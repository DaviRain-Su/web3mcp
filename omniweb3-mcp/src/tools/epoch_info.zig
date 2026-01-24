const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const chain = @import("../core/chain.zig");
const solana_helpers = @import("../core/solana_helpers.zig");

const EpochInfo = solana_sdk.EpochInfo;

/// Get Solana epoch info (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with epoch info
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_epoch_info: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const info: EpochInfo = adapter.getEpochInfo() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get epoch info: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const Response = struct {
        chain: []const u8,
        epoch: u64,
        slot_index: u64,
        slots_in_epoch: u64,
        absolute_slot: u64,
        block_height: u64,
        transaction_count: ?u64 = null,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .epoch = info.epoch,
        .slot_index = info.slot_index,
        .slots_in_epoch = info.slots_in_epoch,
        .absolute_slot = info.absolute_slot,
        .block_height = info.block_height,
        .transaction_count = info.transaction_count,
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
