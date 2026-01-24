//! Meteora Alpha Vault Claim Tool

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

    const Response = struct {
        status: []const u8,
        vault_address: []const u8,
        user: []const u8,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .vault_address = vault_address_str,
        .user = user_str,
        .instruction = "claim_tokens",
        .note = "Claim allocated tokens after vault settlement. Must have participated in deposit phase.",
    };

    return helpers.jsonResult(allocator, response);
}
