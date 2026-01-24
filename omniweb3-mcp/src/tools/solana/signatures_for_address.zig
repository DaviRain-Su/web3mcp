const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");

const json_rpc = solana_client.json_rpc;

/// Get signatures for a Solana address (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - address: Base58 address (required)
/// - limit: Max signatures (optional)
/// - before: Signature to start before (optional)
/// - until: Signature to stop at (optional)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with signature list
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_signatures_for_address: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const address_str = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const limit_raw = mcp.tools.getInteger(args, "limit");
    const before_str = mcp.tools.getString(args, "before");
    const until_str = mcp.tools.getString(args, "until");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    _ = solana_helpers.parsePublicKey(address_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid address") catch {
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

    const limit: ?u32 = if (limit_raw) |value| if (value > 0) @as(u32, @intCast(value)) else null else null;
    if (before_str) |value| {
        _ = solana_helpers.parseSignature(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid before signature") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
    }
    if (until_str) |value| {
        _ = solana_helpers.parseSignature(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid until signature") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
    }

    var params_arr = std.json.Array.init(allocator);
    defer params_arr.deinit();

    try params_arr.append(json_rpc.jsonString(address_str));

    var cfg = json_rpc.jsonObject(allocator);
    defer cfg.deinit();
    try cfg.put("commitment", json_rpc.jsonString(adapter.client.commitment.commitment.toJsonString()));
    if (limit) |value| {
        try cfg.put("limit", json_rpc.jsonInt(@intCast(value)));
    }
    if (before_str) |value| {
        try cfg.put("before", json_rpc.jsonString(value));
    }
    if (until_str) |value| {
        try cfg.put("until", json_rpc.jsonString(value));
    }
    try params_arr.append(.{ .object = cfg });

    var result = adapter.client.json_rpc.callWithResult(allocator, "getSignaturesForAddress", .{ .array = params_arr }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get signatures: {s}", .{@errorName(err)}) catch {
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
        return mcp.tools.errorResult(allocator, "Missing signatures result") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const signatures_json = solana_helpers.jsonStringifyAlloc(allocator, value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(signatures_json);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"chain\":\"solana\",\"address\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"signatures\":{s}}}",
        .{ address_str, network, adapter.endpoint, signatures_json },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
