const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");

const RpcClient = solana_client.RpcClient;
const PublicKey = solana_sdk.PublicKey;
const Keypair = solana_sdk.Keypair;
const AccountMeta = solana_sdk.AccountMeta;

const TransactionBuilder = solana_client.TransactionBuilder;
const InstructionInput = solana_client.transaction.InstructionInput;

/// Lamports per SOL
const LAMPORTS_PER_SOL: u64 = 1_000_000_000;

// C interop for getenv
const c = @cImport({
    @cInclude("stdlib.h");
});

/// Get default keypair path
/// Priority: SOLANA_KEYPAIR env > ~/.config/solana/id.json
fn getDefaultKeypairPath(allocator: std.mem.Allocator) ![]const u8 {
    // First check SOLANA_KEYPAIR environment variable
    if (c.getenv("SOLANA_KEYPAIR")) |env_path_c| {
        const env_path = std.mem.span(env_path_c);
        return allocator.dupe(u8, env_path);
    }

    // Fall back to ~/.config/solana/id.json
    const home_c = c.getenv("HOME") orelse return error.HomeNotFound;
    const home = std.mem.span(home_c);
    return std.fmt.allocPrint(allocator, "{s}/.config/solana/id.json", .{home});
}

/// Load keypair from JSON file (Solana CLI format: [u8; 64] array)
fn loadKeypairFromFile(allocator: std.mem.Allocator, path: []const u8) !Keypair {
    // Add null terminator for C path
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    
    // Open file using Linux syscall
    const flags: std.os.linux.O = .{ .ACCMODE = .RDONLY };
    const fd = std.os.linux.open(path_z.ptr, flags, 0);
    if (fd < 0) return error.KeypairFileNotFound;
    defer _ = std.os.linux.close(@intCast(fd));
    
    // Read file content
    var buffer: [1024]u8 = undefined;
    const bytes_read = std.os.linux.read(@intCast(fd), buffer[0..].ptr, buffer.len);
    if (bytes_read < 0) return error.KeypairReadFailed;
    
    const content = try allocator.dupe(u8, buffer[0..@intCast(bytes_read)]);
    defer allocator.free(content);

    // Parse JSON array of bytes
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        return error.KeypairParseError;
    };
    defer parsed.deinit();

    if (parsed.value != .array) {
        return error.KeypairInvalidFormat;
    }

    const arr = parsed.value.array;
    if (arr.items.len != 64) {
        return error.KeypairInvalidLength;
    }

    var keypair_bytes: [64]u8 = undefined;
    for (arr.items, 0..) |item, i| {
        if (item != .integer) {
            return error.KeypairInvalidFormat;
        }
        keypair_bytes[i] = @intCast(item.integer);
    }

    return Keypair.fromBytes(&keypair_bytes) catch {
        return error.KeypairInvalid;
    };
}

/// System Program ID (all zeros)
const SYSTEM_PROGRAM_ID: [32]u8 = [_]u8{0} ** 32;

/// System Program instruction discriminators
const SystemInstruction = enum(u32) {
    CreateAccount = 0,
    Assign = 1,
    Transfer = 2,
    CreateAccountWithSeed = 3,
    AdvanceNonceAccount = 4,
    WithdrawNonceAccount = 5,
    InitializeNonceAccount = 6,
    AuthorizeNonceAccount = 7,
    Allocate = 8,
    AllocateWithSeed = 9,
    AssignWithSeed = 10,
    TransferWithSeed = 11,
    UpgradeNonceAccount = 12,
};

/// Create a System Program transfer instruction
/// Caller must free the returned data and accounts slices
fn createTransferInstruction(
    allocator: std.mem.Allocator,
    from_pubkey: PublicKey,
    to_pubkey: PublicKey,
    lamports: u64,
) !InstructionInput {
    // Allocate instruction data: 4 bytes discriminator + 8 bytes lamports (little endian)
    const instruction_data = try allocator.alloc(u8, 12);
    errdefer allocator.free(instruction_data);

    // Write discriminator (Transfer = 2)
    std.mem.writeInt(u32, instruction_data[0..4], @intFromEnum(SystemInstruction.Transfer), .little);
    // Write lamports
    std.mem.writeInt(u64, instruction_data[4..12], lamports, .little);

    // Allocate accounts
    const accounts = try allocator.alloc(AccountMeta, 2);
    errdefer allocator.free(accounts);

    accounts[0] = AccountMeta.newWritableSigner(from_pubkey);
    accounts[1] = AccountMeta.newWritable(to_pubkey);

    return .{
        .program_id = PublicKey.from(SYSTEM_PROGRAM_ID),
        .accounts = accounts,
        .data = instruction_data,
    };
}

