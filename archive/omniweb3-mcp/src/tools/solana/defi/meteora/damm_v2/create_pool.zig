//! Meteora DAMM v2 Create Pool Tool
//!
//! Creates a new DAMM v2 pool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

/// Create DAMM v2 pool
///
/// Parameters:
/// - user: Base58 creator public key (required)
/// - token_a_mint: Base58 token A mint (required)
/// - token_b_mint: Base58 token B mint (required)
/// - token_a_amount: Initial amount of token A (required)
/// - token_b_amount: Initial amount of token B (required)
/// - config: Base58 config address (optional, uses default)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with transaction details
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    const token_a_mint_str = mcp.tools.getString(args, "token_a_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: token_a_mint");
    };

    const token_b_mint_str = mcp.tools.getString(args, "token_b_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: token_b_mint");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    _ = helpers.parsePublicKey(token_a_mint_str) orelse {
        return helpers.errorResult(allocator, "Invalid token_a_mint");
    };

    _ = helpers.parsePublicKey(token_b_mint_str) orelse {
        return helpers.errorResult(allocator, "Invalid token_b_mint");
    };

    const token_a_amount: u64 = blk: {
        if (mcp.tools.getString(args, "token_a_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid token_a_amount");
            };
        } else if (mcp.tools.getInteger(args, "token_a_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "token_a_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: token_a_amount");
        }
    };

    const token_b_amount: u64 = blk: {
        if (mcp.tools.getString(args, "token_b_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid token_b_amount");
            };
        } else if (mcp.tools.getInteger(args, "token_b_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "token_b_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: token_b_amount");
        }
    };

    const config_str = mcp.tools.getString(args, "config") orelse "default";

    const Response = struct {
        status: []const u8,
        creator: []const u8,
        token_a_mint: []const u8,
        token_b_mint: []const u8,
        token_a_amount: u64,
        token_b_amount: u64,
        config: []const u8,
        instruction: []const u8,
        pool_creation_cost: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .creator = user_str,
        .token_a_mint = token_a_mint_str,
        .token_b_mint = token_b_mint_str,
        .token_a_amount = token_a_amount,
        .token_b_amount = token_b_amount,
        .config = config_str,
        .instruction = "create_pool",
        .pool_creation_cost = "0.022 SOL",
        .note = "DAMM v2 pool creation costs ~0.022 SOL. Tokens must be ordered (A < B by mint address).",
    };

    return helpers.jsonResult(allocator, response);
}
