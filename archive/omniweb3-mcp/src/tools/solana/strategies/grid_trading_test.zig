//! Unit tests for grid trading strategy
//!
//! Tests cover:
//! - Module compilation
//! - Grid strategy enum
//! - Basic parameter validation

const std = @import("std");
const testing = std.testing;
const grid_trading = @import("grid_trading.zig");

test "grid_trading module loads" {
    // Basic smoke test to ensure module compiles
    _ = grid_trading;
}

test "grid_trading exports handle function" {
    // Verify the handle function exists
    _ = grid_trading.handle;
}

test "GridStrategy fromString - arithmetic" {
    const strategy = grid_trading.GridStrategy.fromString("arithmetic");
    try testing.expectEqual(grid_trading.GridStrategy.arithmetic, strategy.?);
}

test "GridStrategy fromString - geometric" {
    const strategy = grid_trading.GridStrategy.fromString("geometric");
    try testing.expectEqual(grid_trading.GridStrategy.geometric, strategy.?);
}

test "GridStrategy fromString - invalid" {
    const strategy = grid_trading.GridStrategy.fromString("invalid");
    try testing.expectEqual(@as(?grid_trading.GridStrategy, null), strategy);
}

// Note: Full integration tests would require:
// 1. Valid wallet configuration
// 2. Network connectivity to Jupiter API
// 3. Funded wallet for actual orders
// 4. Market data for current price
// These are better suited for integration tests rather than unit tests.
