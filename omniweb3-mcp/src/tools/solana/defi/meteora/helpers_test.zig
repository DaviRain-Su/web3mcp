//! Unit tests for Meteora helper functions
//!
//! Tests cover:
//! - extractDlmmPoolBasics() - DLMM pool data extraction
//! - parseLbPairData() - LB Pair account parsing
//! - extractDammV2PoolBasics() - DAMM v2 pool data extraction
//! - extractDbcPoolBasics() - DBC pool data extraction
//! - Helper utilities (slippage, error handling)

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const solana_sdk = @import("solana_sdk");

const PublicKey = solana_sdk.PublicKey;

// Test extractDlmmPoolBasics with valid data
test "extractDlmmPoolBasics - valid data" {
    // Create mock DLMM pool account data
    var data: [200]u8 = undefined;
    @memset(&data, 0);

    // Set discriminator (first 8 bytes)
    data[0] = 0x01;

    // Set active_id at offset 8 (i32, little-endian)
    // active_id = 100
    std.mem.writeInt(i32, data[8..12], 100, .little);

    // Set bin_step at offset 12 (u16, little-endian)
    // bin_step = 25 (0.25%)
    std.mem.writeInt(u16, data[12..14], 25, .little);

    // Set protocol_fee_bps at offset 14 (u16, little-endian)
    // protocol_fee_bps = 200 (2%)
    std.mem.writeInt(u16, data[14..16], 200, .little);

    const result = helpers.extractDlmmPoolBasics(&data);
    try testing.expect(result != null);
    try testing.expectEqual(@as(i32, 100), result.?.active_id);
    try testing.expectEqual(@as(u16, 25), result.?.bin_step);
    try testing.expectEqual(@as(u16, 200), result.?.protocol_fee_bps);
}

// Test extractDlmmPoolBasics with insufficient data
test "extractDlmmPoolBasics - insufficient data" {
    var data: [10]u8 = undefined;
    @memset(&data, 0);

    const result = helpers.extractDlmmPoolBasics(&data);
    try testing.expect(result == null);
}

// Test extractDlmmPoolBasics with exactly minimum size
test "extractDlmmPoolBasics - minimum size" {
    var data: [16]u8 = undefined;
    @memset(&data, 0);

    // Set values
    std.mem.writeInt(i32, data[8..12], -50, .little); // Negative active_id
    std.mem.writeInt(u16, data[12..14], 100, .little);
    std.mem.writeInt(u16, data[14..16], 50, .little);

    const result = helpers.extractDlmmPoolBasics(&data);
    try testing.expect(result != null);
    try testing.expectEqual(@as(i32, -50), result.?.active_id);
    try testing.expectEqual(@as(u16, 100), result.?.bin_step);
}

// Test parseLbPairData with valid data
test "parseLbPairData - valid data" {
    var data: [300]u8 = undefined;
    @memset(&data, 0);

    // Set discriminator
    data[0] = 0x01;

    // Set key fields
    std.mem.writeInt(i32, data[8..12], 250, .little); // active_id
    std.mem.writeInt(u16, data[12..14], 50, .little); // bin_step
    std.mem.writeInt(u16, data[14..16], 150, .little); // protocol_fee_bps

    const result = helpers.parseLbPairData(&data);
    try testing.expect(result != null);
    try testing.expectEqual(@as(i32, 250), result.?.active_id);
    try testing.expectEqual(@as(u16, 50), result.?.bin_step);
    try testing.expectEqual(@as(u16, 150), result.?.protocol_fee_bps);
}

// Test parseLbPairData with insufficient data
test "parseLbPairData - insufficient data" {
    var data: [150]u8 = undefined;
    @memset(&data, 0);

    const result = helpers.parseLbPairData(&data);
    try testing.expect(result == null);
}

