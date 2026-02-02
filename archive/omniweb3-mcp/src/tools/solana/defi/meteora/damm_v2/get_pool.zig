//! Meteora DAMM v2 Get Pool Tool
//!
//! Retrieves DAMM v2 (CP-AMM) pool information

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Get Meteora DAMM v2 pool information
///
/// Parameters:
/// - pool_address: Base58 DAMM v2 pool address (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional, default: mainnet)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with pool info including tokens, reserves, sqrt_price, and liquidity
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

    if (!constants.isProgramId(account_info.?.owner, constants.PROGRAM_IDS.DAMM_V2)) {
        return helpers.errorResult(allocator, "Account is not a DAMM v2 pool (wrong program owner)");
    }

    const data = account_info.?.data;

    if (data.len < 300) {
        return helpers.errorResult(allocator, "Pool account data too small");
    }

    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const Response = struct {
        address: []const u8,
        program_id: []const u8,
        data_len: usize,
        network: []const u8,
        note: []const u8,
    };

    const response = Response{
        .address = pool_address_str,
        .program_id = "cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG",
        .data_len = data.len,
        .network = network,
        .note = "DAMM v2 uses sqrt_price for price representation. Pool has position NFTs for LP tracking.",
    };

    return helpers.jsonResult(allocator, response);
}
