//! Meteora DAMM v1 Deposit Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    const amount_a: u64 = blk: {
        if (mcp.tools.getString(args, "amount_a")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount_a");
            };
        } else if (mcp.tools.getInteger(args, "amount_a")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount_a must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount_a");
        }
    };

    const amount_b: u64 = blk: {
        if (mcp.tools.getString(args, "amount_b")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount_b");
            };
        } else if (mcp.tools.getInteger(args, "amount_b")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount_b must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount_b");
        }
    };

    const min_lp_amount: u64 = if (mcp.tools.getInteger(args, "min_lp_amount")) |i|
        if (i >= 0) @intCast(i) else 0
    else
        0;

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        amount_a: u64,
        amount_b: u64,
        min_lp_amount: u64,
        instruction: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .amount_a = amount_a,
        .amount_b = amount_b,
        .min_lp_amount = min_lp_amount,
        .instruction = "deposit",
    };

    return helpers.jsonResult(allocator, response);
}
