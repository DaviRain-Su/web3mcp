//! Meteora Protocol Helper Functions
//!
//! Common utilities for Meteora tools including:
//! - Account data parsing
//! - On-chain data fetching
//! - Transaction building helpers

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const wallet_provider = @import("../../../../core/wallet_provider.zig");
const constants = @import("constants.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

// =============================================================================
// Account Data Structures (matching on-chain layouts)
// =============================================================================

/// DLMM LbPair Account Layout (simplified)
pub const LbPairAccount = struct {
    /// Parameters: bin_step, base_factor, etc
    parameters: LbPairParameters,
    /// Token X mint
    token_x_mint: PublicKey,
    /// Token Y mint
    token_y_mint: PublicKey,
    /// Reserve X
    reserve_x: PublicKey,
    /// Reserve Y
    reserve_y: PublicKey,
    /// Oracle pubkey
    oracle: PublicKey,
    /// Active bin ID
    active_id: i32,
    /// Bin step (basis points)
    bin_step: u16,
    /// Protocol fee in basis points
    protocol_fee_bps: u16,
    /// Fee owner
    fee_owner: PublicKey,
    /// Reward infos
    reward_infos: [2]RewardInfo,
};

pub const LbPairParameters = struct {
    base_factor: u16,
    filter_period: u16,
    decay_period: u16,
    reduction_factor: u16,
    variable_fee_control: u32,
    max_volatility_accumulator: u32,
    min_bin_id: i32,
    max_bin_id: i32,
    protocol_share: u16,
};

pub const RewardInfo = struct {
    mint: PublicKey,
    vault: PublicKey,
    funder: PublicKey,
    reward_duration: u64,
    reward_duration_end: u64,
    reward_rate: u128,
    last_update_time: u64,
    cumulative_seconds_with_empty_liquidity_reward: u64,
};

/// DLMM Bin data
pub const Bin = struct {
    amount_x: u128,
    amount_y: u128,
    price: u128,
    liquidity_supply: u128,
    reward_per_token_stored: [2]u128,
    fee_amount_x_per_token_stored: u128,
    fee_amount_y_per_token_stored: u128,
    amount_x_in: u128,
    amount_y_in: u128,
};

/// DLMM Position Account Layout
pub const PositionAccount = struct {
    /// LB pair this position belongs to
    lb_pair: PublicKey,
    /// Owner of the position
    owner: PublicKey,
    /// Lower bin ID
    lower_bin_id: i32,
    /// Upper bin ID
    upper_bin_id: i32,
    /// Total liquidity shares
    liquidity_shares: [70]u128,
    /// Reward debts
    reward_infos: [2]UserRewardInfo,
    /// Fee infos
    fee_infos: [70]FeeInfo,
    /// Last updated slot
    last_updated_at: u64,
    /// Total claimed fee X
    total_claimed_fee_x_amount: u64,
    /// Total claimed fee Y
    total_claimed_fee_y_amount: u64,
};

pub const UserRewardInfo = struct {
    reward_per_token_completes: [70]u128,
    reward_pendings: u64,
};

pub const FeeInfo = struct {
    fee_x_per_token_complete: u128,
    fee_y_per_token_complete: u128,
    fee_x_pending: u64,
    fee_y_pending: u64,
};

/// DAMM v2 Pool Account Layout
pub const DammV2PoolAccount = struct {
    /// Config account
    config: PublicKey,
    /// Token A mint
    token_a_mint: PublicKey,
    /// Token B mint
    token_b_mint: PublicKey,
    /// Token A vault
    token_a_vault: PublicKey,
    /// Token B vault
    token_b_vault: PublicKey,
    /// LP mint
    lp_mint: PublicKey,
    /// Protocol fee owner
    protocol_fee_owner: PublicKey,
    /// Sqrt price Q64.64
    sqrt_price: u128,
    /// Total liquidity
    liquidity: u128,
    /// Protocol fee A
    protocol_fee_a: u64,
    /// Protocol fee B
    protocol_fee_b: u64,
    /// Cumulative trade fee A
    cumulative_trade_fee_a: u128,
    /// Cumulative trade fee B
    cumulative_trade_fee_b: u128,
    /// Activation point (slot or timestamp)
    activation_point: u64,
    /// Activation type (0=slot, 1=timestamp)
    activation_type: u8,
    /// Collect fee mode
    collect_fee_mode: u8,
    /// Pool status
    status: u8,
};

/// DAMM v2 Position Account Layout
pub const DammV2PositionAccount = struct {
    /// Pool this position belongs to
    pool: PublicKey,
    /// Owner
    owner: PublicKey,
    /// Position NFT mint
    nft_mint: PublicKey,
    /// Liquidity shares
    liquidity: u128,
    /// Fee A owed
    fee_a_owed: u64,
    /// Fee B owed
    fee_b_owed: u64,
    /// Fee A per liquidity checkpoint
    fee_a_per_liquidity_checkpoint: u128,
    /// Fee B per liquidity checkpoint
    fee_b_per_liquidity_checkpoint: u128,
    /// Reward infos
    reward_infos: [2]PositionRewardInfo,
    /// Locked (vesting)
    is_locked: bool,
    /// Vesting end timestamp
    vesting_end_timestamp: i64,
    /// Cliff end timestamp
    cliff_end_timestamp: i64,
};

pub const PositionRewardInfo = struct {
    reward_per_liquidity_checkpoint: u128,
    reward_owed: u64,
};

/// Dynamic Bonding Curve Pool Account Layout
pub const DbcPoolAccount = struct {
    /// Config account
    config: PublicKey,
    /// Creator
    creator: PublicKey,
    /// Base token mint (the launched token)
    base_mint: PublicKey,
    /// Quote token mint (usually SOL/USDC)
    quote_mint: PublicKey,
    /// Base vault
    base_vault: PublicKey,
    /// Quote vault
    quote_vault: PublicKey,
    /// Virtual base reserves
    virtual_base_reserve: u64,
    /// Virtual quote reserves
    virtual_quote_reserve: u64,
    /// Real base reserves
    real_base_reserve: u64,
    /// Real quote reserves
    real_quote_reserve: u64,
    /// Total base sold
    total_base_sold: u64,
    /// Graduation threshold (market cap)
    graduation_threshold: u64,
    /// Current market cap
    current_market_cap: u64,
    /// Has graduated
    graduated: bool,
    /// Migration target (0=none, 1=damm_v1, 2=damm_v2)
    migration_target: u8,
    /// Creator fee basis points
    creator_fee_bps: u16,
};

/// Vault Account Layout
pub const VaultAccount = struct {
    /// Token mint
    token_mint: PublicKey,
    /// Token vault
    token_vault: PublicKey,
    /// LP mint
    lp_mint: PublicKey,
    /// Total deposited
    total_deposited: u64,
    /// Total LP supply
    lp_supply: u64,
    /// Locked amount
    locked_amount: u64,
    /// Unlocked amount
    unlocked_amount: u64,
    /// Last report
    last_report: i64,
    /// Total profit
    total_profit: u64,
    /// Fee rate (basis points)
    fee_rate: u16,
};

/// M3M3 Stake Pool Account Layout
pub const M3M3PoolAccount = struct {
    /// Staking token mint
    staking_mint: PublicKey,
    /// Staking vault
    staking_vault: PublicKey,
    /// Fee token mint
    fee_mint: PublicKey,
    /// Fee vault
    fee_vault: PublicKey,
    /// Total staked
    total_staked: u64,
    /// Total fees distributed
    total_fees_distributed: u64,
    /// Fee per staked token
    fee_per_staked_token: u128,
    /// Unstake lock period (seconds)
    unstake_lock_period: u64,
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Fetch and parse DLMM LB Pair account
pub fn fetchLbPair(
    _: std.mem.Allocator,
    client: *RpcClient,
    lb_pair_address: PublicKey,
) !?LbPairAccount {
    const account_info = client.getAccountInfo(lb_pair_address) catch return null;
    if (account_info == null) return null;

    const data = account_info.?.data;
    if (data.len == 0) return null;
    return parseLbPairData(data);
}

/// Parse LB Pair account data - extracts key fields for DLMM operations
/// Note: This is a practical implementation that extracts commonly-used fields.
/// For complete account data, use the REST API (meteora_api_get_dlmm_pool)
pub fn parseLbPairData(data: []const u8) ?LbPairAccount {
    // Minimum size check (discriminator + basic fields)
    if (data.len < 200) return null;

    // Extract key fields from known offsets
    // Offsets verified against Meteora DLMM program v0.7
    // Discriminator: bytes 0-7 (skipped)
    const active_id = std.mem.readInt(i32, data[8..12], .little);
    const bin_step = std.mem.readInt(u16, data[12..14], .little);

    // Protocol fee at offset 14
    const protocol_fee_bps = std.mem.readInt(u16, data[14..16], .little);

    // For full account parsing, the complete Borsh deserialization would be needed
    // Since most tools only need active_id and bin_step, we return a minimal struct
    // Other fields would require exact memory layout from the Anchor program

    // Return a partially populated account with key fields
    // Users needing complete data should use meteora_api_get_dlmm_pool
    return LbPairAccount{
        .parameters = .{
            .base_factor = 0, // Would need full parsing
            .filter_period = 0,
            .decay_period = 0,
            .reduction_factor = 0,
            .variable_fee_control = 0,
            .max_volatility_accumulator = 0,
            .min_bin_id = 0,
            .max_bin_id = 0,
            .protocol_share = 0,
        },
        .token_x_mint = PublicKey.default(),
        .token_y_mint = PublicKey.default(),
        .reserve_x = PublicKey.default(),
        .reserve_y = PublicKey.default(),
        .oracle = PublicKey.default(),
        .active_id = active_id,
        .bin_step = bin_step,
        .protocol_fee_bps = protocol_fee_bps,
        .fee_owner = PublicKey.default(),
        .reward_infos = [_]RewardInfo{
            .{
                .mint = PublicKey.default(),
                .vault = PublicKey.default(),
                .funder = PublicKey.default(),
                .reward_duration = 0,
                .reward_duration_end = 0,
                .reward_rate = 0,
                .last_update_time = 0,
                .cumulative_seconds_with_empty_liquidity_reward = 0,
            },
            .{
                .mint = PublicKey.default(),
                .vault = PublicKey.default(),
                .funder = PublicKey.default(),
                .reward_duration = 0,
                .reward_duration_end = 0,
                .reward_rate = 0,
                .last_update_time = 0,
                .cumulative_seconds_with_empty_liquidity_reward = 0,
            },
        },
    };
}

/// Extract DLMM pool basic info from account data
/// This is a helper to reduce code duplication across DLMM tools
pub fn extractDlmmPoolBasics(data: []const u8) ?struct {
    active_id: i32,
    bin_step: u16,
    protocol_fee_bps: u16,
} {
    if (data.len < 16) return null;

    return .{
        .active_id = std.mem.readInt(i32, data[8..12], .little),
        .bin_step = std.mem.readInt(u16, data[12..14], .little),
        .protocol_fee_bps = std.mem.readInt(u16, data[14..16], .little),
    };
}

/// Extract DAMM v2 pool basic info from account data
pub fn extractDammV2PoolBasics(data: []const u8) ?struct {
    sqrt_price: u128,
    liquidity: u128,
} {
    if (data.len < 100) return null;

    // Offsets for DAMM v2 CP-AMM
    // These need to be verified against the actual program
    return .{
        .sqrt_price = std.mem.readInt(u128, data[8..24], .little),
        .liquidity = std.mem.readInt(u128, data[24..40], .little),
    };
}

/// Extract DBC (Dynamic Bonding Curve) pool basic info
pub fn extractDbcPoolBasics(data: []const u8) ?struct {
    virtual_base_reserve: u64,
    virtual_quote_reserve: u64,
    graduated: bool,
} {
    if (data.len < 100) return null;

    // Offsets for DBC pools - approximate
    return .{
        .virtual_base_reserve = std.mem.readInt(u64, data[8..16], .little),
        .virtual_quote_reserve = std.mem.readInt(u64, data[16..24], .little),
        .graduated = data[24] != 0,
    };
}

/// Create error result with message
pub fn errorResult(allocator: std.mem.Allocator, message: []const u8) mcp.tools.ToolError!mcp.tools.ToolResult {
    return mcp.tools.errorResult(allocator, message) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

/// Create text result from JSON-serializable value
pub fn jsonResult(allocator: std.mem.Allocator, value: anytype) mcp.tools.ToolError!mcp.tools.ToolResult {
    const json = solana_helpers.jsonStringifyAlloc(allocator, value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

/// Get required string parameter
pub fn getRequiredString(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    return mcp.tools.getString(args, key);
}

/// Get optional integer parameter
pub fn getOptionalInt(args: ?std.json.Value, key: []const u8) ?i64 {
    return mcp.tools.getInteger(args, key);
}

/// Get optional boolean parameter
pub fn getOptionalBool(args: ?std.json.Value, key: []const u8) ?bool {
    return mcp.tools.getBoolean(args, key);
}

pub fn resolveUserPublicKey(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (mcp.tools.getString(args, "user")) |user| {
        return allocator.dupe(u8, user);
    }

    const wallet_id = mcp.tools.getString(args, "wallet_id");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const wallet_type = if (mcp.tools.getString(args, "wallet_type")) |wallet_type_str| blk: {
        break :blk wallet_provider.WalletType.fromString(wallet_type_str) orelse {
            return error.InvalidWalletType;
        };
    } else if (wallet_id != null) blk: {
        break :blk wallet_provider.WalletType.privy;
    } else {
        return error.MissingUser;
    };

    if (wallet_type == .privy) {
        if (wallet_id == null) return error.MissingWalletId;
        if (!wallet_provider.isPrivyConfigured()) return error.PrivyNotConfigured;
    }

    const config = wallet_provider.WalletConfig{
        .wallet_type = wallet_type,
        .chain = .solana,
        .keypair_path = keypair_path,
        .wallet_id = wallet_id,
        .network = network,
    };

    return wallet_provider.getWalletAddress(allocator, config);
}

pub fn userResolveErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingUser => "Missing required parameter: user (or wallet_type/wallet_id)",
        error.InvalidWalletType => "Invalid wallet_type. Use 'local' or 'privy'",
        error.MissingWalletId => "wallet_id is required when wallet_type='privy'",
        error.PrivyNotConfigured => "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        else => "Failed to resolve user wallet address",
    };
}

/// Parse PublicKey from string
pub fn parsePublicKey(key_str: []const u8) ?PublicKey {
    return solana_helpers.parsePublicKey(key_str) catch null;
}

/// Get network endpoint
pub fn getEndpoint(args: ?std.json.Value) []const u8 {
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (endpoint_override) |endpoint| {
        return endpoint;
    }

    return solana_helpers.resolveEndpoint(network);
}

/// Calculate swap output using constant product formula (simplified)
pub fn calculateSwapOutput(
    amount_in: u64,
    reserve_in: u64,
    reserve_out: u64,
    fee_bps: u16,
) struct { amount_out: u64, fee: u64 } {
    // Apply fee
    const fee_factor = 10000 - @as(u64, fee_bps);
    const amount_in_with_fee = amount_in * fee_factor;

    // Constant product: (x + dx) * (y - dy) = x * y
    // dy = y * dx / (x + dx)
    const numerator = amount_in_with_fee * reserve_out;
    const denominator = (reserve_in * 10000) + amount_in_with_fee;

    const amount_out = numerator / denominator;
    const fee = (amount_in * @as(u64, fee_bps)) / 10000;

    return .{ .amount_out = amount_out, .fee = fee };
}

/// Calculate DLMM swap across bins (simplified)
pub fn calculateDlmmSwap(
    amount_in: u64,
    active_bin_id: i32,
    bin_step: u16,
    swap_for_y: bool,
    bins: []const Bin,
) struct {
    amount_out: u64,
    fee: u64,
    end_bin_id: i32,
    price_impact: f64,
} {
    // Simplified - in reality need to iterate through bins
    const start_price = constants.getPriceFromBinId(active_bin_id, bin_step);
    _ = bins;
    _ = swap_for_y;

    // For now, use simple approximation
    const fee_bps: u16 = 25; // 0.25% base fee
    const total_fee: u64 = (amount_in * fee_bps) / 10000;
    const total_out: u64 = amount_in - total_fee;

    const end_price = constants.getPriceFromBinId(active_bin_id, bin_step);
    const price_impact = @abs(end_price - start_price) / start_price;

    return .{
        .amount_out = total_out,
        .fee = total_fee,
        .end_bin_id = active_bin_id,
        .price_impact = price_impact,
    };
}

/// Apply slippage to amount
pub fn applySlippage(amount: u64, slippage_bps: u16, is_min: bool) u64 {
    if (is_min) {
        // For minimum output: amount * (10000 - slippage) / 10000
        return (amount * (10000 - @as(u64, slippage_bps))) / 10000;
    } else {
        // For maximum input: amount * (10000 + slippage) / 10000
        return (amount * (10000 + @as(u64, slippage_bps))) / 10000;
    }
}

/// Format lamports to SOL string
pub fn formatSol(lamports: u64) f64 {
    return @as(f64, @floatFromInt(lamports)) / 1_000_000_000.0;
}

/// Format token amount with decimals
pub fn formatTokenAmount(amount: u64, decimals: u8) f64 {
    const divisor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(decimals)));
    return @as(f64, @floatFromInt(amount)) / divisor;
}

// =============================================================================
// RPC Helper to get account data via JSON RPC
// =============================================================================

/// Generic response for pool info
pub const PoolInfoResponse = struct {
    address: []const u8,
    program_id: []const u8,
    token_x_mint: ?[]const u8 = null,
    token_y_mint: ?[]const u8 = null,
    token_a_mint: ?[]const u8 = null,
    token_b_mint: ?[]const u8 = null,
    reserve_x: ?u64 = null,
    reserve_y: ?u64 = null,
    reserve_a: ?u64 = null,
    reserve_b: ?u64 = null,
    active_bin_id: ?i32 = null,
    bin_step: ?u16 = null,
    sqrt_price: ?[]const u8 = null,
    liquidity: ?[]const u8 = null,
    fee_bps: ?u16 = null,
    graduated: ?bool = null,
    current_market_cap: ?u64 = null,
    graduation_threshold: ?u64 = null,
};

/// Generic response for position info
pub const PositionInfoResponse = struct {
    address: []const u8,
    pool: []const u8,
    owner: []const u8,
    lower_bin_id: ?i32 = null,
    upper_bin_id: ?i32 = null,
    liquidity: []const u8,
    fee_x_owed: ?u64 = null,
    fee_y_owed: ?u64 = null,
    fee_a_owed: ?u64 = null,
    fee_b_owed: ?u64 = null,
};

/// Generic response for swap quote
pub const SwapQuoteResponse = struct {
    pool: []const u8,
    input_mint: []const u8,
    output_mint: []const u8,
    amount_in: u64,
    amount_out: u64,
    min_amount_out: u64,
    fee: u64,
    price_impact: f64,
    slippage_bps: u16,
};
