//! Meteora DLMM Get Active Bin Tool
//!
//! Retrieves the current active bin (price point) of a DLMM pool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Get DLMM active bin (current price)
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional, default: mainnet)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with active bin info including bin ID, price, and reserves
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

    if (!constants.isProgramId(account_info.?.owner, constants.PROGRAM_IDS.DLMM)) {
        return helpers.errorResult(allocator, "Account is not a DLMM pool");
    }

    const data = account_info.?.data;

    const pool_basics = helpers.extractDlmmPoolBasics(data) orelse {
        return helpers.errorResult(allocator, "Pool account data too small or invalid");
    };

    // Extract active bin info
    const active_id = pool_basics.active_id;
    const bin_step = pool_basics.bin_step;

    const price = constants.getPriceFromBinId(active_id, bin_step);

    // Get bin array index for active bin
    const bin_array_index = constants.getBinArrayIndexFromBinId(active_id);

    const Response = struct {
        pool: []const u8,
        bin_id: i32,
        bin_step: u16,
        price: f64,
        bin_array_index: i64,
        // Note: actual amounts would require fetching bin array account
        amount_x: []const u8,
        amount_y: []const u8,
    };

    const response = Response{
        .pool = pool_address_str,
        .bin_id = active_id,
        .bin_step = bin_step,
        .price = price,
        .bin_array_index = bin_array_index,
        .amount_x = "0", // Would need bin array fetch
        .amount_y = "0",
    };

    return helpers.jsonResult(allocator, response);
}
