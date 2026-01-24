const std = @import("std");
const mcp = @import("mcp");
const evm_helpers = @import("../core/evm_helpers.zig");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");
const block = @import("zabi").types.block;

/// Get EVM block information.
///
/// Parameters:
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
/// - block_number: Block height (optional)
/// - block_hash: Block hash (optional)
/// - tag: latest|earliest|pending|safe|finalized (optional, default: latest)
/// - include_transactions: Include full transactions (optional, default: false)
///
/// Returns JSON with block info (EVM only)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const block_number_raw = mcp.tools.getInteger(args, "block_number");
    const block_hash_str = mcp.tools.getString(args, "block_hash");
    const include_txs = mcp.tools.getBoolean(args, "include_transactions") orelse false;
    const tag_str = mcp.tools.getString(args, "tag") orelse "latest";

    if (block_number_raw != null and block_hash_str != null) {
        return mcp.tools.errorResult(allocator, "Specify either block_number or block_hash, not both") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (!(std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm"))) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for block: {s}", .{chain_name}) catch {
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

    const block_response = if (block_hash_str) |hash_str| blk: {
        const hash = evm_helpers.parseHash(hash_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid block hash") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        const request: block.BlockHashRequest = .{
            .block_hash = hash,
            .include_transaction_objects = include_txs,
        };
        break :blk adapter.getBlockByHash(request) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get block by hash: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
    } else blk: {
        const request: block.BlockRequest = .{
            .block_number = if (block_number_raw) |value| @intCast(value) else null,
            .tag = if (block_number_raw == null) parseBlockTag(tag_str) else null,
            .include_transaction_objects = include_txs,
        };
        break :blk adapter.getBlockByNumber(request) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get block: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
    };
    defer block_response.deinit();

    const block_json = evm_helpers.jsonStringifyAlloc(allocator, block_response.response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(block_json);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"block\":{s}}}",
        .{ chain_name, network, adapter.endpoint, block_json },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn parseBlockTag(tag: []const u8) ?block.BlockTag {
    if (std.ascii.eqlIgnoreCase(tag, "latest")) return .latest;
    if (std.ascii.eqlIgnoreCase(tag, "earliest")) return .earliest;
    if (std.ascii.eqlIgnoreCase(tag, "pending")) return .pending;
    if (std.ascii.eqlIgnoreCase(tag, "safe")) return .safe;
    if (std.ascii.eqlIgnoreCase(tag, "finalized")) return .finalized;
    return .latest;
}
