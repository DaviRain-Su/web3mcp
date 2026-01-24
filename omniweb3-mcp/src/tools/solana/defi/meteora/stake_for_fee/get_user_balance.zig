//! Meteora M3M3 Get User Balance Tool

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

    const Response = struct {
        pool: []const u8,
        user: []const u8,
        staked_amount: []const u8,
        claimable_fees: []const u8,
        pending_unstake: []const u8,
        note: []const u8,
    };

    const response = Response{
        .pool = pool_address_str,
        .user = user_str,
        .staked_amount = "0",
        .claimable_fees = "0",
        .pending_unstake = "0",
        .note = "Fetch user's stake account for actual balance. Claimable fees update after each trade.",
    };

    return helpers.jsonResult(allocator, response);
}
