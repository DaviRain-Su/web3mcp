const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");

/// Get EVM chain id.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with chain id (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_chain_id: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const chain_id = adapter.getChainId() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get chain id: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"chain_id\":{d}}}",
        .{ chain_name, network, adapter.endpoint, chain_id },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
