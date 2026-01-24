const std = @import("std");
const mcp = @import("mcp");
const chain = @import("../../core/chain.zig");

/// Get current Solana block height (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with block height
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_block_height: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const network = mcp.tools.getString(args, "network") orelse "mainnet";
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

    const height = adapter.getBlockHeight() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get block height: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"solana\",\"block_height\":{d},\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
        .{ height, network, adapter.endpoint },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
