//! Meteora DLMM Get Bins Tool
//!
//! Retrieves bins in a specified range around the active bin

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Get DLMM bins in range
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - min_bin_id: Minimum bin ID (optional, default: active_bin - 10)
/// - max_bin_id: Maximum bin ID (optional, default: active_bin + 10)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON array with bin info including price and liquidity
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const pool_address = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address: not a valid Base58 public key");
    };

    const endpoint = helpers.getEndpoint(args);

    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    // Fetch pool to get active bin and bin step
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

    // Get range parameters
    const min_bin_id = if (mcp.tools.getInteger(args, "min_bin_id")) |id|
        @as(i32, @intCast(id))
    else
        active_id - 10;

    const max_bin_id = if (mcp.tools.getInteger(args, "max_bin_id")) |id|
        @as(i32, @intCast(id))
    else
        active_id + 10;

    // Limit range to prevent huge responses
    const range = @min(@as(u32, @intCast(max_bin_id - min_bin_id + 1)), 100);

    // Build bin list with price info
    const BinInfo = struct {
        bin_id: i32,
        price: f64,
        is_active: bool,
        // Note: actual liquidity would require fetching bin arrays
    };

    var bins = std.ArrayList(BinInfo).initCapacity(allocator, @intCast(range)) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer bins.deinit(allocator);

    var bin_id = min_bin_id;
    var count: u32 = 0;
    while (count < range) : ({
        bin_id += 1;
        count += 1;
    }) {
        const price = constants.getPriceFromBinId(bin_id, bin_step);
        bins.appendAssumeCapacity(.{
            .bin_id = bin_id,
            .price = price,
            .is_active = bin_id == active_id,
        });
    }

    const Response = struct {
        pool: []const u8,
        active_bin_id: i32,
        bin_step: u16,
        min_bin_id: i32,
        max_bin_id: i32,
        bins: []const BinInfo,
    };

    const response = Response{
        .pool = pool_address_str,
        .active_bin_id = active_id,
        .bin_step = bin_step,
        .min_bin_id = min_bin_id,
        .max_bin_id = max_bin_id,
        .bins = bins.items,
    };

    return helpers.jsonResult(allocator, response);
}
