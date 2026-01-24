const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../core/solana_helpers.zig");
const solana_sdk = @import("solana_sdk");
const evm_helpers = @import("../core/evm_helpers.zig");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");
const block = @import("zabi").types.block;

/// Get block information (Solana/EVM).
///
/// Parameters:
/// - chain: "solana" | "ethereum" | "avalanche" | "bnb" (optional, default: solana)
/// - network: Solana: devnet/testnet/mainnet/localhost; EVM: mainnet/sepolia/goerli/fuji/testnet
/// - endpoint: Override RPC endpoint (optional)
/// - block_number: EVM block height or Solana slot (optional)
/// - slot: Solana slot (optional)
/// - block_hash: EVM block hash (optional)
/// - tag: latest|earliest|pending|safe|finalized (EVM optional)
/// - include_transactions: Include full transactions (optional, default: false)
///
/// Returns JSON with block info
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    const network_raw = mcp.tools.getString(args, "network");
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const block_number_raw = mcp.tools.getInteger(args, "block_number");
    const slot_raw = mcp.tools.getInteger(args, "slot");
    const block_hash_str = mcp.tools.getString(args, "block_hash");
    const include_txs = mcp.tools.getBoolean(args, "include_transactions") orelse false;
    const tag_str = mcp.tools.getString(args, "tag") orelse "latest";

    if (std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        if (block_hash_str != null) {
            return mcp.tools.errorResult(allocator, "block_hash is not supported for Solana") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        if (slot_raw != null and block_number_raw != null) {
            return mcp.tools.errorResult(allocator, "Specify either slot or block_number") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const network = network_raw orelse "devnet";
        var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const slot = if (slot_raw) |value|
            @as(u64, @intCast(value))
        else if (block_number_raw) |value|
            @as(u64, @intCast(value))
        else
            adapter.getSlot() catch |err| {
                const msg = std.fmt.allocPrint(allocator, "Failed to get slot: {s}", .{@errorName(err)}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                return mcp.tools.errorResult(allocator, msg) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            };

        const block_opt = adapter.getBlock(slot, include_txs) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get block: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        if (block_opt == null) {
            return mcp.tools.errorResult(allocator, "Block not found") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const block_value = block_opt.?;

        var hash_buf: [solana_sdk.hash.MAX_BASE58_LEN]u8 = undefined;
        var prev_buf: [solana_sdk.hash.MAX_BASE58_LEN]u8 = undefined;
        const blockhash_str = block_value.blockhash.toBase58(&hash_buf);
        const prev_hash_str = block_value.previous_blockhash.toBase58(&prev_buf);

        const blockhash_owned = allocator.dupe(u8, blockhash_str) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(blockhash_owned);
        const prev_owned = allocator.dupe(u8, prev_hash_str) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(prev_owned);

        var transactions: ?[]const []const u8 = null;
        var allocated = std.array_list.Managed([]u8).init(allocator);
        defer {
            for (allocated.items) |item| allocator.free(item);
            allocated.deinit();
        }

        if (include_txs) {
            if (block_value.transactions) |txs| {
                const list = try allocator.alloc([]const u8, txs.len);
                transactions = list;
                for (txs, 0..) |tx, i| {
                    const data_owned = try allocator.dupe(u8, tx.transaction.data);
                    try allocated.append(data_owned);
                    list[i] = data_owned;
                }
            }
        }
        defer if (transactions) |list| allocator.free(list);

        const Response = struct {
            chain: []const u8,
            slot: u64,
            blockhash: []const u8,
            previous_blockhash: []const u8,
            block_time: ?i64 = null,
            block_height: ?u64 = null,
            transaction_count: usize,
            transactions: ?[]const []const u8 = null,
            network: []const u8,
            endpoint: []const u8,
        };

        const response_value: Response = .{
            .chain = "solana",
            .slot = slot,
            .blockhash = blockhash_owned,
            .previous_blockhash = prev_owned,
            .block_time = block_value.block_time,
            .block_height = block_value.block_height,
            .transaction_count = if (block_value.transactions) |txs| txs.len else 0,
            .transactions = transactions,
            .network = network,
            .endpoint = adapter.endpoint,
        };

        const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(json);

        return mcp.tools.textResult(allocator, json) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

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

    const network = network_raw orelse "mainnet";
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
