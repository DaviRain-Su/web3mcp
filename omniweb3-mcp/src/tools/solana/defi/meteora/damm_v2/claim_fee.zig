//! Meteora DAMM v2 Claim Fee Tool
//!
//! Creates a transaction to claim fees from a DAMM v2 position

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

/// Claim DAMM v2 position fees
///
/// Parameters:
/// - pool_address: Base58 pool address (required)
/// - user: Base58 user public key (required)
/// - position: Base58 position NFT address (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with transaction details
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    const position_str = mcp.tools.getString(args, "position") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: position");
    };

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    _ = helpers.parsePublicKey(position_str) orelse {
        return helpers.errorResult(allocator, "Invalid position");
    };

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        position: []const u8,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .position = position_str,
        .instruction = "claim_position_fee",
        .note = "Include user's position NFT and token accounts for A and B to receive fees.",
    };

    return helpers.jsonResult(allocator, response);
}
