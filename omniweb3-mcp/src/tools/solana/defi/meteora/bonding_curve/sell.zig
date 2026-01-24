//! Meteora Dynamic Bonding Curve Sell Tool

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

    const base_amount: u64 = blk: {
        if (mcp.tools.getString(args, "base_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid base_amount");
            };
        } else if (mcp.tools.getInteger(args, "base_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "base_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: base_amount");
        }
    };

    const min_quote_amount: u64 = blk: {
        if (mcp.tools.getString(args, "min_quote_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid min_quote_amount");
            };
        } else if (mcp.tools.getInteger(args, "min_quote_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "min_quote_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: min_quote_amount");
        }
    };

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        base_amount: u64,
        min_quote_amount: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .base_amount = base_amount,
        .min_quote_amount = min_quote_amount,
        .instruction = "sell",
        .note = "Sell base tokens back to bonding curve for quote tokens.",
    };

    return helpers.jsonResult(allocator, response);
}