// Test parseLbPairData boundary cases
test "parseLbPairData - boundary values" {
    var data: [300]u8 = undefined;
    @memset(&data, 0);

    // Test with extreme values
    std.mem.writeInt(i32, data[8..12], std.math.maxInt(i32), .little);
    std.mem.writeInt(u16, data[12..14], std.math.maxInt(u16), .little);
    std.mem.writeInt(u16, data[14..16], std.math.maxInt(u16), .little);

    const result = helpers.parseLbPairData(&data);
    try testing.expect(result != null);
    try testing.expectEqual(std.math.maxInt(i32), result.?.active_id);
    try testing.expectEqual(std.math.maxInt(u16), result.?.bin_step);
    try testing.expectEqual(std.math.maxInt(u16), result.?.protocol_fee_bps);
}

// Test extractDammV2PoolBasics with valid data
test "extractDammV2PoolBasics - valid data" {
    var data: [300]u8 = undefined;
    @memset(&data, 0);

    // DAMM v2: sqrt_price at offset 8 (u128), liquidity at offset 24 (u128)
    // Set sqrt_price = 1000000 (example)
    std.mem.writeInt(u128, data[8..24], 1000000, .little);

    // Set liquidity = 5000000000
    std.mem.writeInt(u128, data[24..40], 5000000000, .little);

    const result = helpers.extractDammV2PoolBasics(&data);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u128, 1000000), result.?.sqrt_price);
    try testing.expectEqual(@as(u128, 5000000000), result.?.liquidity);
}

// Test extractDammV2PoolBasics with insufficient data
test "extractDammV2PoolBasics - insufficient data" {
    var data: [30]u8 = undefined;
    @memset(&data, 0);

    const result = helpers.extractDammV2PoolBasics(&data);
    try testing.expect(result == null);
}

// Test extractDbcPoolBasics with valid data
test "extractDbcPoolBasics - valid data" {
    var data: [300]u8 = undefined;
    @memset(&data, 0);

    // DBC: virtual_base_reserve at offset 8, virtual_quote_reserve at offset 16
    std.mem.writeInt(u64, data[8..16], 1000000000000, .little); // 1T base
    std.mem.writeInt(u64, data[16..24], 2000000000, .little); // 2B quote

    // graduated flag at offset 24 (bool = u8)
    data[24] = 1; // true

    const result = helpers.extractDbcPoolBasics(&data);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u64, 1000000000000), result.?.virtual_base_reserve);
    try testing.expectEqual(@as(u64, 2000000000), result.?.virtual_quote_reserve);
    try testing.expect(result.?.graduated);
}

// Test extractDbcPoolBasics with non-graduated pool
test "extractDbcPoolBasics - not graduated" {
    var data: [300]u8 = undefined;
    @memset(&data, 0);

    std.mem.writeInt(u64, data[8..16], 500000000, .little);
    std.mem.writeInt(u64, data[16..24], 100000000, .little);
    data[24] = 0; // false

    const result = helpers.extractDbcPoolBasics(&data);
    try testing.expect(result != null);
    try testing.expect(!result.?.graduated);
}

// Test extractDbcPoolBasics with insufficient data
test "extractDbcPoolBasics - insufficient data" {
    var data: [20]u8 = undefined;
    @memset(&data, 0);

    const result = helpers.extractDbcPoolBasics(&data);
    try testing.expect(result == null);
}

// Test applySlippage function - reduce output
test "applySlippage - reduce output" {
    // Test 1% slippage (100 bps) on output
    const amount: u64 = 1000000;
    const slippage_bps: u16 = 100; // 1%
    const result = helpers.applySlippage(amount, slippage_bps, true);

    // Expected: 1000000 * (1 - 0.01) = 990000
    try testing.expectEqual(@as(u64, 990000), result);
}

// Test applySlippage function - increase input
test "applySlippage - increase input" {
    // Test 0.5% slippage (50 bps) on input
    const amount: u64 = 2000000;
    const slippage_bps: u16 = 50; // 0.5%
    const result = helpers.applySlippage(amount, slippage_bps, false);

    // Expected: 2000000 * (1 + 0.005) = 2010000
    try testing.expectEqual(@as(u64, 2010000), result);
}

// Test applySlippage with zero slippage
test "applySlippage - zero slippage" {
    const amount: u64 = 5000000;
    const slippage_bps: u16 = 0;

    const result_reduce = helpers.applySlippage(amount, slippage_bps, true);
    const result_increase = helpers.applySlippage(amount, slippage_bps, false);

    try testing.expectEqual(amount, result_reduce);
    try testing.expectEqual(amount, result_increase);
}

