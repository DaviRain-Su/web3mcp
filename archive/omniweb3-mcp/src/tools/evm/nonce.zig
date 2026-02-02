const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");

const block = zabi.types.block;

/// Get EVM account nonce.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - address: Address (required)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
/// - tag: latest|pending|earliest (optional, default: latest)
///
/// Returns JSON with nonce (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const address_str = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const tag_str = mcp.tools.getString(args, "tag") orelse "latest";

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "bsc") or std.ascii.eqlIgnoreCase(chain_name, "polygon") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for nonce: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

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

    const request: block.BalanceRequest = .{ .address = address, .tag = parseBalanceTag(tag_str) };
    const nonce = adapter.getTransactionCount(request) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get nonce: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"{s}\",\"address\":\"{s}\",\"nonce\":{d},\"network\":\"{s}\",\"endpoint\":\"{s}\",\"tag\":\"{s}\"}}",
        .{ chain_name, address_str, nonce, network, adapter.endpoint, tag_str },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn parseBalanceTag(tag: []const u8) ?block.BalanceBlockTag {
    if (std.ascii.eqlIgnoreCase(tag, "latest")) return .latest;
    if (std.ascii.eqlIgnoreCase(tag, "pending")) return .pending;
    if (std.ascii.eqlIgnoreCase(tag, "earliest")) return .earliest;
    return .latest;
}
