//! Meteora Vault Deposit Tool

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

    const amount: u64 = blk: {
        if (mcp.tools.getString(args, "amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount");
            };
        } else if (mcp.tools.getInteger(args, "amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount");
        }
    };

    const Response = struct {
        status: []const u8,
        token_mint: []const u8,
        user: []const u8,
        amount: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .token_mint = token_mint_str,
        .user = user_str,
        .amount = amount,
        .instruction = "deposit",
        .note = "Deposit tokens to vault. Receive LP tokens representing your share of the vault.",
    };

    return helpers.jsonResult(allocator, response);
}
