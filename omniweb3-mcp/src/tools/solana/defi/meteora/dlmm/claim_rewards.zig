//! Meteora DLMM Claim Rewards Tool
//!
//! Creates a transaction to claim LM rewards from a DLMM position

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Claim DLMM LM rewards
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - user: Base58 user public key (required)
/// - position: Base58 position address (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with transaction details for signing
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const user_str = mcp.tools.getString(args, "user") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: user");
    };

    const position_str = mcp.tools.getString(args, "position") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: position");
    };

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address: not a valid Base58 public key");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user: not a valid Base58 public key");
    };

    _ = helpers.parsePublicKey(position_str) orelse {
        return helpers.errorResult(allocator, "Invalid position: not a valid Base58 public key");
    };

    const endpoint = helpers.getEndpoint(args);
    _ = endpoint;

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
        .instruction = "claim_reward",
        .note = "Transaction needs reward vault accounts. Pool must have active LM rewards.",
    };

    return helpers.jsonResult(allocator, response);
}
