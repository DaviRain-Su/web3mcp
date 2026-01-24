const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_runtime = @import("../../core/evm_runtime.zig");
const evm_helpers = @import("../../core/evm_helpers.zig");
const chain = @import("../../core/chain.zig");

const block = zabi.types.block;
const log_types = zabi.types.log;
const zabi_meta = zabi.meta;

/// Get EVM logs.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - address: Contract address (optional)
/// - from_block: Start block number (optional)
/// - to_block: End block number (optional)
/// - block_hash: Block hash (optional)
/// - topics: Array of topic hashes (optional, use null entries to skip)
/// - tag: latest|pending|earliest (optional)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with logs (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_logs: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const address_str = mcp.tools.getString(args, "address");
    const block_hash_str = mcp.tools.getString(args, "block_hash");
    const from_block_raw = mcp.tools.getInteger(args, "from_block");
    const to_block_raw = mcp.tools.getInteger(args, "to_block");
    const tag_str = mcp.tools.getString(args, "tag");

    if (block_hash_str != null and (from_block_raw != null or to_block_raw != null or tag_str != null)) {
        return mcp.tools.errorResult(allocator, "block_hash cannot be combined with from_block/to_block/tag") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const address = if (address_str) |value| blk: {
        const parsed = evm_helpers.parseAddress(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk parsed;
    } else null;

    const block_hash = if (block_hash_str) |value| blk: {
        const parsed = evm_helpers.parseHash(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid block_hash") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk parsed;
    } else null;

    const from_block = if (from_block_raw) |value| blk: {
        if (value < 0) {
            return mcp.tools.errorResult(allocator, "from_block must be non-negative") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        break :blk @as(u64, @intCast(value));
    } else null;

    const to_block = if (to_block_raw) |value| blk: {
        if (value < 0) {
            return mcp.tools.errorResult(allocator, "to_block must be non-negative") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        break :blk @as(u64, @intCast(value));
    } else null;

    const tag = if (tag_str) |value| parseTag(value) orelse {
        return mcp.tools.errorResult(allocator, "Invalid tag") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    } else null;

    var topics: std.ArrayList(?[]u8) = .empty;
    defer {
        for (topics.items) |topic| {
            if (topic) |bytes| allocator.free(bytes);
        }
        topics.deinit(allocator);
    }

    if (mcp.tools.getArray(args, "topics")) |arr| {
        for (arr.items) |item| {
            if (item == .null) {
                try topics.append(allocator, null);
                continue;
            }
            if (item != .string) {
                return mcp.tools.errorResult(allocator, "Invalid topics entry") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            const hex = evm_helpers.parseHexDataAlloc(allocator, item.string) catch {
                return mcp.tools.errorResult(allocator, "Invalid topic hex") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };
            try topics.append(allocator, hex);
        }
    }

    const request: log_types.LogRequest = .{
        .fromBlock = if (tag != null) null else from_block,
        .toBlock = if (tag != null) null else to_block,
        .address = address,
        .topics = if (topics.items.len > 0) topics.items else null,
        .blockHash = block_hash,
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

    const response = adapter.getLogs(request, tag) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get logs: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer response.deinit();

    const payload = Response{
        .chain = chain_name,
        .logs = response.response,
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
    logs: log_types.Logs,
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