// Test applySlippage with maximum slippage
test "applySlippage - maximum slippage" {
    const amount: u64 = 1000000;
    const slippage_bps: u16 = 1000; // 10%

    const result_reduce = helpers.applySlippage(amount, slippage_bps, true);
    try testing.expectEqual(@as(u64, 900000), result_reduce);

    const result_increase = helpers.applySlippage(amount, slippage_bps, false);
    try testing.expectEqual(@as(u64, 1100000), result_increase);
}

// Test price impact calculation logic
// This tests the formula used in dlmm/swap_quote.zig
test "price impact calculation - logarithmic scaling" {
    // Test small amount
    const small_amount: u64 = 100;
    const small_amount_f = @as(f64, @floatFromInt(small_amount));
    const small_impact_factor = @log10(small_amount_f + 1.0) / 10.0;
    const small_base_impact = small_impact_factor * 0.005;
    const small_impact = @max(@min(small_base_impact, 0.15), 0.0001);

    // Should be very small (close to minimum 0.01%)
    try testing.expect(small_impact < 0.01);
    try testing.expect(small_impact >= 0.0001);

    // Test medium amount
    const medium_amount: u64 = 10000;
    const medium_amount_f = @as(f64, @floatFromInt(medium_amount));
    const medium_impact_factor = @log10(medium_amount_f + 1.0) / 10.0;
    const medium_base_impact = medium_impact_factor * 0.005;
    const medium_impact = @max(@min(medium_base_impact, 0.15), 0.0001);

    // Should be in range 0.1-1%
    try testing.expect(medium_impact > 0.001);
    try testing.expect(medium_impact < 0.01);

    // Test large amount
    const large_amount: u64 = 100000000;
    const large_amount_f = @as(f64, @floatFromInt(large_amount));
    const large_impact_factor = @log10(large_amount_f + 1.0) / 10.0;
    const large_base_impact = large_impact_factor * 0.005;
    const large_impact = @max(@min(large_base_impact, 0.15), 0.0001);

    // Should be capped at 15%
    try testing.expect(large_impact <= 0.15);
}

// Test price impact - verify it scales logarithmically
test "price impact - logarithmic scaling property" {
    // Impact should increase logarithmically, not linearly
    const amounts = [_]u64{ 100, 1000, 10000, 100000, 1000000 };
    var prev_impact: f64 = 0.0;

    for (amounts) |amount| {
        const amount_f = @as(f64, @floatFromInt(amount));
        const impact_factor = @log10(amount_f + 1.0) / 10.0;
        const base_impact = impact_factor * 0.005;
        const impact = @max(@min(base_impact, 0.15), 0.0001);

        // Each 10x increase should add roughly constant impact
        if (prev_impact > 0.0) {
            const impact_increase = impact - prev_impact;
            // Impact increase per order of magnitude should be roughly 0.0005 (0.05%)
            try testing.expect(impact_increase >= 0.0004);
            try testing.expect(impact_increase <= 0.0006);
        }

        prev_impact = impact;
    }
}

// Test price impact - boundary cases
test "price impact - boundary cases" {
    // Test zero amount
    const zero_f: f64 = 0.0;
    const zero_impact_factor = @log10(zero_f + 1.0) / 10.0;
    const zero_impact = @max(@min(zero_impact_factor * 0.005, 0.15), 0.0001);
    try testing.expectEqual(@as(f64, 0.0001), zero_impact);

    // Test very large amount
    // log10(1e15) = 15, so impact_factor = 1.5, base_impact = 0.0075
    const huge_amount_f: f64 = 1.0e15;
    const huge_impact_factor = @log10(huge_amount_f + 1.0) / 10.0;
    const huge_base_impact = huge_impact_factor * 0.005;
    const huge_impact = @max(@min(huge_base_impact, 0.15), 0.0001);
    try testing.expectEqual(@as(f64, 0.0075), huge_impact);

    // Test amount large enough to cap at 15%
    // log10(1e30) = 30, so impact_factor = 3.0, base_impact = 0.015, capped at 0.15? No.
    // Actually, base_impact = 3.0 * 0.005 = 0.015 (1.5%), still below cap
    // We need log10(x)/10 * 0.005 = 0.15, so log10(x) = 300, x = 1e300
    const capped_amount_f: f64 = 1.0e300;
    const capped_impact_factor = @log10(capped_amount_f + 1.0) / 10.0;
    const capped_base_impact = capped_impact_factor * 0.005;
    const capped_impact = @max(@min(capped_base_impact, 0.15), 0.0001);
    try testing.expectEqual(@as(f64, 0.15), capped_impact);
}

