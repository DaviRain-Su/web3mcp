//! EVM Gas Price Tracker and Predictor
//!
//! Tracks historical gas prices and provides predictions based on trends.

const std = @import("std");
const gas_oracle = @import("./gas_oracle.zig");
const rpc_client = @import("./rpc_client.zig");

const GasPrice = gas_oracle.GasPrice;
const GasTier = gas_oracle.GasTier;
const EvmRpcClient = rpc_client.EvmRpcClient;

/// Historical gas price entry
pub const GasPriceEntry = struct {
    /// Timestamp when this price was recorded
    timestamp: i64,

    /// Block number
    block_number: u64,

    /// Gas price for slow tier (wei)
    slow: u64,

    /// Gas price for standard tier (wei)
    standard: u64,

    /// Gas price for fast tier (wei)
    fast: u64,

    /// Base fee per gas (EIP-1559 chains only)
    base_fee: ?u64 = null,
};

/// Gas price statistics
pub const GasStatistics = struct {
    /// Average gas price over period
    average: u64,

    /// Median gas price
    median: u64,

    /// Minimum gas price seen
    min: u64,

    /// Maximum gas price seen
    max: u64,

    /// Standard deviation
    std_dev: u64,

    /// 25th percentile
    p25: u64,

    /// 75th percentile
    p75: u64,

    /// 95th percentile (for outlier detection)
    p95: u64,
};

/// Gas price trend
pub const GasTrend = enum {
    rising, // Prices increasing
    falling, // Prices decreasing
    stable, // Prices relatively constant
    high_variance, // High variance, unpredictable
};

/// Gas price prediction
pub const GasPrediction = struct {
    /// Predicted price for next block
    next_block: u64,

    /// Predicted price in 1 minute
    in_1_min: u64,

    /// Predicted price in 5 minutes
    in_5_min: u64,

    /// Predicted price in 15 minutes
    in_15_min: u64,

    /// Confidence level (0-100)
    confidence: u8,

    /// Current trend
    trend: GasTrend,
};

