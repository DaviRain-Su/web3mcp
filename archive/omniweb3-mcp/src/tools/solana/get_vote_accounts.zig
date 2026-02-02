const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");

const json_rpc = solana_client.json_rpc;

/// Get vote accounts (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - network: devnet/testnet/mainnet/localhost (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with vote accounts payload
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_vote_accounts: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

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

    var params_arr = std.json.Array.init(allocator);
    defer params_arr.deinit();

    var config_obj = json_rpc.jsonObject(allocator);
    defer config_obj.deinit();
    try config_obj.put("commitment", json_rpc.jsonString(adapter.client.commitment.commitment.toJsonString()));
    try params_arr.append(.{ .object = config_obj });

    var result = adapter.client.json_rpc.callWithResult(allocator, "getVoteAccounts", .{ .array = params_arr }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get vote accounts: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer result.deinit();

    if (result.rpc_error) |rpc_err| {
        const msg = std.fmt.allocPrint(allocator, "RPC error: {s}", .{rpc_err.message}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const value = result.value orelse {
        return mcp.tools.errorResult(allocator, "Missing vote accounts result") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const votes_json = solana_helpers.jsonStringifyAlloc(allocator, value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(votes_json);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"solana\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"vote_accounts\":{s}}}",
        .{ network, adapter.endpoint, votes_json },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
