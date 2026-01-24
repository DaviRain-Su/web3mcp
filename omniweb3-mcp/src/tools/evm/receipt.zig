const std = @import("std");
const mcp = @import("mcp");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");

/// Get EVM transaction receipt by hash.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
/// - tx_hash: Transaction hash (required)
///
/// Returns JSON with transaction receipt (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const tx_hash_str = mcp.tools.getString(args, "tx_hash") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: tx_hash") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for receipt: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const tx_hash = evm_helpers.parseHash(tx_hash_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid transaction hash") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const receipt_response = adapter.getTransactionReceipt(tx_hash) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get receipt: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer receipt_response.deinit();

    const receipt_json = evm_helpers.jsonStringifyAlloc(allocator, receipt_response.response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(receipt_json);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"receipt\":{s}}}",
        .{ chain_name, network, adapter.endpoint, receipt_json },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
