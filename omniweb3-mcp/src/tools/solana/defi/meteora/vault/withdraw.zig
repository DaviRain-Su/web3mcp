//! Meteora Vault Withdraw Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const token_mint_str = mcp.tools.getString(args, "token_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: token_mint");
    };

    const user_str = mcp.tools.getString(args, "user") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: user");
    };

    _ = helpers.parsePublicKey(token_mint_str) orelse {
        return helpers.errorResult(allocator, "Invalid token_mint");
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

    const Response = struct {
        status: []const u8,
        token_mint: []const u8,
        user: []const u8,
        lp_amount: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .token_mint = token_mint_str,
        .user = user_str,
        .lp_amount = lp_amount,
        .instruction = "withdraw",
        .note = "Withdraw tokens from vault by burning LP tokens. Amount received = LP * unlocked_balance / total_supply.",
    };

    return helpers.jsonResult(allocator, response);
}