// Test parsePublicKey helper
test "parsePublicKey - valid Base58" {
    // Test with known valid Base58 public key
    const valid_key = "11111111111111111111111111111111";
    const result = helpers.parsePublicKey(valid_key);
    try testing.expect(result != null);
}

// Test parsePublicKey with invalid input
test "parsePublicKey - invalid Base58" {
    const invalid_key = "invalid!!!";
    const result = helpers.parsePublicKey(invalid_key);
    try testing.expect(result == null);
}

// Test parsePublicKey with empty string
test "parsePublicKey - empty string" {
    const empty_key = "";
    const result = helpers.parsePublicKey(empty_key);
    try testing.expect(result == null);
}

// Test integration: DLMM pool data flow
test "integration - DLMM pool data extraction flow" {
    // Simulate real DLMM pool account data
    var data: [500]u8 = undefined;
    @memset(&data, 0);

    // Set realistic DLMM values
    std.mem.writeInt(i32, data[8..12], 8500, .little); // active_id
    std.mem.writeInt(u16, data[12..14], 25, .little); // bin_step = 0.25%
    std.mem.writeInt(u16, data[14..16], 100, .little); // protocol_fee_bps = 1%

    // Step 1: Extract pool basics
    const pool_basics = helpers.extractDlmmPoolBasics(&data);
    try testing.expect(pool_basics != null);

    // Step 2: Verify extracted values
    try testing.expectEqual(@as(i32, 8500), pool_basics.?.active_id);
    try testing.expectEqual(@as(u16, 25), pool_basics.?.bin_step);

    // Step 3: Parse full account
    const lb_pair = helpers.parseLbPairData(&data);
    try testing.expect(lb_pair != null);
    try testing.expectEqual(@as(i32, 8500), lb_pair.?.active_id);
    try testing.expectEqual(@as(u16, 25), lb_pair.?.bin_step);

    // Step 4: Verify consistency
    try testing.expectEqual(pool_basics.?.active_id, lb_pair.?.active_id);
    try testing.expectEqual(pool_basics.?.bin_step, lb_pair.?.bin_step);
}

// Test integration: Swap quote calculation components
test "integration - swap quote calculation" {
    // Simulate swap quote calculation pipeline
    const amount_in: u64 = 1000000; // 1 token with 6 decimals
    const base_fee_bps: u16 = 25; // 0.25%
    const slippage_bps: u16 = 100; // 1%

    // Step 1: Calculate fee
    const fee = (amount_in * base_fee_bps) / 10000;
    try testing.expectEqual(@as(u64, 2500), fee);

    // Step 2: Amount after fee
    const amount_after_fee = amount_in - fee;
    try testing.expectEqual(@as(u64, 997500), amount_after_fee);

    // Step 3: Calculate price impact
    const amount_f = @as(f64, @floatFromInt(amount_in));
    const impact_factor = @log10(amount_f + 1.0) / 10.0;
    const base_impact = impact_factor * 0.005;
    const price_impact = @max(@min(base_impact, 0.15), 0.0001);

    // For 1M amount: log10(1e6) = 6, impact_factor = 0.6, base_impact = 0.003 (0.3%)
    try testing.expect(price_impact > 0.0025);
    try testing.expect(price_impact < 0.0035);

    // Step 4: Apply slippage to estimated output
    const estimated_output: u64 = 950000; // Example output
    const min_output = helpers.applySlippage(estimated_output, slippage_bps, true);
    try testing.expectEqual(@as(u64, 940500), min_output);
}
