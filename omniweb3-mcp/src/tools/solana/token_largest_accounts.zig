const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");

const json_rpc = solana_client.json_rpc;

/// Get SPL token largest accounts (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - mint: Base58 mint address (required)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with largest accounts
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_token_largest_accounts: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const mint_str = mcp.tools.getString(args, "mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    _ = solana_helpers.parsePublicKey(mint_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid mint address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

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

    try params_arr.append(json_rpc.jsonString(mint_str));

    var cfg = json_rpc.jsonObject(allocator);
    defer cfg.deinit();
    try cfg.put("commitment", json_rpc.jsonString(adapter.client.commitment.commitment.toJsonString()));
    try params_arr.append(.{ .object = cfg });

    var result = adapter.client.json_rpc.callWithResult(allocator, "getTokenLargestAccounts", .{ .array = params_arr }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token largest accounts: {s}", .{@errorName(err)}) catch {
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
        return mcp.tools.errorResult(allocator, "Missing token largest accounts result") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const accounts_json = solana_helpers.jsonStringifyAlloc(allocator, value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(accounts_json);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"solana\",\"mint\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"accounts\":{s}}}",
        .{ mint_str, network, adapter.endpoint, accounts_json },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