/// Transfer SOL tool handler
/// Transfers native SOL from one account to another on Solana
///
/// Parameters:
/// - to_address: Base58 encoded recipient address (required)
/// - amount: Amount to transfer in lamports (required)
/// - network: "devnet" | "mainnet" | "testnet" | "localhost" (optional, default: devnet)
/// - keypair_path: Path to keypair JSON file (optional, default: ~/.config/solana/id.json)
///
/// Returns JSON with transaction signature
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Get keypair path (from arg, env var, or default)
    const keypair_path_override = mcp.tools.getString(args, "keypair_path");
    const keypair_path = if (keypair_path_override) |p| blk: {
        break :blk allocator.dupe(u8, p) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    } else blk: {
        break :blk getDefaultKeypairPath(allocator) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get default keypair path: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
    };
    defer allocator.free(keypair_path);

    const to_address_str = mcp.tools.getString(args, "to_address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: to_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount = mcp.tools.getInteger(args, "amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount (in lamports)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    if (amount <= 0) {
        return mcp.tools.errorResult(allocator, "Amount must be positive") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const network_str = mcp.tools.getString(args, "network") orelse "devnet";

    // Get endpoint based on network
    const endpoint: []const u8 = if (std.mem.eql(u8, network_str, "mainnet"))
        "https://api.mainnet-beta.solana.com"
    else if (std.mem.eql(u8, network_str, "testnet"))
        "https://api.testnet.solana.com"
    else if (std.mem.eql(u8, network_str, "localhost"))
        "http://localhost:8899"
    else
        "https://api.devnet.solana.com";

    // Load sender keypair from file
    const sender_keypair = loadKeypairFromFile(allocator, keypair_path) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to load keypair from '{s}': {s}", .{ keypair_path, @errorName(err) }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // Parse recipient address
    const to_pubkey = PublicKey.fromBase58(to_address_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid recipient address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const from_pubkey = sender_keypair.pubkey();
    const lamports: u64 = @intCast(amount);

    // Create RPC client
    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    // Get latest blockhash
    const blockhash_result = client.getLatestBlockhash() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get latest blockhash: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // Build transfer transaction
    var builder = TransactionBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.setFeePayer(from_pubkey);
    _ = builder.setRecentBlockhash(blockhash_result.blockhash);

    const transfer_ix = createTransferInstruction(allocator, from_pubkey, to_pubkey, lamports) catch {
        return mcp.tools.errorResult(allocator, "Failed to create transfer instruction") catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(transfer_ix.data);
    defer allocator.free(transfer_ix.accounts);

    _ = builder.addInstruction(transfer_ix) catch {
        return mcp.tools.errorResult(allocator, "Failed to add transfer instruction") catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // Build and sign transaction
    var tx = builder.buildSigned(&[_]*const Keypair{&sender_keypair}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to build/sign transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer tx.deinit();

    // Serialize transaction
    const serialized = tx.serialize() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to serialize transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(serialized);

    // Send transaction with skip_preflight for better error messages
    const signature = client.sendTransactionWithConfig(serialized, .{ .skip_preflight = true }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to send transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // Format signature as base58
    // Signature is 64 bytes, base58 encoded max is 88 chars
    var sig_buf: [88]u8 = undefined;
    const sig_str = signature.toBase58(&sig_buf);

    // Format response
    var from_buf: [PublicKey.max_base58_len]u8 = undefined;
    const from_str = from_pubkey.toBase58(&from_buf);

    const sol_amount = @as(f64, @floatFromInt(lamports)) / @as(f64, @floatFromInt(LAMPORTS_PER_SOL));

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"status\":\"success\",\"signature\":\"{s}\",\"from\":\"{s}\",\"to\":\"{s}\",\"lamports\":{d},\"sol\":{d:.9},\"network\":\"{s}\"}}",
        .{ sig_str, from_str, to_address_str, lamports, sol_amount, network_str },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
