//! Additional edge case tests for Jupiter constants
//!
//! Tests cover:
//! - Slippage edge cases
//! - Price impact boundaries
//! - Basis points extremes

const std = @import("std");
const testing = std.testing;
const constants = @import("constants.zig");

// Test slippage with zero amount
test "applySlippage - zero amount exact in" {
    const result = constants.applySlippage(0, 100, true);
    try testing.expectEqual(@as(u64, 0), result);
}

test "applySlippage - zero amount exact out" {
    const result = constants.applySlippage(0, 100, false);
    try testing.expectEqual(@as(u64, 0), result);
}

// Test slippage with zero slippage
test "applySlippage - zero slippage exact in" {
    const amount: u64 = 1000000;
    const result = constants.applySlippage(amount, 0, true);
    try testing.expectEqual(amount, result);
}

test "applySlippage - zero slippage exact out" {
    const amount: u64 = 1000000;
    const result = constants.applySlippage(amount, 0, false);
    try testing.expectEqual(amount, result);
}

// Test slippage with max basis points (100%)
test "applySlippage - max slippage exact in" {
    const amount: u64 = 1000000;
    const result = constants.applySlippage(amount, 10000, true);
    // 100% slippage on exact in = minimum out is 0
    try testing.expectEqual(@as(u64, 0), result);
}

test "applySlippage - max slippage exact out" {
    const amount: u64 = 1000000;
    const result = constants.applySlippage(amount, 10000, false);
    // 100% slippage on exact out = maximum in is 2x amount
    try testing.expectEqual(@as(u64, 2000000), result);
}

// Test price impact edge cases
test "calculatePriceImpact - identical prices" {
    // expected_price should be output/input ratio
    // input=1000000, output=1000000, ratio = 1.0
    const impact = constants.calculatePriceImpact(1000000, 1000000, 1.0);
    try testing.expectApproxEqAbs(0.0, impact, 0.000001);
}

test "calculatePriceImpact - zero output amount" {
    // Zero output amount returns 0.0 (handled by early return)
    const impact = constants.calculatePriceImpact(1000000, 0, 1.0);
    try testing.expectApproxEqAbs(0.0, impact, 0.000001);
}

test "calculatePriceImpact - zero input amount" {
    // Zero input amount returns 0.0 (handled by early return)
    const impact = constants.calculatePriceImpact(0, 1000000, 1.0);
    try testing.expectApproxEqAbs(0.0, impact, 0.000001);
}

test "calculatePriceImpact - 10% price impact" {
    // Expected price 1.0, actual price 0.9 (900/1000)
    // Impact = |1.0 - 0.9| / 1.0 = 0.1 = 10%
    const impact = constants.calculatePriceImpact(1000, 900, 1.0);
    try testing.expectApproxEqAbs(10.0, impact, 0.01);
}

test "calculatePriceImpact - 50% price impact" {
    // Expected price 1.0, actual price 0.5 (500/1000)
    // Impact = |1.0 - 0.5| / 1.0 = 0.5 = 50%
    const impact = constants.calculatePriceImpact(1000, 500, 1.0);
    try testing.expectApproxEqAbs(50.0, impact, 0.01);
}

test "calculatePriceImpact - better than expected price" {
    // Expected price 1.0, actual price 1.1 (1100/1000)
    // Impact = |1.0 - 1.1| / 1.0 = 0.1 = 10% (negative impact, better price)
    const impact = constants.calculatePriceImpact(1000, 1100, 1.0);
    try testing.expectApproxEqAbs(10.0, impact, 0.01);
}

// Test basis points conversion roundtrip
test "BASIS_POINTS roundtrip" {
    const bps_values = [_]u16{ 0, 1, 10, 50, 100, 500, 1000, 5000, 9999, 10000 };

    for (bps_values) |bps| {
        const decimal = constants.BASIS_POINTS.toDecimal(bps);
        const recovered_bps = constants.BASIS_POINTS.fromDecimal(decimal);

        // Should recover same value (or very close for rounding)
        const diff = if (recovered_bps > bps) recovered_bps - bps else bps - recovered_bps;
        try testing.expect(diff <= 1);
    }
}
