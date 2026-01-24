//! Meteora Dynamic Bonding Curve Migrate Tool

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

    const target = mcp.tools.getString(args, "target") orelse "damm_v2";

    // Validate target
    if (!std.mem.eql(u8, target, "damm_v1") and !std.mem.eql(u8, target, "damm_v2")) {
        return helpers.errorResult(allocator, "Invalid target: must be 'damm_v1' or 'damm_v2'");
    }

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        target: []const u8,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .target = target,
        .instruction = if (std.mem.eql(u8, target, "damm_v2")) "migrate_to_damm_v2" else "migrate_to_damm_v1",
        .note = "Pool must have graduated (met threshold) before migration. Migration moves liquidity to DAMM pool.",
    };

    return helpers.jsonResult(allocator, response);
}
