//! EVM Gas Oracle
//!
//! Provides optimized gas price estimation with:
//! - EIP-1559 support (baseFee + priorityFee)
//! - Multiple fee tiers (slow, standard, fast)
//! - Caching to reduce RPC calls
//! - Automatic safety margins

const std = @import("std");
const rpc_client = @import("./rpc_client.zig");

/// Gas price tier
pub const GasTier = enum {
    slow, // Low priority, cheaper
    standard, // Normal priority, recommended
    fast, // High priority, more expensive
};

/// Gas price recommendation (EIP-1559)
pub const GasPriceEIP1559 = struct {
    /// Base fee per gas (from block)
    base_fee_per_gas: u64,

    /// Max priority fee per gas (tip to miner)
    max_priority_fee_per_gas: u64,

    /// Max fee per gas (base + priority)
    max_fee_per_gas: u64,

    /// Estimated total cost in wei (gas_limit * max_fee_per_gas)
    estimated_cost: ?u64 = null,
};

/// Legacy gas price (pre-EIP-1559)
pub const GasPriceLegacy = struct {
    /// Gas price in wei
    gas_price: u64,

    /// Estimated total cost in wei (gas_limit * gas_price)
    estimated_cost: ?u64 = null,
};

/// Gas price recommendation
pub const GasPrice = union(enum) {
    eip1559: GasPriceEIP1559,
    legacy: GasPriceLegacy,
};

/// Gas estimation result with safety margin
pub const GasEstimate = struct {
    /// Estimated gas units (from eth_estimateGas)
    base_estimate: u64,

    /// Recommended gas limit (base + safety margin)
    recommended_limit: u64,

    /// Safety margin percentage (e.g., 20 = 20% extra)
    safety_margin_percent: u8,
};

/// Cached gas price data
const GasPriceCache = struct {
    slow: GasPrice,
    standard: GasPrice,
    fast: GasPrice,
    timestamp: i64, // Unix timestamp
    block_number: u64,
};

