//! Meteora Protocol Constants
//!
//! Program IDs and constants for all Meteora protocols:
//! - DLMM (Dynamic Liquidity Market Maker)
//! - DAMM v2 (CP-AMM - Constant Product AMM)
//! - DAMM v1 (Legacy Dynamic AMM)
//! - Dynamic Bonding Curve (Token launches)
//! - Dynamic Vault (Yield optimization)
//! - Stake-for-Fee (M3M3)
//! - Zap (Single-token entry/exit)

const std = @import("std");
const solana_sdk = @import("solana_sdk");
const PublicKey = solana_sdk.PublicKey;

/// Program ID strings for display/comparison
pub const PROGRAM_IDS = struct {
    pub const DLMM = "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo";
    pub const DAMM_V2 = "cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG";
    pub const DAMM_V1 = "Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB";
    pub const DBC = "dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN";
    pub const VAULT = "24Uqj9JCLxUeoC3hGfh5W3s9FM9uCHDS2SG3LYwBpyTi";
    pub const M3M3 = "FEESngU3neckdwib9X3KWqdL7Mjmqk9XNp3uh5JbP4KP";
    pub const ZAP = "zapvX9M3uf5pvy4wRPAbQgdQsM1xmuiFnkfHKPvwMiz";
};

/// Get DLMM Program PublicKey (runtime parsed)
pub fn getDlmmProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.DLMM);
}

/// Get DAMM v2 Program PublicKey
pub fn getDammV2ProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.DAMM_V2);
}

/// Get DAMM v1 Program PublicKey
pub fn getDammV1ProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.DAMM_V1);
}

/// Get DBC Program PublicKey
pub fn getDbcProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.DBC);
}

/// Get Vault Program PublicKey
pub fn getVaultProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.VAULT);
}

/// Get M3M3 Program PublicKey
pub fn getM3M3ProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.M3M3);
}

/// Get Zap Program PublicKey
pub fn getZapProgramId() !PublicKey {
    return PublicKey.fromBase58(PROGRAM_IDS.ZAP);
}

/// Check if pubkey matches a program ID string
pub fn isProgramId(pubkey: PublicKey, program_id_str: []const u8) bool {
    var buf: [44]u8 = undefined;
    const pubkey_str = pubkey.toBase58(&buf);
    return std.mem.eql(u8, pubkey_str, program_id_str);
}

// =============================================================================
// DLMM Seeds for PDA derivation
// =============================================================================

pub const DLMM_SEEDS = struct {
    pub const LB_PAIR = "lb_pair";
    pub const ORACLE = "oracle";
    pub const BIN_ARRAY = "bin_array";
    pub const POSITION = "position";
    pub const BIN_ARRAY_BITMAP_EXTENSION = "bitmap";
    pub const PRESET_PARAMETER = "preset_parameter";
    pub const FEE_OWNER = "fee_owner";
    pub const REWARD = "reward";
    pub const PERMISSION = "permission";
    pub const LOCK_RELEASE_POINT = "lock_release_point";
};

// =============================================================================
// DAMM v2 Seeds for PDA derivation
// =============================================================================

pub const DAMM_V2_SEEDS = struct {
    pub const POOL = "pool";
    pub const POSITION = "position";
    pub const TOKEN_VAULT = "token_vault";
    pub const LP_MINT = "lp_mint";
    pub const REWARD = "reward";
    pub const LOCK = "lock";
};

// =============================================================================
// Dynamic Bonding Curve Seeds
// =============================================================================

pub const DBC_SEEDS = struct {
    pub const POOL = "pool";
    pub const BASE_VAULT = "base_vault";
    pub const QUOTE_VAULT = "quote_vault";
    pub const CONFIG = "config";
    pub const CREATOR_METADATA = "creator_metadata";
};

// =============================================================================
// Vault Seeds
// =============================================================================

pub const VAULT_SEEDS = struct {
    pub const VAULT = "vault";
    pub const TOKEN_VAULT = "token_vault";
    pub const LP_MINT = "lp_mint";
    pub const COLLATERAL_VAULT = "collateral_vault";
};

// =============================================================================
// DLMM Bin Math Constants
// =============================================================================

pub const DLMM_MATH = struct {
    /// Basis for bin steps (10000 = 1%)
    pub const BASIS_POINT_MAX: u64 = 10000;

    /// Maximum bin ID
    pub const MAX_BIN_ID: i32 = 443636;

    /// Minimum bin ID
    pub const MIN_BIN_ID: i32 = -443636;

    /// Price precision (128-bit fixed point)
    pub const PRICE_PRECISION: u128 = 1 << 64;

    /// Maximum number of bins per array
    pub const MAX_BIN_PER_ARRAY: u32 = 70;

    /// Maximum bins per position
    pub const MAX_BIN_PER_POSITION: u32 = 70;
};

// =============================================================================
// Fee Tier Configurations
// =============================================================================

pub const FeeTier = struct {
    base_fee_bps: u16,
    protocol_fee_percent: u8,

    pub const TIER_1 = FeeTier{ .base_fee_bps = 25, .protocol_fee_percent = 20 }; // 0.25%
    pub const TIER_2 = FeeTier{ .base_fee_bps = 50, .protocol_fee_percent = 20 }; // 0.50%
    pub const TIER_3 = FeeTier{ .base_fee_bps = 100, .protocol_fee_percent = 20 }; // 1.00%
    pub const TIER_4 = FeeTier{ .base_fee_bps = 200, .protocol_fee_percent = 20 }; // 2.00%
    pub const TIER_5 = FeeTier{ .base_fee_bps = 400, .protocol_fee_percent = 20 }; // 4.00%
    pub const TIER_6 = FeeTier{ .base_fee_bps = 600, .protocol_fee_percent = 20 }; // 6.00%
};

