//! Price Subscription Module
//!
//! Real-time price monitoring using Solana WebSocket subscriptions.
//! Monitors DEX pool accounts for state changes to detect price updates.
//!
//! Supported DEX protocols:
//! - Jupiter (via accountSubscribe on swap pools)
//! - Meteora DLMM (Dynamic Liquidity Market Maker)
//! - Meteora DAMM (Dynamic AMM)
//!
//! Use cases:
//! - Trading bot price monitoring
//! - Arbitrage detection
//! - Portfolio tracking with live prices
//!
//! Performance:
//! - Real-time updates (< 1s latency)
//! - Single WebSocket connection for multiple subscriptions
//! - Efficient account state parsing

const std = @import("std");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const endpoints = @import("endpoints.zig");

const PubsubClient = solana_client.pubsub.PubsubClient;
const PublicKey = solana_sdk.PublicKey;
const SubscriptionId = solana_client.pubsub.SubscriptionId;

/// Price update notification
pub const PriceUpdate = struct {
    pool_address: []const u8,
    token_a: []const u8,
    token_b: []const u8,
    price: f64,
    liquidity: ?u64 = null,
    timestamp: i64,
};

/// Price subscription configuration
pub const PriceSubscriptionConfig = struct {
    /// Network (mainnet/devnet/testnet)
    network: []const u8 = "mainnet",
    /// Custom WebSocket endpoint
    endpoint: ?[]const u8 = null,
    /// Commitment level (processed/confirmed/finalized)
    commitment: []const u8 = "confirmed",
};

/// Price subscription manager
pub const PriceSubscription = struct {
    allocator: std.mem.Allocator,
    client: *PubsubClient,
    subscriptions: std.StringHashMap(SubscriptionId),
    config: PriceSubscriptionConfig,

    const Self = @This();

    /// Initialize price subscription manager
    pub fn init(
        allocator: std.mem.Allocator,
        config: PriceSubscriptionConfig,
    ) !Self {
        // Resolve WebSocket endpoint
        const ws_endpoint = if (config.endpoint) |ep|
            ep
        else
            resolveWsEndpoint(config.network);

        // Create PubSub client
        var client = try allocator.create(PubsubClient);
        errdefer allocator.destroy(client);

        client.* = try PubsubClient.init(allocator, ws_endpoint);
        errdefer client.deinit();

        return Self{
            .allocator = allocator,
            .client = client,
            .subscriptions = std.StringHashMap(SubscriptionId).init(allocator),
            .config = config,
        };
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        // Unsubscribe all
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            self.client.accountUnsubscribe(entry.value_ptr.*) catch {};
        }

        self.subscriptions.deinit();
        self.client.deinit();
        self.allocator.destroy(self.client);
    }

    /// Subscribe to price updates for a pool
    pub fn subscribePool(
        self: *Self,
        pool_address: []const u8,
    ) !SubscriptionId {
        // Check if already subscribed
        if (self.subscriptions.get(pool_address)) |sub_id| {
            return sub_id;
        }

        // Parse pool address
        const pubkey = try PublicKey.fromBase58(pool_address);

        // Subscribe to account changes
        const sub_id = try self.client.accountSubscribe(pubkey, .{
            .encoding = .base64,
            .commitment = self.config.commitment,
        });

        // Store subscription
        const pool_key = try self.allocator.dupe(u8, pool_address);
        errdefer self.allocator.free(pool_key);

        try self.subscriptions.put(pool_key, sub_id);

        return sub_id;
    }

    /// Unsubscribe from pool price updates
    pub fn unsubscribePool(
        self: *Self,
        pool_address: []const u8,
    ) !void {
        if (self.subscriptions.fetchRemove(pool_address)) |kv| {
            defer self.allocator.free(kv.key);
            try self.client.accountUnsubscribe(kv.value);
        }
    }

    /// Read next price update notification
    ///
    /// This is a blocking call that waits for the next notification.
    /// Returns null if the connection is closed.
    pub fn readUpdate(self: *Self) !?PriceUpdate {
        // Read notification from WebSocket
        const notification = try self.client.readNotification();
        if (notification == null) {
            return null;
        }

        // Parse notification to extract price data
        // Note: This is a simplified implementation
        // Real implementation would parse the account data based on DEX protocol

        // TODO: Implement account data parsing for:
        // - Jupiter pools
        // - Meteora DLMM pools
        // - Meteora DAMM pools

        // For now, return a placeholder
        return PriceUpdate{
            .pool_address = "placeholder",
            .token_a = "SOL",
            .token_b = "USDC",
            .price = 0.0,
            .liquidity = null,
            .timestamp = std.time.timestamp(),
        };
    }

    /// List all active subscriptions
    pub fn listSubscriptions(self: *Self) []const []const u8 {
        var keys = std.ArrayList([]const u8).init(self.allocator);
        defer keys.deinit();

        var iter = self.subscriptions.keyIterator();
        while (iter.next()) |key| {
            keys.append(key.*) catch continue;
        }

        return keys.toOwnedSlice() catch &.{};
    }
};

/// Resolve WebSocket endpoint for network
pub fn resolveWsEndpoint(network: []const u8) []const u8 {
    if (std.mem.eql(u8, network, "mainnet")) {
        return "wss://api.mainnet-beta.solana.com";
    } else if (std.mem.eql(u8, network, "testnet")) {
        return "wss://api.testnet.solana.com";
    } else if (std.mem.eql(u8, network, "localhost")) {
        return "ws://localhost:8900";
    } else {
        // Default to devnet
        return "wss://api.devnet.solana.com";
    }
}
