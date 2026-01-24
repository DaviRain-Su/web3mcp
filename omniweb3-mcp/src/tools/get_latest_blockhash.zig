const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");

const LatestBlockhash = solana_client.types.LatestBlockhash;
const Hash = solana_sdk.Hash;
const hash_module = solana_sdk.hash;

/// Get latest Solana blockhash (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - network: devnet/testnet/mainnet/localhost (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with latest blockhash
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_latest_blockhash: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const latest: LatestBlockhash = adapter.getLatestBlockhash() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get latest blockhash: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    var hash_buf: [hash_module.MAX_BASE58_LEN]u8 = undefined;
    const hash_str = latest.blockhash.toBase58(&hash_buf);

    const Response = struct {
        chain: []const u8,
        blockhash: []const u8,
        last_valid_block_height: u64,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .blockhash = hash_str,
        .last_valid_block_height = latest.last_valid_block_height,
        .network = network,
        .endpoint = adapter.endpoint,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