/// Gas price tracker
pub const GasTracker = struct {
    allocator: std.mem.Allocator,
    rpc_client: *EvmRpcClient,

    /// Historical entries (circular buffer)
    history: std.ArrayList(GasPriceEntry),

    /// Maximum history size
    max_history: usize = 1000,

    /// Average block time in seconds
    block_time_seconds: u64 = 12,

    /// Initialize gas tracker
    pub fn init(
        allocator: std.mem.Allocator,
        client: *EvmRpcClient,
        block_time: u64,
    ) GasTracker {
        return .{
            .allocator = allocator,
            .rpc_client = client,
            .history = std.ArrayList(GasPriceEntry).init(allocator),
            .block_time_seconds = block_time,
        };
    }

    /// Clean up
    pub fn deinit(self: *GasTracker) void {
        self.history.deinit();
    }

    /// Record current gas prices
    pub fn recordCurrentPrice(self: *GasTracker) !void {
        // Get current block number
        const block_hex = try self.rpc_client.ethBlockNumber();
        defer self.allocator.free(block_hex);

        const block_number = try parseHexU64(block_hex);

        // Get current gas price
        const gas_price_hex = try self.rpc_client.ethGasPrice();
        defer self.allocator.free(gas_price_hex);

        const current_price = try parseHexU64(gas_price_hex);

        // Get current block for base fee
        const block = try self.rpc_client.ethGetBlockByNumber(block_number, false);
        var base_fee: ?u64 = null;

        if (block) |b| {
            defer b.deinit(self.allocator);
            if (b.baseFeePerGas) |bf| {
                base_fee = try parseHexU64(bf);
            }
        }

        // Calculate tier prices
        const slow = (current_price * 9) / 10; // 0.9x
        const standard = current_price; // 1.0x
        const fast = (current_price * 12) / 10; // 1.2x

        // Create entry
        const entry = GasPriceEntry{
            .timestamp = std.time.timestamp(),
            .block_number = block_number,
            .slow = slow,
            .standard = standard,
            .fast = fast,
            .base_fee = base_fee,
        };

        // Add to history
        try self.history.append(entry);

        // Limit history size
        if (self.history.items.len > self.max_history) {
            _ = self.history.orderedRemove(0);
        }
    }

    /// Get statistics for a specific tier
    pub fn getStatistics(self: *GasTracker, tier: GasTier) !GasStatistics {
        if (self.history.items.len == 0) {
            return error.NoHistoryData;
        }

        // Extract prices for this tier
        var prices = try self.allocator.alloc(u64, self.history.items.len);
        defer self.allocator.free(prices);

        for (self.history.items, 0..) |entry, i| {
            prices[i] = switch (tier) {
                .slow => entry.slow,
                .standard => entry.standard,
                .fast => entry.fast,
            };
        }

        // Sort for percentile calculations
        std.mem.sort(u64, prices, {}, comptime std.sort.asc(u64));

        // Calculate statistics
        const average = calculateAverage(prices);
        const median = prices[prices.len / 2];
        const min = prices[0];
        const max = prices[prices.len - 1];
        const std_dev = calculateStdDev(prices, average);

        const p25_idx = prices.len / 4;
        const p75_idx = (prices.len * 3) / 4;
        const p95_idx = (prices.len * 95) / 100;

        return GasStatistics{
            .average = average,
            .median = median,
            .min = min,
            .max = max,
            .std_dev = std_dev,
            .p25 = prices[p25_idx],
            .p75 = prices[p75_idx],
            .p95 = prices[p95_idx],
        };
    }

    /// Predict future gas prices
    pub fn predictPrice(self: *GasTracker, tier: GasTier) !GasPrediction {
        if (self.history.items.len < 10) {
            return error.InsufficientHistory;
        }

        // Get recent entries (last 20 blocks or 10 minutes)
        const recent_count = @min(20, self.history.items.len);
        const recent_start = self.history.items.len - recent_count;

        // Calculate trend
        const trend = try self.calculateTrend(tier, recent_start);

        // Get current price
        const current = self.history.items[self.history.items.len - 1];
        const current_price = switch (tier) {
            .slow => current.slow,
            .standard => current.standard,
            .fast => current.fast,
        };

        // Simple linear prediction based on trend
        const trend_factor: f64 = switch (trend) {
            .rising => 1.05, // +5% per prediction period
            .falling => 0.95, // -5% per prediction period
            .stable => 1.00, // No change
            .high_variance => 1.02, // Slight increase (cautious)
        };

        const next_block = @as(u64, @intFromFloat(@as(f64, @floatFromInt(current_price)) * trend_factor));

        // Blocks per minute = 60 / block_time
        const blocks_per_min = 60 / self.block_time_seconds;

        const in_1_min = @as(u64, @intFromFloat(@as(f64, @floatFromInt(current_price)) * std.math.pow(f64, trend_factor, @floatFromInt(blocks_per_min))));
        const in_5_min = @as(u64, @intFromFloat(@as(f64, @floatFromInt(current_price)) * std.math.pow(f64, trend_factor, @floatFromInt(blocks_per_min * 5))));
        const in_15_min = @as(u64, @intFromFloat(@as(f64, @floatFromInt(current_price)) * std.math.pow(f64, trend_factor, @floatFromInt(blocks_per_min * 15))));

        // Confidence based on data consistency
        const confidence: u8 = switch (trend) {
            .stable => 90,
            .rising, .falling => 75,
            .high_variance => 50,
        };

        return GasPrediction{
            .next_block = next_block,
            .in_1_min = in_1_min,
            .in_5_min = in_5_min,
            .in_15_min = in_15_min,
            .confidence = confidence,
            .trend = trend,
        };
    }

    /// Calculate trend from recent history
    fn calculateTrend(self: *GasTracker, tier: GasTier, start_idx: usize) !GasTrend {
        const entries = self.history.items[start_idx..];

        if (entries.len < 5) {
            return .stable;
        }

        // Get prices
        var prices = try self.allocator.alloc(u64, entries.len);
        defer self.allocator.free(prices);

        for (entries, 0..) |entry, i| {
            prices[i] = switch (tier) {
                .slow => entry.slow,
                .standard => entry.standard,
                .fast => entry.fast,
            };
        }

        // Calculate variance
        const avg = calculateAverage(prices);
        const std_dev = calculateStdDev(prices, avg);

        // High variance = high_variance
        const variance_ratio = (@as(f64, @floatFromInt(std_dev)) / @as(f64, @floatFromInt(avg))) * 100.0;
        if (variance_ratio > 20.0) {
            return .high_variance;
        }

        // Compare first half vs second half
        const mid = prices.len / 2;
        const first_half_avg = calculateAverage(prices[0..mid]);
        const second_half_avg = calculateAverage(prices[mid..]);

        const change_percent = (@as(f64, @floatFromInt(second_half_avg)) / @as(f64, @floatFromInt(first_half_avg)) - 1.0) * 100.0;

        if (change_percent > 5.0) {
            return .rising;
        } else if (change_percent < -5.0) {
            return .falling;
        } else {
            return .stable;
        }
    }

    /// Get best time to transact in next N minutes
    pub fn getBestTimeWindow(self: *GasTracker, tier: GasTier, window_minutes: u64) !struct { minute: u64, price: u64 } {
        const prediction = try self.predictPrice(tier);

        // Check predictions at different time points
        const times = [_]struct { minute: u64, price: u64 }{
            .{ .minute = 0, .price = prediction.next_block },
            .{ .minute = 1, .price = prediction.in_1_min },
            .{ .minute = 5, .price = prediction.in_5_min },
            .{ .minute = 15, .price = prediction.in_15_min },
        };

        var best = times[0];
        for (times) |t| {
            if (t.minute <= window_minutes and t.price < best.price) {
                best = t;
            }
        }

        return best;
    }
};