/// Gas Oracle for optimized gas price estimation
pub const GasOracle = struct {
    allocator: std.mem.Allocator,
    rpc_client: *rpc_client.EvmRpcClient,
    cache: ?GasPriceCache = null,
    cache_ttl_seconds: i64 = 12, // Default 12s (1 Ethereum block)
    default_safety_margin: u8 = 20, // Default 20% safety margin

    /// Initialize gas oracle
    pub fn init(
        allocator: std.mem.Allocator,
        client: *rpc_client.EvmRpcClient,
    ) GasOracle {
        return .{
            .allocator = allocator,
            .rpc_client = client,
        };
    }

    /// Get gas price recommendation for a specific tier
    pub fn getGasPrice(self: *GasOracle, tier: GasTier) !GasPrice {
        // Check cache
        if (self.cache) |cached| {
            const now = std.time.timestamp();
            if (now - cached.timestamp < self.cache_ttl_seconds) {
                // Cache is still valid
                return switch (tier) {
                    .slow => cached.slow,
                    .standard => cached.standard,
                    .fast => cached.fast,
                };
            }
        }

        // Cache expired or not exists, fetch new data
        try self.refreshCache();

        if (self.cache) |cached| {
            return switch (tier) {
                .slow => cached.slow,
                .standard => cached.standard,
                .fast => cached.fast,
            };
        }

        return error.CacheRefreshFailed;
    }

    /// Estimate gas for a transaction with safety margin
    pub fn estimateGas(
        self: *GasOracle,
        transaction: rpc_client.TransactionRequest,
        safety_margin: ?u8,
    ) !GasEstimate {
        const base_estimate = try self.rpc_client.ethEstimateGas(transaction);

        const margin = safety_margin orelse self.default_safety_margin;
        const margin_amount = (base_estimate * margin) / 100;
        const recommended_limit = base_estimate + margin_amount;

        return GasEstimate{
            .base_estimate = base_estimate,
            .recommended_limit = recommended_limit,
            .safety_margin_percent = margin,
        };
    }

    /// Get complete gas recommendation (price + estimate)
    pub fn getGasRecommendation(
        self: *GasOracle,
        transaction: rpc_client.TransactionRequest,
        tier: GasTier,
        safety_margin: ?u8,
    ) !struct { estimate: GasEstimate, price: GasPrice } {
        const estimate = try self.estimateGas(transaction, safety_margin);
        var price = try self.getGasPrice(tier);

        // Calculate estimated cost
        switch (price) {
            .eip1559 => |*eip| {
                eip.estimated_cost = estimate.recommended_limit * eip.max_fee_per_gas;
            },
            .legacy => |*leg| {
                leg.estimated_cost = estimate.recommended_limit * leg.gas_price;
            },
        }

        return .{ .estimate = estimate, .price = price };
    }

    /// Refresh gas price cache
    fn refreshCache(self: *GasOracle) !void {
        // Get latest block to check for EIP-1559 support
        const latest_block = try self.rpc_client.ethGetBlockByNumber(
            try self.getCurrentBlockNumber(),
            false,
        );

        if (latest_block == null) {
            return error.FailedToFetchBlock;
        }

        const block = latest_block.?;
        defer block.deinit(self.allocator);

        const now = std.time.timestamp();

        // Check if chain supports EIP-1559 (has baseFeePerGas)
        if (block.baseFeePerGas) |base_fee_hex| {
            // EIP-1559 supported
            const base_fee = try parseHexU64(base_fee_hex);

            // Calculate priority fees for different tiers
            // Slow: 1 gwei, Standard: 2 gwei, Fast: 3 gwei
            const slow_priority: u64 = 1_000_000_000; // 1 gwei
            const standard_priority: u64 = 2_000_000_000; // 2 gwei
            const fast_priority: u64 = 3_000_000_000; // 3 gwei

            self.cache = GasPriceCache{
                .slow = .{
                    .eip1559 = .{
                        .base_fee_per_gas = base_fee,
                        .max_priority_fee_per_gas = slow_priority,
                        .max_fee_per_gas = base_fee + slow_priority,
                    },
                },
                .standard = .{
                    .eip1559 = .{
                        .base_fee_per_gas = base_fee,
                        .max_priority_fee_per_gas = standard_priority,
                        .max_fee_per_gas = base_fee + standard_priority,
                    },
                },
                .fast = .{
                    .eip1559 = .{
                        .base_fee_per_gas = base_fee,
                        .max_priority_fee_per_gas = fast_priority,
                        .max_fee_per_gas = base_fee + fast_priority,
                    },
                },
                .timestamp = now,
                .block_number = block.number,
            };
        } else {
            // Legacy gas pricing
            const base_gas_price = try self.rpc_client.ethGasPrice();
            defer self.allocator.free(base_gas_price);

            const gas_price_wei = try parseHexU64(base_gas_price);

            // Apply multipliers for different tiers
            // Slow: 0.9x, Standard: 1.0x, Fast: 1.2x
            const slow_price = (gas_price_wei * 9) / 10;
            const standard_price = gas_price_wei;
            const fast_price = (gas_price_wei * 12) / 10;

            self.cache = GasPriceCache{
                .slow = .{ .legacy = .{ .gas_price = slow_price } },
                .standard = .{ .legacy = .{ .gas_price = standard_price } },
                .fast = .{ .legacy = .{ .gas_price = fast_price } },
                .timestamp = now,
                .block_number = block.number,
            };
        }
    }

    /// Get current block number
    fn getCurrentBlockNumber(self: *GasOracle) !u64 {
        const block_hex = try self.rpc_client.ethBlockNumber();
        defer self.allocator.free(block_hex);
        return try parseHexU64(block_hex);
    }

    /// Parse hex string to u64
    fn parseHexU64(hex: []const u8) !u64 {
        if (hex.len < 2 or hex[0] != '0' or hex[1] != 'x') {
            return error.InvalidHexFormat;
        }

        const hex_part = hex[2..];
        return try std.fmt.parseInt(u64, hex_part, 16);
    }
};

// Tests
const testing = std.testing;

test "GasEstimate with safety margin" {
    const base = 21000;
    const margin: u8 = 20; // 20%
    const expected = 21000 + (21000 * 20 / 100); // 25200

    const estimate = GasEstimate{
        .base_estimate = base,
        .recommended_limit = expected,
        .safety_margin_percent = margin,
    };

    try testing.expectEqual(@as(u64, 21000), estimate.base_estimate);
    try testing.expectEqual(@as(u64, 25200), estimate.recommended_limit);
    try testing.expectEqual(@as(u8, 20), estimate.safety_margin_percent);
}

test "EIP-1559 gas price calculation" {
    const base_fee: u64 = 30_000_000_000; // 30 gwei
    const priority_fee: u64 = 2_000_000_000; // 2 gwei
    const max_fee = base_fee + priority_fee;

    const price = GasPriceEIP1559{
        .base_fee_per_gas = base_fee,
        .max_priority_fee_per_gas = priority_fee,
        .max_fee_per_gas = max_fee,
    };

    try testing.expectEqual(@as(u64, 30_000_000_000), price.base_fee_per_gas);
    try testing.expectEqual(@as(u64, 2_000_000_000), price.max_priority_fee_per_gas);
    try testing.expectEqual(@as(u64, 32_000_000_000), price.max_fee_per_gas);
}

test "Legacy gas price calculation" {
    const gas_price: u64 = 20_000_000_000; // 20 gwei
    const gas_limit: u64 = 21000;
    const expected_cost = gas_price * gas_limit;

    const price = GasPriceLegacy{
        .gas_price = gas_price,
        .estimated_cost = expected_cost,
    };

    try testing.expectEqual(@as(u64, 20_000_000_000), price.gas_price);
    try testing.expectEqual(@as(u64, 420_000_000_000_000), price.estimated_cost.?);
}
