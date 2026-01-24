const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");

/// Get recent TPS from Solana performance samples (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
/// - limit: Sample count (optional, default: 1)
///
/// Returns JSON with TPS estimate
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_tps: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const limit_raw = mcp.tools.getInteger(args, "limit");
    const limit = if (limit_raw) |value| if (value > 0) @as(u64, @intCast(value)) else 1 else 1;

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const samples = adapter.getRecentPerformanceSamples(limit) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get performance samples: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(samples);

    if (samples.len == 0) {
        return mcp.tools.errorResult(allocator, "No performance samples found") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const sample = samples[0];
    const tps = if (sample.sample_period_secs > 0)
        @as(f64, @floatFromInt(sample.num_transactions)) / @as(f64, @floatFromInt(sample.sample_period_secs))
    else
        0.0;

    const Response = struct {
        chain: []const u8,
        slot: u64,
        tps: f64,
        sample_period_secs: u16,
        num_transactions: u64,
        num_slots: u64,
        num_non_vote_transactions: ?u64 = null,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .slot = sample.slot,
        .tps = tps,
        .sample_period_secs = sample.sample_period_secs,
        .num_transactions = sample.num_transactions,
        .num_slots = sample.num_slots,
        .num_non_vote_transactions = sample.num_non_vote_transactions,
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
