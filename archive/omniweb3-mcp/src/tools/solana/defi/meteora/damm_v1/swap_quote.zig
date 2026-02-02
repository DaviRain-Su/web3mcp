//! Meteora DAMM v1 Swap Quote Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const input_mint_str = mcp.tools.getString(args, "input_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: input_mint");
    };

    _ = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
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

    const slippage_bps: u16 = if (mcp.tools.getInteger(args, "slippage_bps")) |s|
        @intCast(s)
    else
        100;

    const fee_bps: u16 = 25;
    const fee = (amount * fee_bps) / 10000;
    const estimated_output = amount - fee;
    const min_output = helpers.applySlippage(estimated_output, slippage_bps, true);

    const Response = struct {
        pool: []const u8,
        input_mint: []const u8,
        amount_in: u64,
        estimated_amount_out: u64,
        min_amount_out: u64,
        fee: u64,
        fee_bps: u16,
        slippage_bps: u16,
    };

    const response = Response{
        .pool = pool_address_str,
        .input_mint = input_mint_str,
        .amount_in = amount,
        .estimated_amount_out = estimated_output,
        .min_amount_out = min_output,
        .fee = fee,
        .fee_bps = fee_bps,
        .slippage_bps = slippage_bps,
    };

    return helpers.jsonResult(allocator, response);
}