// =============================================================================
// DLMM Strategy Types
// =============================================================================

pub const StrategyType = enum(u8) {
    SpotOneSide = 0,
    CurveOneSide = 1,
    BidAskOneSide = 2,
    SpotBalanced = 3,
    CurveBalanced = 4,
    BidAskBalanced = 5,
    SpotImBalanced = 6,
    CurveImBalanced = 7,
    BidAskImBalanced = 8,
};

// =============================================================================
// DAMM v2 Swap Modes
// =============================================================================

pub const SwapMode = enum(u8) {
    ExactIn = 0,
    ExactOut = 1,
    PartialFill = 2,
};

// =============================================================================
// Pool Activation Types
// =============================================================================

pub const ActivationType = enum(u8) {
    Slot = 0,
    Timestamp = 1,
};

// =============================================================================
// Collect Fee Modes
// =============================================================================

pub const CollectFeeMode = enum(u8) {
    OnlyQuote = 0,
    Both = 1,
};

// =============================================================================
// Helper Functions - PDA Derivation
// Note: PDA derivation requires program ID at runtime.
// These functions return seed arrays for use with PublicKey.findProgramAddress
// =============================================================================

/// Get DLMM LB Pair seeds (for off-chain PDA derivation)
pub fn getDlmmLbPairSeeds(
    token_x_bytes: *const [32]u8,
    token_y_bytes: *const [32]u8,
    bin_step_bytes: *const [2]u8,
) [4][]const u8 {
    return .{
        DLMM_SEEDS.LB_PAIR,
        token_x_bytes,
        token_y_bytes,
        bin_step_bytes,
    };
}

/// Get DLMM Bin Array index
pub fn getDlmmBinArrayIndex(bin_id: i32) i64 {
    const bin_id_i64: i64 = @intCast(bin_id);
    const max_bin: i64 = @intCast(DLMM_MATH.MAX_BIN_PER_ARRAY);

    if (bin_id >= 0) {
        return @divFloor(bin_id_i64, max_bin);
    } else {
        return @divFloor(bin_id_i64 - max_bin + 1, max_bin);
    }
}

// =============================================================================
// DLMM Price/Bin Math
// =============================================================================

/// Calculate price from bin ID
/// price = (1 + binStep / 10000) ^ binId
pub fn getPriceFromBinId(bin_id: i32, bin_step: u16) f64 {
    const base = 1.0 + @as(f64, @floatFromInt(bin_step)) / @as(f64, @floatFromInt(DLMM_MATH.BASIS_POINT_MAX));
    return std.math.pow(f64, base, @as(f64, @floatFromInt(bin_id)));
}

/// Calculate bin ID from price
/// binId = log(price) / log(1 + binStep / 10000)
pub fn getBinIdFromPrice(price: f64, bin_step: u16, round_down: bool) i32 {
    const base = 1.0 + @as(f64, @floatFromInt(bin_step)) / @as(f64, @floatFromInt(DLMM_MATH.BASIS_POINT_MAX));
    const bin_id_f = @log(price) / @log(base);

    if (round_down) {
        return @intFromFloat(@floor(bin_id_f));
    } else {
        return @intFromFloat(@ceil(bin_id_f));
    }
}

/// Get bin array index from bin ID
pub fn getBinArrayIndexFromBinId(bin_id: i32) i64 {
    const bin_id_i64: i64 = @intCast(bin_id);
    const max_bin: i64 = @intCast(DLMM_MATH.MAX_BIN_PER_ARRAY);

    if (bin_id >= 0) {
        return @divFloor(bin_id_i64, max_bin);
    } else {
        return @divFloor(bin_id_i64 - max_bin + 1, max_bin);
    }
}

// =============================================================================
// Tests
// =============================================================================

test "program IDs are valid strings" {
    // Verify program ID strings are valid Base58
    try std.testing.expect(PROGRAM_IDS.DLMM.len > 0);
    try std.testing.expect(PROGRAM_IDS.DAMM_V2.len > 0);
    try std.testing.expect(PROGRAM_IDS.DAMM_V1.len > 0);
    try std.testing.expect(PROGRAM_IDS.DBC.len > 0);
    try std.testing.expect(PROGRAM_IDS.VAULT.len > 0);
    try std.testing.expect(PROGRAM_IDS.M3M3.len > 0);
    try std.testing.expect(PROGRAM_IDS.ZAP.len > 0);
}

test "bin price calculation" {
    // Bin step 100 = 1%
    // At bin 0, price should be 1.0
    const price_at_0 = getPriceFromBinId(0, 100);
    try std.testing.expectApproxEqAbs(price_at_0, 1.0, 0.0001);

    // At bin 1 with 1% step, price should be ~1.01
    const price_at_1 = getPriceFromBinId(1, 100);
    try std.testing.expectApproxEqAbs(price_at_1, 1.01, 0.0001);

    // At bin -1 with 1% step, price should be ~0.99
    const price_at_neg1 = getPriceFromBinId(-1, 100);
    try std.testing.expectApproxEqAbs(price_at_neg1, 0.9901, 0.001);
}

test "bin id from price calculation" {
    const bin_step: u16 = 100; // 1%

    // Price 1.0 should give bin 0
    const bin_0 = getBinIdFromPrice(1.0, bin_step, true);
    try std.testing.expectEqual(@as(i32, 0), bin_0);

    // Price ~1.01 should give bin 1
    const bin_1 = getBinIdFromPrice(1.01, bin_step, true);
    try std.testing.expectEqual(@as(i32, 1), bin_1);
}
