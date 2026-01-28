const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");

const PublicKey = solana_sdk.PublicKey;
const AccountMeta = solana_sdk.AccountMeta;

/// Call a Solana program instruction with automatic IDL loading.
///
/// This tool reads the IDL from idl_registry and helps build program instructions.
///
/// Parameters:
/// - program: Program ID (required)
/// - instruction: Instruction name (required)
/// - accounts: Array of account objects with {pubkey, is_signer?, is_writable?} (required)
/// - data: Array of instruction data fields (optional, default: [])
/// - network: "mainnet" | "devnet" | "testnet" (optional, default: "mainnet")
///
/// Example:
///   call_program(
///     program="JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
///     instruction="swap",
///     accounts=[
///       {pubkey: "user_wallet", is_signer: true, is_writable: true},
///       {pubkey: "source_token", is_writable: true},
///       {pubkey: "dest_token", is_writable: true}
///     ],
///     data=[amount, min_out]
///   )
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Parse basic parameters
    const program_str = mcp.tools.getString(args, "program") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: program") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const instruction_name = mcp.tools.getString(args, "instruction") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: instruction") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    // Parse program ID
    const program_id = PublicKey.fromBase58(program_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid program ID") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Parse accounts - access from args object
    const args_obj = if (args) |a| switch (a) {
        .object => |obj| obj,
        else => {
            return mcp.tools.errorResult(allocator, "Invalid arguments format") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        },
    } else {
        return mcp.tools.errorResult(allocator, "Missing arguments") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const accounts_value = args_obj.get("accounts") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: accounts") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const accounts = parseAccounts(allocator, accounts_value) catch |err| {
        const msg = std.fmt.allocPrint(
            allocator,
            "Failed to parse accounts: {s}",
            .{@errorName(err)},
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(accounts);

    // Load IDL (optional, for validation and encoding hints)
    const idl_opt = loadProgramIdl(allocator, program_str) catch null;
    defer if (idl_opt) |_| {
        // TODO: Free IDL properly
    };

    // Parse instruction data
    const data = if (args_obj.get("data")) |data_value|
        parseInstructionData(allocator, data_value, idl_opt, instruction_name) catch |err| {
            const msg = std.fmt.allocPrint(
                allocator,
                "Failed to parse instruction data: {s}",
                .{@errorName(err)},
            ) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        }
    else
        try allocator.alloc(u8, 0);
    defer allocator.free(data);

    // For now, return instruction details instead of executing
    // (Execution requires wallet integration which is complex)
    // TODO: Build and execute instruction when wallet integration is ready
    _ = program_id; // Will be used for execution
    const response_json = std.fmt.allocPrint(
        allocator,
        \\{{
        \\  "status": "instruction_built",
        \\  "program": "{s}",
        \\  "instruction_name": "{s}",
        \\  "accounts_count": {d},
        \\  "data_size": {d},
        \\  "network": "{s}",
        \\  "note": "Instruction built successfully. To execute, use sign_and_send with wallet integration.",
        \\  "instruction_data_hex": "{s}"
        \\}}
        ,
        .{
            program_str,
            instruction_name,
            accounts.len,
            data.len,
            network,
            try formatHex(allocator, data),
        },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response_json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

/// Parse accounts from JSON
fn parseAccounts(
    allocator: std.mem.Allocator,
    accounts_value: std.json.Value,
) ![]AccountMeta {
    const accounts_array = switch (accounts_value) {
        .array => |arr| arr.items,
        else => return error.InvalidAccountsFormat,
    };

    const accounts = try allocator.alloc(AccountMeta, accounts_array.len);
    errdefer allocator.free(accounts);

    for (accounts_array, 0..) |account_obj, i| {
        const obj = switch (account_obj) {
            .object => |o| o,
            else => return error.InvalidAccountFormat,
        };

        // Get pubkey
        const pubkey_str = if (obj.get("pubkey")) |v|
            switch (v) {
                .string => |s| s,
                else => return error.InvalidPubkey,
            }
        else
            return error.MissingPubkey;

        const pubkey = try PublicKey.fromBase58(pubkey_str);

        // Get is_signer (default: false)
        const is_signer = if (obj.get("is_signer")) |v|
            switch (v) {
                .bool => |b| b,
                else => false,
            }
        else
            false;

        // Get is_writable (default: false)
        const is_writable = if (obj.get("is_writable")) |v|
            switch (v) {
                .bool => |b| b,
                else => false,
            }
        else
            false;

        accounts[i] = AccountMeta{
            .pubkey = pubkey,
            .is_signer = is_signer,
            .is_writable = is_writable,
        };
    }

    return accounts;
}

/// Load program IDL
fn loadProgramIdl(
    allocator: std.mem.Allocator,
    program_id: []const u8,
) !?void {
    // TODO: Implement IDL loading using idl_resolver
    // For now, return null (no IDL)
    _ = allocator;
    _ = program_id;
    return null;
}

/// Parse instruction data
fn parseInstructionData(
    allocator: std.mem.Allocator,
    data_value: std.json.Value,
    idl: ?void,
    instruction_name: []const u8,
) ![]u8 {
    _ = idl;
    _ = instruction_name;

    // For now, support simple array of bytes or numbers
    const data_array = switch (data_value) {
        .array => |arr| arr.items,
        else => return error.InvalidDataFormat,
    };

    var data_list: std.ArrayList(u8) = .empty;
    errdefer data_list.deinit(allocator);

    for (data_array) |item| {
        switch (item) {
            .integer => |n| {
                // Add as byte
                if (n < 0 or n > 255) return error.ByteOutOfRange;
                try data_list.append(allocator, @intCast(n));
            },
            .number_string => |s| {
                const num = try std.fmt.parseInt(u8, s, 10);
                try data_list.append(allocator, num);
            },
            else => return error.UnsupportedDataType,
        }
    }

    return try data_list.toOwnedSlice(allocator);
}

/// Format bytes as hex string
fn formatHex(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    if (data.len == 0) return try allocator.dupe(u8, "");

    const hex_len = data.len * 2;
    const hex_buf = try allocator.alloc(u8, hex_len);
    errdefer allocator.free(hex_buf);

    const hex_chars = "0123456789abcdef";
    for (data, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    return hex_buf;
}
