//! Jupiter Protocol Constants
//!
//! Configuration and constants for Jupiter:
//! - API endpoints
//! - Swap modes
//! - Default parameters
//! - Utility functions

const std = @import("std");

/// Jupiter API endpoints
pub const ENDPOINTS = struct {
    pub const QUOTE = "https://quote-api.jup.ag/v6/quote";
    pub const SWAP = "https://quote-api.jup.ag/v6/swap";
    pub const SWAP_INSTRUCTIONS = "https://quote-api.jup.ag/v6/swap-instructions";
    pub const TOKENS = "https://tokens.jup.ag/tokens";
    pub const PRICE = "https://api.jup.ag/price/v2";
};

/// Swap modes supported by Jupiter
pub const SwapMode = enum {
    ExactIn,
    ExactOut,

    pub fn toString(self: SwapMode) []const u8 {
        return switch (self) {
            .ExactIn => "ExactIn",
            .ExactOut => "ExactOut",
        };
    }

    pub fn fromString(str: []const u8) ?SwapMode {
        if (std.mem.eql(u8, str, "ExactIn")) return .ExactIn;
        if (std.mem.eql(u8, str, "ExactOut")) return .ExactOut;
        return null;
    }
};

/// Default swap parameters
pub const DEFAULTS = struct {
    /// Default slippage in basis points (50 = 0.5%)
    pub const SLIPPAGE_BPS: u16 = 50;

    /// Default swap mode
    pub const SWAP_MODE: SwapMode = .ExactIn;

    /// Minimum slippage (1 bps = 0.01%)
    pub const MIN_SLIPPAGE_BPS: u16 = 1;

    /// Maximum slippage (10000 bps = 100%)
    pub const MAX_SLIPPAGE_BPS: u16 = 10000;

    /// Default priority fee in lamports
    pub const PRIORITY_FEE_LAMPORTS: u64 = 1000;
};

/// Basis points constants
pub const BASIS_POINTS = struct {
    /// 1 basis point = 0.01%
    pub const ONE_BPS: f64 = 0.0001;

    /// Maximum basis points (100%)
    pub const MAX: u16 = 10000;

    /// Convert basis points to decimal percentage
    pub fn toDecimal(bps: u16) f64 {
        return @as(f64, @floatFromInt(bps)) * ONE_BPS;
    }

    /// Convert decimal percentage to basis points
    pub fn fromDecimal(decimal: f64) u16 {
        const bps_f = decimal / ONE_BPS;
        return @intFromFloat(@max(0.0, @min(bps_f, @as(f64, @floatFromInt(MAX)))));
    }

    /// Validate basis points value
    pub fn isValid(bps: u16) bool {
        return bps <= MAX;
    }
};

/// Calculate output amount with slippage
/// For ExactIn: output_with_slippage = output * (1 - slippage%)
/// For ExactOut: input_with_slippage = input * (1 + slippage%)
pub fn applySlippage(amount: u64, slippage_bps: u16, is_exact_in: bool) u64 {
    if (slippage_bps == 0) return amount;

    const amount_f = @as(f64, @floatFromInt(amount));
    const slippage_decimal = BASIS_POINTS.toDecimal(slippage_bps);

    const result_f = if (is_exact_in)
        amount_f * (1.0 - slippage_decimal) // Reduce output for ExactIn
    else
        amount_f * (1.0 + slippage_decimal); // Increase input for ExactOut

    // Round down for ExactIn (conservative output), round up for ExactOut (conservative input)
    const result = if (is_exact_in) @floor(result_f) else @ceil(result_f);

    return @intFromFloat(@max(0.0, result));
}

/// Calculate price impact percentage
/// price_impact = abs(expected_price - actual_price) / expected_price * 100
pub fn calculatePriceImpact(
    input_amount: u64,
    output_amount: u64,
    expected_price: f64,
) f64 {
    if (input_amount == 0 or output_amount == 0) return 0.0;

    const input_f = @as(f64, @floatFromInt(input_amount));
    const output_f = @as(f64, @floatFromInt(output_amount));

    const actual_price = output_f / input_f;
    const impact = @abs(expected_price - actual_price) / expected_price;

    return impact * 100.0; // Return as percentage
}

/// Validate slippage value
pub fn isValidSlippage(slippage_bps: u16) bool {
    return slippage_bps >= DEFAULTS.MIN_SLIPPAGE_BPS and
        slippage_bps <= DEFAULTS.MAX_SLIPPAGE_BPS;
}

// =============================================================================
// Tests
// =============================================================================

