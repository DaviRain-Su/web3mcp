//! Meteora DAMM v2 Remove Liquidity Tool
//!
//! Creates a transaction to remove liquidity from a DAMM v2 position

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

/// Remove liquidity from DAMM v2
///
/// Parameters:
/// - pool_address: Base58 pool address (required)
/// - user: Base58 user public key (required)
/// - position: Base58 position NFT address (required)
/// - lp_amount: Amount of LP to remove (required)
/// - min_a: Minimum token A to receive (optional, default: 0)
/// - min_b: Minimum token B to receive (optional, default: 0)
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

    const min_a: u64 = if (mcp.tools.getInteger(args, "min_a")) |i|
        if (i >= 0) @intCast(i) else 0
    else
        0;

    const min_b: u64 = if (mcp.tools.getInteger(args, "min_b")) |i|
        if (i >= 0) @intCast(i) else 0
    else
        0;

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        position: []const u8,
        lp_amount: u64,
        min_a: u64,
        min_b: u64,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .position = position_str,
        .lp_amount = lp_amount,
        .min_a = min_a,
        .min_b = min_b,
        .instruction = "remove_liquidity",
        .note = "Include user's position NFT and token accounts for A and B.",
    };

    return helpers.jsonResult(allocator, response);
}
