const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");
const wallet = @import("../../core/wallet.zig");

const PublicKey = solana_sdk.PublicKey;

/// Request SOL airdrop (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - address: Base58 address (optional, default: keypair pubkey)
/// - amount: Lamports to airdrop (required)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
/// - keypair_path: Optional keypair path (used if address not provided)
///
/// Returns JSON with airdrop signature
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for request_airdrop: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const amount_raw = mcp.tools.getInteger(args, "amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    if (amount_raw <= 0) {
        return mcp.tools.errorResult(allocator, "Amount must be positive") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }
    const lamports: u64 = @intCast(amount_raw);

    const address_str = mcp.tools.getString(args, "address");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    var address_buf: [PublicKey.max_base58_len]u8 = undefined;
    const pubkey: PublicKey = if (address_str) |value| blk: {
        break :blk solana_helpers.parsePublicKey(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid Solana address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
    } else blk: {
        const keypair = wallet.loadSolanaKeypair(allocator, keypair_path) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to load keypair: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        break :blk keypair.pubkey();
    };

    const address_out = address_str orelse pubkey.toBase58(&address_buf);

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const signature = adapter.requestAirdrop(pubkey, lamports) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to request airdrop: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    var sig_buf: [solana_sdk.signature.MAX_BASE58_LEN]u8 = undefined;
    const sig_str = signature.toBase58(&sig_buf);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"solana\",\"address\":\"{s}\",\"lamports\":{d},\"signature\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
        .{ address_out, lamports, sig_str, network, adapter.endpoint },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
