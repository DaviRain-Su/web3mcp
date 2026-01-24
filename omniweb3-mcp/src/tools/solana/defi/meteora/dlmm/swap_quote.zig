//! Meteora DLMM Swap Quote Tool
//!
//! Gets a swap quote for a DLMM pool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Get DLMM swap quote
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - amount: Amount to swap in base units (required)
/// - swap_for_y: true=swap X for Y, false=swap Y for X (required)
/// - slippage_bps: Slippage tolerance in basis points (optional, default: 100 = 1%)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with quote details including expected output and price impact
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const pool_address = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address: not a valid Base58 public key");
    };

    // Get amount - support both string and integer
    const amount_str = mcp.tools.getString(args, "amount");
    const amount_int = mcp.tools.getInteger(args, "amount");

    const amount: u64 = if (amount_str) |s| blk: {
        break :blk std.fmt.parseInt(u64, s, 10) catch {
            return helpers.errorResult(allocator, "Invalid amount: must be a valid integer");
        };
    } else if (amount_int) |i| blk: {
        if (i < 0) {
            return helpers.errorResult(allocator, "Invalid amount: must be non-negative");
        }
        break :blk @intCast(i);
    } else {
        return helpers.errorResult(allocator, "Missing required parameter: amount");
    };

    const swap_for_y = mcp.tools.getBoolean(args, "swap_for_y") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: swap_for_y");
    };

    const slippage_bps: u16 = if (mcp.tools.getInteger(args, "slippage_bps")) |s|
        @intCast(s)
    else
        100; // 1% default

    const endpoint = helpers.getEndpoint(args);

    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    // Fetch pool info
    const account_info = client.getAccountInfo(pool_address) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch pool account: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return helpers.errorResult(allocator, msg);
    };

    if (account_info == null) {
        return helpers.errorResult(allocator, "Pool account not found");
    }

    const data = account_info.?.data;
    if (data.len == 0) {
        return helpers.errorResult(allocator, "Pool account has no data");
    }

    if (data.len < 200) {
        return helpers.errorResult(allocator, "Pool account data too small");
    }

    const active_id = std.mem.readInt(i32, data[8..12], .little);
    const bin_step = std.mem.readInt(u16, data[12..14], .little);

    // Calculate swap quote (simplified)
    // In production, this would iterate through bins and calculate exact output
    const base_fee_bps: u16 = 25; // 0.25% base fee
    const fee = (amount * base_fee_bps) / 10000;
    const amount_after_fee = amount - fee;

    // Estimate output (simplified - real calculation needs bin data)
    const price = constants.getPriceFromBinId(active_id, bin_step);
    const estimated_output: u64 = if (swap_for_y)
        @intFromFloat(@as(f64, @floatFromInt(amount_after_fee)) * price)
    else
        @intFromFloat(@as(f64, @floatFromInt(amount_after_fee)) / price);

    // Apply slippage for minimum output
    const min_output = helpers.applySlippage(estimated_output, slippage_bps, true);

    // Estimate price impact (simplified)
    const price_impact: f64 = 0.001; // 0.1% placeholder

    const Response = struct {
        pool: []const u8,
        amount_in: u64,
        swap_for_y: bool,
        estimated_amount_out: u64,
        min_amount_out: u64,
        fee: u64,
        fee_bps: u16,
        price: f64,
        price_impact: f64,
        slippage_bps: u16,
        active_bin_id: i32,
        bin_step: u16,
    };

    const response = Response{
        .pool = pool_address_str,
        .amount_in = amount,
        .swap_for_y = swap_for_y,
        .estimated_amount_out = estimated_output,
        .min_amount_out = min_output,
        .fee = fee,
        .fee_bps = base_fee_bps,
        .price = price,
        .price_impact = price_impact,
        .slippage_bps = slippage_bps,
        .active_bin_id = active_id,
        .bin_step = bin_step,
    };

    return helpers.jsonResult(allocator, response);
}
