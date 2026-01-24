const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_helpers = @import("../core/evm_helpers.zig");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");

const EthCall = zabi.types.transactions.EthCall;
const Wei = zabi.types.ethereum.Wei;

/// Estimate EVM gas for a call.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
/// - from_address: Optional sender address
/// - to_address: Target address (required)
/// - value: Optional value in wei (string or integer)
/// - data: Optional calldata hex (0x...)
///
/// Returns JSON with gas estimate (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const from_str = mcp.tools.getString(args, "from_address");
    const to_str = mcp.tools.getString(args, "to_address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: to_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const data_str = mcp.tools.getString(args, "data");
    const value_str = mcp.tools.getString(args, "value");
    const value_int = mcp.tools.getInteger(args, "value");

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for estimate_gas: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const to_address = evm_helpers.parseAddress(to_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid to_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const from_address = if (from_str) |value| blk: {
        const addr = evm_helpers.parseAddress(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid from_address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk addr;
    } else null;

    const value_wei: ?Wei = if (value_str != null or value_int != null) blk: {
        if (value_str) |value| {
            const parsed = evm_helpers.parseWeiAmount(value) catch {
                return mcp.tools.errorResult(allocator, "Invalid value") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };
            break :blk parsed;
        }
        const int_value = value_int.?;
        if (int_value < 0) {
            return mcp.tools.errorResult(allocator, "Invalid value") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        break :blk @as(Wei, @intCast(int_value));
    } else null;

    var data_bytes: ?[]u8 = null;
    defer if (data_bytes) |bytes| allocator.free(bytes);
    if (data_str) |value| {
        data_bytes = evm_helpers.parseHexDataAlloc(allocator, value) catch {
            return mcp.tools.errorResult(allocator, "Invalid data hex") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
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

    const call = EthCall{ .london = .{
        .from = from_address,
        .to = to_address,
        .value = value_wei,
        .data = data_bytes,
    } };

    const gas_estimate = adapter.estimateGas(call) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to estimate gas: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"{s}\",\"to_address\":\"{s}\",\"gas_estimate\":{d},\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
        .{ chain_name, to_str, gas_estimate, network, adapter.endpoint },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
