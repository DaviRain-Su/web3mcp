//! Meteora Alpha Vault Deposit Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const vault_address_str = mcp.tools.getString(args, "vault_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: vault_address");
    };

    const user_str = mcp.tools.getString(args, "user") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: user");
    };

    _ = helpers.parsePublicKey(vault_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid vault_address");
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
        vault_address: []const u8,
        user: []const u8,
        amount: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .vault_address = vault_address_str,
        .user = user_str,
        .amount = amount,
        .instruction = "deposit",
        .note = "Deposit to Alpha Vault during deposit window. Pro-rata allocation based on total deposits.",
    };

    return helpers.jsonResult(allocator, response);
}
