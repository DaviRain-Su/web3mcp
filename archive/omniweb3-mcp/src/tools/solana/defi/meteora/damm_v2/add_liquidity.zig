//! Meteora DAMM v2 Add Liquidity Tool
//!
//! Creates a transaction to add liquidity to a DAMM v2 pool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

/// Add liquidity to DAMM v2
///
/// Parameters:
/// - pool_address: Base58 pool address (required)
/// - user: Base58 user public key (required)
/// - amount_a: Amount of token A (required)
/// - amount_b: Amount of token B (required)
/// - min_lp_amount: Minimum LP tokens to receive (optional, default: 0)
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

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    const amount_a: u64 = blk: {
        if (mcp.tools.getString(args, "amount_a")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount_a");
            };
        } else if (mcp.tools.getInteger(args, "amount_a")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount_a must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount_a");
        }
    };

    const amount_b: u64 = blk: {
        if (mcp.tools.getString(args, "amount_b")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount_b");
            };
        } else if (mcp.tools.getInteger(args, "amount_b")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount_b must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount_b");
        }
    };

    const min_lp_amount: u64 = blk: {
        if (mcp.tools.getString(args, "min_lp_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch 0;
        } else if (mcp.tools.getInteger(args, "min_lp_amount")) |i| {
            if (i < 0) break :blk 0;
            break :blk @intCast(i);
        } else {
            break :blk 0;
        }
    };

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        amount_a: u64,
        amount_b: u64,
        min_lp_amount: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .amount_a = amount_a,
        .amount_b = amount_b,
        .min_lp_amount = min_lp_amount,
        .instruction = "add_liquidity",
        .note = "DAMM v2 creates a position NFT for the LP. Include token accounts for A and B.",
    };

    return helpers.jsonResult(allocator, response);
}