test "swap mode conversion" {
    // Test toString
    try std.testing.expectEqualStrings("ExactIn", SwapMode.ExactIn.toString());
    try std.testing.expectEqualStrings("ExactOut", SwapMode.ExactOut.toString());

    // Test fromString
    try std.testing.expectEqual(SwapMode.ExactIn, SwapMode.fromString("ExactIn").?);
    try std.testing.expectEqual(SwapMode.ExactOut, SwapMode.fromString("ExactOut").?);
    try std.testing.expect(SwapMode.fromString("Invalid") == null);
}

test "basis points conversion" {
    // Test toDecimal
    try std.testing.expectApproxEqAbs(0.005, BASIS_POINTS.toDecimal(50), 0.00001); // 50 bps = 0.5%
    try std.testing.expectApproxEqAbs(0.01, BASIS_POINTS.toDecimal(100), 0.00001); // 100 bps = 1%
    try std.testing.expectApproxEqAbs(1.0, BASIS_POINTS.toDecimal(10000), 0.00001); // 10000 bps = 100%

    // Test fromDecimal
    try std.testing.expectEqual(@as(u16, 50), BASIS_POINTS.fromDecimal(0.005)); // 0.5% = 50 bps
    try std.testing.expectEqual(@as(u16, 100), BASIS_POINTS.fromDecimal(0.01)); // 1% = 100 bps
    try std.testing.expectEqual(@as(u16, 10000), BASIS_POINTS.fromDecimal(1.0)); // 100% = 10000 bps

    // Test isValid
    try std.testing.expect(BASIS_POINTS.isValid(0));
    try std.testing.expect(BASIS_POINTS.isValid(50));
    try std.testing.expect(BASIS_POINTS.isValid(10000));
    try std.testing.expect(!BASIS_POINTS.isValid(10001));
}

test "apply slippage - ExactIn mode" {
    // ExactIn: reduce output amount
    // 1000 output with 1% slippage (100 bps) = 990
    const result1 = applySlippage(1000, 100, true);
    try std.testing.expectEqual(@as(u64, 990), result1);

    // 1000 output with 0.5% slippage (50 bps) = 995
    const result2 = applySlippage(1000, 50, true);
    try std.testing.expectEqual(@as(u64, 995), result2);

    // No slippage
    const result3 = applySlippage(1000, 0, true);
    try std.testing.expectEqual(@as(u64, 1000), result3);
}

test "apply slippage - ExactOut mode" {
    // ExactOut: increase input amount
    // 1000 input with 1% slippage (100 bps) = 1010
    const result1 = applySlippage(1000, 100, false);
    try std.testing.expectEqual(@as(u64, 1010), result1);

    // 1000 input with 0.5% slippage (50 bps) = 1005
    const result2 = applySlippage(1000, 50, false);
    try std.testing.expectEqual(@as(u64, 1005), result2);

    // No slippage
    const result3 = applySlippage(1000, 0, false);
    try std.testing.expectEqual(@as(u64, 1000), result3);
}

test "calculate price impact" {
    // No price impact
    const impact1 = calculatePriceImpact(1000, 1000, 1.0);
    try std.testing.expectApproxEqAbs(0.0, impact1, 0.001);

    // 1% price impact
    // Expected: 1.0, Actual: 0.99 (990/1000)
    const impact2 = calculatePriceImpact(1000, 990, 1.0);
    try std.testing.expectApproxEqAbs(1.0, impact2, 0.01);

    // 5% price impact
    // Expected: 1.0, Actual: 0.95 (950/1000)
    const impact3 = calculatePriceImpact(1000, 950, 1.0);
    try std.testing.expectApproxEqAbs(5.0, impact3, 0.01);
}

test "validate slippage" {
    // Valid slippage values
    try std.testing.expect(isValidSlippage(1));
    try std.testing.expect(isValidSlippage(50));
    try std.testing.expect(isValidSlippage(100));
    try std.testing.expect(isValidSlippage(10000));

    // Invalid slippage values
    try std.testing.expect(!isValidSlippage(0));
    try std.testing.expect(!isValidSlippage(10001));
}

test "default constants are valid" {
    // Verify defaults are within valid ranges
    try std.testing.expect(isValidSlippage(DEFAULTS.SLIPPAGE_BPS));
    try std.testing.expect(DEFAULTS.SLIPPAGE_BPS >= DEFAULTS.MIN_SLIPPAGE_BPS);
    try std.testing.expect(DEFAULTS.SLIPPAGE_BPS <= DEFAULTS.MAX_SLIPPAGE_BPS);
    try std.testing.expect(BASIS_POINTS.isValid(DEFAULTS.MAX_SLIPPAGE_BPS));
}
