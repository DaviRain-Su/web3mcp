const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");
const wallet = @import("../core/wallet.zig");

const PublicKey = solana_sdk.PublicKey;

/// Get Solana wallet address from configured keypair (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - keypair_path: Solana keypair path (optional)
///
/// Returns JSON with wallet address
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_wallet_address: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const keypair_path_override = mcp.tools.getString(args, "keypair_path");

    const keypair = wallet.loadSolanaKeypair(allocator, keypair_path_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to load Solana keypair: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    var buf: [PublicKey.max_base58_len]u8 = undefined;
    const address = keypair.pubkey().toBase58(&buf);

    const Response = struct {
        chain: []const u8,
        address: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .address = address,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
