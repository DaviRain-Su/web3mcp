//! Meteora DAMM v1 Swap Tool

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

    const input_mint_str = mcp.tools.getString(args, "input_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: input_mint");
    };

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    _ = helpers.parsePublicKey(input_mint_str) orelse {
        return helpers.errorResult(allocator, "Invalid input_mint");
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

    const min_out_amount: u64 = blk: {
        if (mcp.tools.getString(args, "min_out_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid min_out_amount");
            };
        } else if (mcp.tools.getInteger(args, "min_out_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "min_out_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: min_out_amount");
        }
    };

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        input_mint: []const u8,
        amount_in: u64,
        min_amount_out: u64,
        instruction: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .input_mint = input_mint_str,
        .amount_in = amount,
        .min_amount_out = min_out_amount,
        .instruction = "swap",
    };

    return helpers.jsonResult(allocator, response);
}
