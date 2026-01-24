//! Meteora DAMM v1 Withdraw Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const user_str = mcp.tools.getString(args, "user") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: user");
    };

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    const lp_amount: u64 = blk: {
        if (mcp.tools.getString(args, "lp_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid lp_amount");
            };
        } else if (mcp.tools.getInteger(args, "lp_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "lp_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: lp_amount");
        }
    };

    const min_a: u64 = if (mcp.tools.getInteger(args, "min_a")) |i|
        if (i >= 0) @intCast(i) else 0
    else
        0;

    const min_b: u64 = if (mcp.tools.getInteger(args, "min_b")) |i|
        if (i >= 0) @intCast(i) else 0
    else
        0;

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        lp_amount: u64,
        min_a: u64,
        min_b: u64,
        instruction: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .lp_amount = lp_amount,
        .min_a = min_a,
        .min_b = min_b,
        .instruction = "withdraw",
    };

    return helpers.jsonResult(allocator, response);
}
