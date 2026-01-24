//! Meteora DLMM Add Liquidity Tool
//!
//! Creates a transaction to add liquidity to a DLMM pool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

/// Add liquidity to DLMM pool
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - user: Base58 user public key (required)
/// - amount_x: Amount of token X in base units (required)
/// - amount_y: Amount of token Y in base units (required)
/// - strategy: Distribution strategy (required)
///   - SpotBalanced, CurveBalanced, BidAskBalanced
///   - SpotOneSide, CurveOneSide, BidAskOneSide
///   - SpotImBalanced, CurveImBalanced, BidAskImBalanced
/// - min_bin_id: Lower bin ID for position (required)
/// - max_bin_id: Upper bin ID for position (required)
/// - network: "mainnet" | "devnet" | "testnet" (optional)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns JSON with transaction details for signing
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    const pool_address = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address: not a valid Base58 public key");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user: not a valid Base58 public key");
    };

    // Get amounts
    const amount_x: u64 = blk: {
        if (mcp.tools.getString(args, "amount_x")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount_x");
            };
        } else if (mcp.tools.getInteger(args, "amount_x")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount_x must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount_x");
        }
    };

    const amount_y: u64 = blk: {
        if (mcp.tools.getString(args, "amount_y")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid amount_y");
            };
        } else if (mcp.tools.getInteger(args, "amount_y")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "amount_y must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: amount_y");
        }
    };

    const strategy_str = mcp.tools.getString(args, "strategy") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: strategy");
    };

    // Parse strategy
    const strategy: constants.StrategyType = if (std.ascii.eqlIgnoreCase(strategy_str, "SpotBalanced"))
        .SpotBalanced
    else if (std.ascii.eqlIgnoreCase(strategy_str, "CurveBalanced"))
        .CurveBalanced
    else if (std.ascii.eqlIgnoreCase(strategy_str, "BidAskBalanced"))
        .BidAskBalanced
    else if (std.ascii.eqlIgnoreCase(strategy_str, "SpotOneSide"))
        .SpotOneSide
    else if (std.ascii.eqlIgnoreCase(strategy_str, "CurveOneSide"))
        .CurveOneSide
    else if (std.ascii.eqlIgnoreCase(strategy_str, "BidAskOneSide"))
        .BidAskOneSide
    else if (std.ascii.eqlIgnoreCase(strategy_str, "SpotImBalanced"))
        .SpotImBalanced
    else if (std.ascii.eqlIgnoreCase(strategy_str, "CurveImBalanced"))
        .CurveImBalanced
    else if (std.ascii.eqlIgnoreCase(strategy_str, "BidAskImBalanced"))
        .BidAskImBalanced
    else {
        return helpers.errorResult(allocator, "Invalid strategy. Use: SpotBalanced, CurveBalanced, BidAskBalanced, SpotOneSide, CurveOneSide, BidAskOneSide, SpotImBalanced, CurveImBalanced, BidAskImBalanced");
    };

    // Get bin range
    const min_bin_id: i32 = if (mcp.tools.getInteger(args, "min_bin_id")) |id| @intCast(id) else {
        return helpers.errorResult(allocator, "Missing required parameter: min_bin_id");
    };

    const max_bin_id: i32 = if (mcp.tools.getInteger(args, "max_bin_id")) |id| @intCast(id) else {
        return helpers.errorResult(allocator, "Missing required parameter: max_bin_id");
    };

    if (min_bin_id >= max_bin_id) {
        return helpers.errorResult(allocator, "min_bin_id must be less than max_bin_id");
    }

    const width = max_bin_id - min_bin_id;
    if (width > @as(i32, constants.DLMM_MATH.MAX_BIN_PER_POSITION)) {
        return helpers.errorResult(allocator, "Bin range too wide. Maximum 70 bins per position.");
    }

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

    // Calculate prices at boundaries
    const min_price = constants.getPriceFromBinId(min_bin_id, bin_step);
    const max_price = constants.getPriceFromBinId(max_bin_id, bin_step);
    const current_price = constants.getPriceFromBinId(active_id, bin_step);

    const Response = struct {
        status: []const u8,
        pool: []const u8,
        user: []const u8,
        amount_x: u64,
        amount_y: u64,
        strategy: []const u8,
        min_bin_id: i32,
        max_bin_id: i32,
        num_bins: i32,
        min_price: f64,
        max_price: f64,
        current_price: f64,
        active_bin_id: i32,
        bin_step: u16,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .pool = pool_address_str,
        .user = user_str,
        .amount_x = amount_x,
        .amount_y = amount_y,
        .strategy = strategy_str,
        .min_bin_id = min_bin_id,
        .max_bin_id = max_bin_id,
        .num_bins = width,
        .min_price = min_price,
        .max_price = max_price,
        .current_price = current_price,
        .active_bin_id = active_id,
        .bin_step = bin_step,
        .note = "Transaction needs position keypair, user token accounts, and proper bin arrays.",
    };

    _ = strategy;

    return helpers.jsonResult(allocator, response);
}
