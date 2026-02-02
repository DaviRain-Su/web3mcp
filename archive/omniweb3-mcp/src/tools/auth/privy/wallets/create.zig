//! Privy Create Wallet Tool
//!
//! Creates a new embedded wallet on the specified chain.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// Create a new Privy embedded wallet
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const chain_type = getChainType(allocator, args) orelse {
        return client.errorResult(allocator, "Missing required parameter: chain_type");
    };

    // Validate chain type
    const valid_chains = [_][]const u8{
        "ethereum", "solana",   "cosmos", "stellar",        "sui",
        "aptos",    "movement", "tron",   "bitcoin-segwit", "near",
        "ton",      "starknet", "spark",
    };
    var is_valid = false;
    for (valid_chains) |valid| {
        if (std.mem.eql(u8, chain_type, valid)) {
            is_valid = true;
            break;
        }
    }
    if (!is_valid) {
        return client.errorResult(allocator, "Invalid chain_type. Valid options: ethereum, solana, cosmos, stellar, sui, aptos, movement, tron, bitcoin-segwit, near, ton, starknet, spark");
    }

    const user_id = mcp.tools.getString(args, "user_id");

    // Build request body
    const body = if (user_id) |uid|
        std.fmt.allocPrint(allocator, "{{\"chain_type\":\"{s}\",\"owner\":{{\"user_id\":\"{s}\"}}}}", .{ chain_type, uid })
    else
        std.fmt.allocPrint(allocator, "{{\"chain_type\":\"{s}\"}}", .{chain_type});

    const request_body = body catch return mcp.tools.ToolError.OutOfMemory;
    defer allocator.free(request_body);

    // Make API request
    const response = client.privyPost(allocator, "/wallets", request_body) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Privy API error: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return client.errorResult(allocator, msg);
    };
    defer allocator.free(response);

    return client.jsonResult(allocator, response);
}

fn getChainType(allocator: std.mem.Allocator, args: ?std.json.Value) ?[]const u8 {
    if (mcp.tools.getString(args, "chain_type")) |val| return val;
    if (mcp.tools.getString(args, "chainType")) |val| return val;

    if (args) |a| {
        if (a == .string) {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, a.string, .{}) catch return null;
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("chain_type")) |v| if (v == .string) return v.string;
                if (parsed.value.object.get("chainType")) |v| if (v == .string) return v.string;
            }
        }
    }

    return null;
}
