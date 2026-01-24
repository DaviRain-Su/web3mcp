const std = @import("std");
const mcp = @import("mcp");
const chain = @import("../../core/chain.zig");
const solana_helpers = @import("../../core/solana_helpers.zig");

/// Get Solana block time for a slot (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - slot: Slot number (required)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with block time
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_block_time: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const slot_raw = mcp.tools.getInteger(args, "slot") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: slot") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    if (slot_raw < 0) {
        return mcp.tools.errorResult(allocator, "Invalid slot") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }
    const slot = @as(u64, @intCast(slot_raw));

    const network = mcp.tools.getString(args, "network") orelse "mainnet";
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

    const block_time = adapter.getBlockTime(slot) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get block time: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const Response = struct {
        chain: []const u8,
        slot: u64,
        block_time: ?i64,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .slot = slot,
        .block_time = block_time,
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
