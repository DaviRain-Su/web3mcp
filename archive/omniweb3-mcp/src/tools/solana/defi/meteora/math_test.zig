//! Additional tests for Meteora mathematical calculations
//!
//! Tests cover:
//! - Price calculation edge cases
//! - Bin ID calculations
//! - Slippage boundary conditions
//! - Large number handling

const std = @import("std");
const testing = std.testing;
const constants = @import("constants.zig");

// Test price from bin ID - edge cases
test "getPriceFromBinId - at zero bin" {
    // At bin 0, price should always be 1.0 regardless of bin step
    const price_1 = constants.getPriceFromBinId(0, 1);
    const price_10 = constants.getPriceFromBinId(0, 10);
    const price_100 = constants.getPriceFromBinId(0, 100);

    try testing.expectApproxEqAbs(1.0, price_1, 0.000001);
    try testing.expectApproxEqAbs(1.0, price_10, 0.000001);
    try testing.expectApproxEqAbs(1.0, price_100, 0.000001);
}

test "getPriceFromBinId - positive bins increase price" {
    const bin_step: u16 = 100; // 1%

    const price_0 = constants.getPriceFromBinId(0, bin_step);
    const price_1 = constants.getPriceFromBinId(1, bin_step);
    const price_10 = constants.getPriceFromBinId(10, bin_step);

    // Prices should increase
    try testing.expect(price_1 > price_0);
    try testing.expect(price_10 > price_1);
}

test "getPriceFromBinId - negative bins decrease price" {
    const bin_step: u16 = 100; // 1%

    const price_0 = constants.getPriceFromBinId(0, bin_step);
    const price_neg1 = constants.getPriceFromBinId(-1, bin_step);
    const price_neg10 = constants.getPriceFromBinId(-10, bin_step);

    // Prices should decrease
    try testing.expect(price_neg1 < price_0);
    try testing.expect(price_neg10 < price_neg1);
}

test "getPriceFromBinId - symmetry around zero" {
    const bin_step: u16 = 100; // 1%

    const price_pos = constants.getPriceFromBinId(5, bin_step);
    const price_neg = constants.getPriceFromBinId(-5, bin_step);

    // price_pos * price_neg should be approximately 1.0
    const product = price_pos * price_neg;
    try testing.expectApproxEqAbs(1.0, product, 0.001);
}

test "getPriceFromBinId - large bin step" {
    // Large bin step = more volatile price changes
    const large_step: u16 = 1000; // 10%

    const price_0 = constants.getPriceFromBinId(0, large_step);
    const price_1 = constants.getPriceFromBinId(1, large_step);

    try testing.expectApproxEqAbs(1.0, price_0, 0.000001);
    try testing.expectApproxEqAbs(1.1, price_1, 0.001); // ~10% higher
}

test "getPriceFromBinId - small bin step" {
    // Small bin step = less volatile price changes
    const small_step: u16 = 1; // 0.01%

    const price_0 = constants.getPriceFromBinId(0, small_step);
    const price_1 = constants.getPriceFromBinId(1, small_step);

    try testing.expectApproxEqAbs(1.0, price_0, 0.000001);
    try testing.expectApproxEqAbs(1.0001, price_1, 0.000001); // ~0.01% higher
}

// Test bin ID from price
test "getBinIdFromPrice - at price 1.0" {
    const bin_step: u16 = 100;

    // Price 1.0 should give bin 0
    const bin_down = constants.getBinIdFromPrice(1.0, bin_step, true);
    const bin_up = constants.getBinIdFromPrice(1.0, bin_step, false);

    try testing.expectEqual(@as(i32, 0), bin_down);
    try testing.expectEqual(@as(i32, 0), bin_up);
}

test "getBinIdFromPrice - round down vs round up" {
    const bin_step: u16 = 100;

    // Price between bin 0 and bin 1 (e.g., 1.005)
    const bin_down = constants.getBinIdFromPrice(1.005, bin_step, true);
    const bin_up = constants.getBinIdFromPrice(1.005, bin_step, false);

    // Round down should give 0, round up should give 1
    try testing.expectEqual(@as(i32, 0), bin_down);
    try testing.expectEqual(@as(i32, 1), bin_up);
}

test "getBinIdFromPrice - negative bins for prices < 1" {
    const bin_step: u16 = 100;

    // Price 0.99 should give negative bin
    const bin = constants.getBinIdFromPrice(0.99, bin_step, true);
    try testing.expect(bin < 0);
}

test "getBinIdFromPrice - large price" {
    const bin_step: u16 = 100;

    // Price 2.0 should give positive bin
    const bin = constants.getBinIdFromPrice(2.0, bin_step, true);
    try testing.expect(bin > 0);

    // Verify roundtrip (with relaxed tolerance due to floating point precision)
    const recovered_price = constants.getPriceFromBinId(bin, bin_step);
    try testing.expectApproxEqAbs(2.0, recovered_price, 0.02);
}

test "getBinIdFromPrice - small price" {
    const bin_step: u16 = 100;

    // Price 0.5 should give negative bin
    const bin = constants.getBinIdFromPrice(0.5, bin_step, true);
    try testing.expect(bin < 0);

    // Verify roundtrip
    const recovered_price = constants.getPriceFromBinId(bin, bin_step);
    try testing.expectApproxEqAbs(0.5, recovered_price, 0.01);
}

