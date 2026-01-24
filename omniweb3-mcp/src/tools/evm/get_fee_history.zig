const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");

const block = zabi.types.block;
const FeeHistory = zabi.types.transactions.FeeHistory;
const zabi_meta = zabi.meta;

/// Get EVM fee history.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - block_count: Number of blocks (required)
/// - newest_block: Block tag (latest/pending/earliest) or block number (optional, default: latest)
/// - reward_percentiles: Array of reward percentiles (optional)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with fee history (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_fee_history: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const block_count_raw = mcp.tools.getInteger(args, "block_count") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: block_count") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    if (block_count_raw <= 0) {
        return mcp.tools.errorResult(allocator, "block_count must be positive") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }
    const block_count: u64 = @intCast(block_count_raw);

    const newest_block_str = mcp.tools.getString(args, "newest_block");
    const newest_block_int = mcp.tools.getInteger(args, "newest_block");

    const newest_request: block.BlockNumberRequest = if (newest_block_int != null and newest_block_int.? >= 0) blk: {
        break :blk .{ .block_number = @intCast(newest_block_int.?) };
    } else blk: {
        const tag = parseTag(newest_block_str orelse "latest") orelse {
            return mcp.tools.errorResult(allocator, "Invalid newest_block tag") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk .{ .tag = tag };
    };

    var percentiles: std.ArrayList(f64) = .empty;
    defer percentiles.deinit(allocator);

    if (mcp.tools.getArray(args, "reward_percentiles")) |arr| {
        for (arr.items) |item| {
            const value = switch (item) {
                .float => item.float,
                .integer => @as(f64, @floatFromInt(item.integer)),
                else => return mcp.tools.errorResult(allocator, "Invalid reward_percentiles entry") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                },
            };
            try percentiles.append(allocator, value);
        }
    }

    const reward_slice: ?[]const f64 = if (percentiles.items.len > 0) percentiles.items else null;

    var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const response = adapter.getFeeHistory(block_count, newest_request, reward_slice) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get fee history: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer response.deinit();

    const payload = Response{
        .chain = chain_name,
        .fee_history = response.response,
        .network = network,
        .endpoint = adapter.endpoint,
    };

    const json = jsonStringifyAlloc(allocator, payload) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

const Response = struct {
    chain: []const u8,
    fee_history: FeeHistory,
    network: []const u8,
    endpoint: []const u8,
};

fn parseTag(tag: []const u8) ?block.BalanceBlockTag {
    if (std.ascii.eqlIgnoreCase(tag, "latest")) return .latest;
    if (std.ascii.eqlIgnoreCase(tag, "pending")) return .pending;
    if (std.ascii.eqlIgnoreCase(tag, "earliest")) return .earliest;
    return null;
}

fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .emit_null_optional_fields = false },
    };

    try zabi_meta.json.jsonStringify(@TypeOf(value), value, &stringify);
    return out.toOwnedSlice();
}
