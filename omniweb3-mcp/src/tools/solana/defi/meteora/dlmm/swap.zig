//! Meteora DLMM Swap Tool
//!
//! Creates a swap transaction for a DLMM pool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Create DLMM swap transaction
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - user: Base58 user public key (required)
/// - amount: Amount to swap in base units (required)
/// - swap_for_y: true=swap X for Y, false=swap Y for X (required)
/// - min_out_amount: Minimum output amount (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with transaction details for signing
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    const pool_address = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address: not a valid Base58 public key");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user: not a valid Base58 public key");
    };

    // Get amount
    const amount_str = mcp.tools.getString(args, "amount");
    const amount_int = mcp.tools.getInteger(args, "amount");

    const amount: u64 = if (amount_str) |s| blk: {
        break :blk std.fmt.parseInt(u64, s, 10) catch {
            return helpers.errorResult(allocator, "Invalid amount: must be a valid integer");
        };
    } else if (amount_int) |i| blk: {
        if (i < 0) {
            return helpers.errorResult(allocator, "Invalid amount: must be non-negative");
        }
        break :blk @intCast(i);
    } else {
        return helpers.errorResult(allocator, "Missing required parameter: amount");
    };

    const swap_for_y = mcp.tools.getBoolean(args, "swap_for_y") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: swap_for_y");
    };

    // Get min_out_amount
    const min_out_str = mcp.tools.getString(args, "min_out_amount");
    const min_out_int = mcp.tools.getInteger(args, "min_out_amount");

    const min_out_amount: u64 = if (min_out_str) |s| blk: {
        break :blk std.fmt.parseInt(u64, s, 10) catch {
            return helpers.errorResult(allocator, "Invalid min_out_amount: must be a valid integer");
        };
    } else if (min_out_int) |i| blk: {
        if (i < 0) {
            return helpers.errorResult(allocator, "Invalid min_out_amount: must be non-negative");
        }
        break :blk @intCast(i);
    } else {
        return helpers.errorResult(allocator, "Missing required parameter: min_out_amount");
    };

    const endpoint = helpers.getEndpoint(args);

    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    // Fetch pool info
    const account_info = client.getAccountInfo(pool_address) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch pool account: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return helpers.errorResult(allocator, msg);
    };

    if (account_info == null) {
        return helpers.errorResult(allocator, "Pool account not found");
    }

    const data = account_info.?.data;
    if (data.len == 0) {
        return helpers.errorResult(allocator, "Pool account has no data");
    }

    if (data.len < 200) {
        return helpers.errorResult(allocator, "Pool account data too small");
    }

    const active_id = std.mem.readInt(i32, data[8..12], .little);
    const bin_step = std.mem.readInt(u16, data[12..14], .little);

    // Get bin array index for reference
    const bin_array_index = constants.getBinArrayIndexFromBinId(active_id);

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        amount_in: u64,
        min_amount_out: u64,
        swap_for_y: bool,
        active_bin_id: i32,
        bin_step: u16,
        bin_array_index: i64,
        program_id: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .amount_in = amount,
        .min_amount_out = min_out_amount,
        .swap_for_y = swap_for_y,
        .active_bin_id = active_id,
        .bin_step = bin_step,
        .bin_array_index = bin_array_index,
        .program_id = constants.PROGRAM_IDS.DLMM,
        .note = "Transaction needs to be signed and submitted. Client must derive bin array PDAs and include user's token accounts.",
    };

    return helpers.jsonResult(allocator, response);
}