// Test bin array index calculation
test "getBinArrayIndexFromBinId - positive bins" {
    // Bins 0-69 should be in array 0
    const idx_0 = constants.getBinArrayIndexFromBinId(0);
    const idx_69 = constants.getBinArrayIndexFromBinId(69);
    try testing.expectEqual(@as(i64, 0), idx_0);
    try testing.expectEqual(@as(i64, 0), idx_69);

    // Bin 70 should be in array 1
    const idx_70 = constants.getBinArrayIndexFromBinId(70);
    try testing.expectEqual(@as(i64, 1), idx_70);

    // Bin 140 should be in array 2
    const idx_140 = constants.getBinArrayIndexFromBinId(140);
    try testing.expectEqual(@as(i64, 2), idx_140);
}

test "getBinArrayIndexFromBinId - negative bins" {
    // Bin -1 is in array -1
    const idx_neg1 = constants.getBinArrayIndexFromBinId(-1);
    try testing.expectEqual(@as(i64, -1), idx_neg1);

    // Test a few negative bins to verify the pattern
    const idx_neg10 = constants.getBinArrayIndexFromBinId(-10);
    try testing.expect(idx_neg10 < 0);

    const idx_neg100 = constants.getBinArrayIndexFromBinId(-100);
    try testing.expect(idx_neg100 < 0);

    // Verify that more negative bins have more negative array indices
    const idx_neg1000 = constants.getBinArrayIndexFromBinId(-1000);
    try testing.expect(idx_neg1000 < idx_neg100);
    try testing.expect(idx_neg100 < idx_neg10);
    try testing.expect(idx_neg10 < idx_neg1);
}

test "getBinArrayIndexFromBinId - at boundaries" {
    const max_bin_per_array: i32 = @intCast(constants.DLMM_MATH.MAX_BIN_PER_ARRAY);

    // Just below boundary
    const idx_before = constants.getBinArrayIndexFromBinId(max_bin_per_array - 1);
    try testing.expectEqual(@as(i64, 0), idx_before);

    // At boundary
    const idx_at = constants.getBinArrayIndexFromBinId(max_bin_per_array);
    try testing.expectEqual(@as(i64, 1), idx_at);

    // Just above boundary
    const idx_after = constants.getBinArrayIndexFromBinId(max_bin_per_array + 1);
    try testing.expectEqual(@as(i64, 1), idx_after);
}

// Test bin ID limits
test "DLMM_MATH constants are valid" {
    // Verify bin ID limits
    try testing.expectEqual(@as(i32, 443636), constants.DLMM_MATH.MAX_BIN_ID);
    try testing.expectEqual(@as(i32, -443636), constants.DLMM_MATH.MIN_BIN_ID);

    // Verify basis points
    try testing.expectEqual(@as(u64, 10000), constants.DLMM_MATH.BASIS_POINT_MAX);

    // Verify bin array size
    try testing.expectEqual(@as(u32, 70), constants.DLMM_MATH.MAX_BIN_PER_ARRAY);
    try testing.expectEqual(@as(u32, 70), constants.DLMM_MATH.MAX_BIN_PER_POSITION);
}

// Test fee tiers
test "fee tier constants are valid" {
    // Verify tier 1 (0.25%)
    try testing.expectEqual(@as(u16, 25), constants.FeeTier.TIER_1.base_fee_bps);
    try testing.expectEqual(@as(u8, 20), constants.FeeTier.TIER_1.protocol_fee_percent);

    // Verify tier 6 (6%)
    try testing.expectEqual(@as(u16, 600), constants.FeeTier.TIER_6.base_fee_bps);
    try testing.expectEqual(@as(u8, 20), constants.FeeTier.TIER_6.protocol_fee_percent);

    // All tiers should have 20% protocol fee
    try testing.expectEqual(@as(u8, 20), constants.FeeTier.TIER_2.protocol_fee_percent);
    try testing.expectEqual(@as(u8, 20), constants.FeeTier.TIER_3.protocol_fee_percent);
    try testing.expectEqual(@as(u8, 20), constants.FeeTier.TIER_4.protocol_fee_percent);
    try testing.expectEqual(@as(u8, 20), constants.FeeTier.TIER_5.protocol_fee_percent);
}

// Test strategy type enum
test "StrategyType enum values" {
    // Verify enum values are sequential
    try testing.expectEqual(@as(u8, 0), @intFromEnum(constants.StrategyType.SpotOneSide));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(constants.StrategyType.CurveOneSide));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(constants.StrategyType.BidAskImBalanced));
}

// Test swap mode enum
test "SwapMode enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(constants.SwapMode.ExactIn));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(constants.SwapMode.ExactOut));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(constants.SwapMode.PartialFill));
}

// Test roundtrip: bin ID -> price -> bin ID
test "price calculation roundtrip" {
    const bin_step: u16 = 100;

    // Test roundtrip for various bin IDs
    const test_bins = [_]i32{ -100, -10, -1, 0, 1, 10, 100, 1000 };

    for (test_bins) |bin_id| {
        const price = constants.getPriceFromBinId(bin_id, bin_step);
        const recovered_bin = constants.getBinIdFromPrice(price, bin_step, true);

        // Should recover the same bin ID (or very close)
        const diff = @abs(recovered_bin - bin_id);
        try testing.expect(diff <= 1);
    }
}
