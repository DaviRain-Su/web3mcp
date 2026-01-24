const std = @import("std");
const mcp = @import("mcp");
const evm_helpers = @import("../core/evm_helpers.zig");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");

/// Get EVM balance tool handler
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - address: Hex address (required)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with balance info
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const address_str = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    const address = evm_helpers.parseAddress(address_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid EVM address") catch {
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

    const balance = adapter.getBalance(address) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get balance: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const wei_str = evm_helpers.formatU256(allocator, balance) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(wei_str);

    const eth_str = evm_helpers.formatWeiToEthString(allocator, balance) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(eth_str);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"address\":\"{s}\",\"balance_wei\":\"{s}\",\"balance_eth\":\"{s}\",\"chain\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
        .{ address_str, wei_str, eth_str, chain_name, network, adapter.endpoint },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