/// Calculate average of u64 array
fn calculateAverage(values: []const u64) u64 {
    if (values.len == 0) return 0;

    var sum: u128 = 0;
    for (values) |v| {
        sum += v;
    }

    return @intCast(sum / values.len);
}

/// Calculate standard deviation
fn calculateStdDev(values: []const u64, mean: u64) u64 {
    if (values.len == 0) return 0;

    var sum_sq_diff: u128 = 0;
    for (values) |v| {
        const diff: i128 = @as(i128, @intCast(v)) - @as(i128, @intCast(mean));
        sum_sq_diff += @as(u128, @intCast(diff * diff));
    }

    const variance = sum_sq_diff / values.len;
    return @intFromFloat(@sqrt(@as(f64, @floatFromInt(variance))));
}

/// Parse hex string to u64
fn parseHexU64(hex: []const u8) !u64 {
    if (hex.len < 2 or hex[0] != '0' or hex[1] != 'x') {
        return error.InvalidHexFormat;
    }

    const hex_part = hex[2..];
    return try std.fmt.parseInt(u64, hex_part, 16);
}

// Tests
const testing = std.testing;

test "GasPriceEntry structure" {
    const entry = GasPriceEntry{
        .timestamp = 1234567890,
        .block_number = 1000,
        .slow = 10_000_000_000, // 10 gwei
        .standard = 15_000_000_000, // 15 gwei
        .fast = 20_000_000_000, // 20 gwei
        .base_fee = 12_000_000_000,
    };

    try testing.expectEqual(@as(i64, 1234567890), entry.timestamp);
    try testing.expectEqual(@as(u64, 1000), entry.block_number);
    try testing.expectEqual(@as(u64, 10_000_000_000), entry.slow);
}

test "calculateAverage" {
    const values = [_]u64{ 10, 20, 30, 40, 50 };
    const avg = calculateAverage(&values);

    try testing.expectEqual(@as(u64, 30), avg);
}

test "calculateStdDev" {
    const values = [_]u64{ 10, 20, 30, 40, 50 };
    const avg = calculateAverage(&values);
    const std_dev = calculateStdDev(&values, avg);

    // Standard deviation should be around 14-15
    try testing.expect(std_dev >= 14 and std_dev <= 16);
}

test "GasTracker initialization" {
    const allocator = testing.allocator;

    var dummy_ptr: usize = 0;
    const client_ptr: *EvmRpcClient = @ptrFromInt(@intFromPtr(&dummy_ptr));

    var tracker = GasTracker.init(allocator, client_ptr, 12);
    defer tracker.deinit();

    try testing.expectEqual(@as(usize, 0), tracker.history.items.len);
    try testing.expectEqual(@as(u64, 12), tracker.block_time_seconds);
}
