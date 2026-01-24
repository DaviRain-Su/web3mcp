const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_helpers = @import("../core/evm_helpers.zig");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");

const block = zabi.types.block;
const EthCall = zabi.types.transactions.EthCall;
const Wei = zabi.types.ethereum.Wei;

/// Perform an EVM eth_call (read-only).
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
/// - to_address: Target contract address (required)
/// - data: Calldata hex (required)
/// - from_address: Optional sender
/// - value: Optional value in wei
/// - tag: latest|pending|earliest (optional, default: latest)
///
/// Returns JSON with hex result (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const to_str = mcp.tools.getString(args, "to_address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: to_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const data_str = mcp.tools.getString(args, "data") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: data") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const from_str = mcp.tools.getString(args, "from_address");
    const value_str = mcp.tools.getString(args, "value");
    const value_int = mcp.tools.getInteger(args, "value");
    const tag_str = mcp.tools.getString(args, "tag") orelse "latest";

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for call: {s}", .{chain_name}) catch {
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

    const data_bytes = evm_helpers.parseHexDataAlloc(allocator, data_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid data hex") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(data_bytes);

    var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const call = EthCall{ .london = .{ .from = from_address, .to = to_address, .value = value_wei, .data = data_bytes } };
    const request: block.BlockNumberRequest = .{ .tag = parseBalanceTag(tag_str) };

    const response = adapter.call(call, request) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to call contract: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer response.deinit();

    const hex_len = response.response.len * 2;
    const hex_buf = try allocator.alloc(u8, hex_len);
    defer allocator.free(hex_buf);

    const hex_chars = "0123456789abcdef";
    for (response.response, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const result_str = std.fmt.allocPrint(allocator, "0x{s}", .{hex_buf}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(result_str);

    const response_json = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"{s}\",\"to_address\":\"{s}\",\"data\":\"{s}\",\"result\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
        .{ chain_name, to_str, data_str, result_str, network, adapter.endpoint },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response_json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn parseBalanceTag(tag: []const u8) ?block.BalanceBlockTag {
    if (std.ascii.eqlIgnoreCase(tag, "latest")) return .latest;
    if (std.ascii.eqlIgnoreCase(tag, "pending")) return .pending;
    if (std.ascii.eqlIgnoreCase(tag, "earliest")) return .earliest;
    return .latest;
}
