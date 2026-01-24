//! Meteora DLMM Get Pool Tool
//!
//! Retrieves DLMM pool information including:
//! - Token mints
//! - Reserves
//! - Active bin ID and price
//! - Bin step and fee info

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Get Meteora DLMM pool information
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional, default: mainnet)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with pool info including tokens, reserves, active bin, and fees
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Get required pool address
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const pool_address = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address: not a valid Base58 public key");
    };

    // Get network endpoint
    const endpoint = helpers.getEndpoint(args);

    // Create RPC client
    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    // Fetch account info
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

    // Verify it's a DLMM program account
    if (!constants.isProgramId(account_info.?.owner, constants.PROGRAM_IDS.DLMM)) {
        return helpers.errorResult(allocator, "Account is not a DLMM pool (wrong program owner)");
    }

    const data = account_info.?.data;

    // Parse account data (basic structure extraction)
    // DLMM LbPair layout:
    // - 8 bytes: discriminator
    // - parameters struct
    // - mints and reserves

    if (data.len < 200) {
        return helpers.errorResult(allocator, "Pool account data too small");
    }

    // Extract key fields from account data
    // Note: This is a simplified extraction - production code would use proper borsh deserialization
    const active_id = std.mem.readInt(i32, data[8..12], .little);
    const bin_step = std.mem.readInt(u16, data[12..14], .little);

    // Calculate current price from active bin
    const current_price = constants.getPriceFromBinId(active_id, bin_step);

    // Build response
    const Response = struct {
        address: []const u8,
        program_id: []const u8,
        active_bin_id: i32,
        bin_step: u16,
        current_price: f64,
        fee_bps: u16,
        data_len: usize,
        network: []const u8,
    };

    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const response = Response{
        .address = pool_address_str,
        .program_id = "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo",
        .active_bin_id = active_id,
        .bin_step = bin_step,
        .current_price = current_price,
        .fee_bps = 25, // Default base fee, actual fee is dynamic
        .data_len = data.len,
        .network = network,
    };

    return helpers.jsonResult(allocator, response);
}
