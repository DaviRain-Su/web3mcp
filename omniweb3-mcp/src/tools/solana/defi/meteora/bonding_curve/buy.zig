//! Meteora Dynamic Bonding Curve Buy Tool

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

    const quote_amount: u64 = blk: {
        if (mcp.tools.getString(args, "quote_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid quote_amount");
            };
        } else if (mcp.tools.getInteger(args, "quote_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "quote_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: quote_amount");
        }
    };

    const min_base_amount: u64 = blk: {
        if (mcp.tools.getString(args, "min_base_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid min_base_amount");
            };
        } else if (mcp.tools.getInteger(args, "min_base_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "min_base_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: min_base_amount");
        }
    };

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        quote_amount: u64,
        min_base_amount: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .quote_amount = quote_amount,
        .min_base_amount = min_base_amount,
        .instruction = "buy",
        .note = "Buy tokens on bonding curve. Quote token is usually SOL or USDC.",
    };

    return helpers.jsonResult(allocator, response);
}
