//! Meteora Vault Get User Balance Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const token_mint_str = mcp.tools.getString(args, "token_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: token_mint");
    };

    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    _ = helpers.parsePublicKey(token_mint_str) orelse {
        return helpers.errorResult(allocator, "Invalid token_mint");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    const Response = struct {
        token_mint: []const u8,
        user: []const u8,
        lp_balance: []const u8,
        underlying_value: []const u8,
        note: []const u8,
    };

    const response = Response{
        .token_mint = token_mint_str,
        .user = user_str,
        .lp_balance = "0",
        .underlying_value = "0",
        .note = "Fetch user's LP token account to get actual balance. Underlying value = LP * unlocked / total_supply.",
    };

    return helpers.jsonResult(allocator, response);
}
