//! Unit tests for arbitrage detector

const std = @import("std");
const testing = std.testing;
const arbitrage = @import("arbitrage_detector.zig");

test "arbitrage_detector module loads" {
    _ = arbitrage;
}

test "DexId fromString and toString" {
    const jupiter = arbitrage.DexId.fromString("jupiter");
    try testing.expect(jupiter.? == .jupiter);
    try testing.expectEqualStrings("jupiter", jupiter.?.toString());

    const meteora = arbitrage.DexId.fromString("meteora_dlmm");
    try testing.expect(meteora.? == .meteora_dlmm);
    try testing.expectEqualStrings("meteora_dlmm", meteora.?.toString());

    const invalid = arbitrage.DexId.fromString("invalid");
    try testing.expect(invalid == null);
}

test "ArbitrageDetector init and deinit" {
    const allocator = testing.allocator;

    const config = arbitrage.ArbitrageConfig{
        .min_profit_pct = 0.5,
        .max_slippage_bps = 50,
    };

    var detector = arbitrage.ArbitrageDetector.init(allocator, config);
    defer detector.deinit();

    try testing.expect(detector.config.min_profit_pct == 0.5);
    try testing.expect(detector.config.max_slippage_bps == 50);
}

test "detectOpportunities with no quotes" {
    const allocator = testing.allocator;

    const config = arbitrage.ArbitrageConfig{};
    var detector = arbitrage.ArbitrageDetector.init(allocator, config);
    defer detector.deinit();

    const quotes: []const arbitrage.DexQuote = &.{};
    const opportunities = try detector.detectOpportunities(quotes);
    defer allocator.free(opportunities);

    try testing.expect(opportunities.len == 0);
}

test "detectOpportunities with single quote" {
    const allocator = testing.allocator;

    const config = arbitrage.ArbitrageConfig{};
    var detector = arbitrage.ArbitrageDetector.init(allocator, config);
    defer detector.deinit();

    const quotes = [_]arbitrage.DexQuote{
        .{
            .dex = .jupiter,
            .input_mint = "SOL",
            .output_mint = "USDC",
            .input_amount = 1_000_000_000, // 1 SOL
            .output_amount = 100_000_000, // 100 USDC
            .price = 100.0,
            .fee_bps = 25, // 0.25%
            .slippage_bps = 10, // 0.1%
        },
    };

    const opportunities = try detector.detectOpportunities(&quotes);
    defer allocator.free(opportunities);

    // Need at least 2 quotes
    try testing.expect(opportunities.len == 0);
}

test "detectOpportunities with profitable arbitrage" {
    const allocator = testing.allocator;

    const config = arbitrage.ArbitrageConfig{
        .min_profit_pct = 0.1, // 0.1% minimum
        .include_gas_cost = false, // Simplify test
    };
    var detector = arbitrage.ArbitrageDetector.init(allocator, config);
    defer detector.deinit();

    const quotes = [_]arbitrage.DexQuote{
        // DEX A: Lower price (buy here)
        .{
            .dex = .jupiter,
            .input_mint = "SOL",
            .output_mint = "USDC",
            .input_amount = 1_000_000_000, // 1 SOL
            .output_amount = 100_000_000, // 100 USDC
            .price = 100.0,
            .fee_bps = 25, // 0.25%
            .slippage_bps = 10,
        },
        // DEX B: Higher price (sell here)
        .{
            .dex = .meteora_dlmm,
            .input_mint = "SOL",
            .output_mint = "USDC",
            .input_amount = 1_000_000_000, // 1 SOL
            .output_amount = 102_000_000, // 102 USDC (2% higher)
            .price = 102.0,
            .fee_bps = 30, // 0.3%
            .slippage_bps = 15,
        },
    };

    const opportunities = try detector.detectOpportunities(&quotes);
    defer allocator.free(opportunities);

    // Should find at least one opportunity
    try testing.expect(opportunities.len > 0);

    const opp = opportunities[0];
    try testing.expect(opp.buy_dex == .jupiter);
    try testing.expect(opp.sell_dex == .meteora_dlmm);
    try testing.expect(opp.net_profit > 0);
    try testing.expect(opp.profit_percentage > config.min_profit_pct);
}

test "detectOpportunities filters low profit" {
    const allocator = testing.allocator;

    const config = arbitrage.ArbitrageConfig{
        .min_profit_pct = 5.0, // 5% minimum (very high)
        .include_gas_cost = false,
    };
    var detector = arbitrage.ArbitrageDetector.init(allocator, config);
    defer detector.deinit();

    const quotes = [_]arbitrage.DexQuote{
        .{
            .dex = .jupiter,
            .input_mint = "SOL",
            .output_mint = "USDC",
            .input_amount = 1_000_000_000,
            .output_amount = 100_000_000,
            .price = 100.0,
            .fee_bps = 25,
            .slippage_bps = 10,
        },
        .{
            .dex = .meteora_dlmm,
            .input_mint = "SOL",
            .output_mint = "USDC",
            .input_amount = 1_000_000_000,
            .output_amount = 101_000_000, // Only 1% difference
            .price = 101.0,
            .fee_bps = 30,
            .slippage_bps = 15,
        },
    };

    const opportunities = try detector.detectOpportunities(&quotes);
    defer allocator.free(opportunities);

    // Should filter out low-profit opportunities
    try testing.expect(opportunities.len == 0);
}
