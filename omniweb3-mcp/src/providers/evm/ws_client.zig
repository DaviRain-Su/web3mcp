//! EVM WebSocket Client
//!
//! Provides real-time event subscriptions for EVM chains:
//! - New blocks
//! - Pending transactions
//! - Event logs
//! - Automatic reconnection
//! - Subscription management

const std = @import("std");

/// Subscription type
pub const SubscriptionType = enum {
    /// New block headers
    new_heads,
    /// Pending transactions
    pending_transactions,
    /// Event logs with filter
    logs,
    /// New pending transactions (full)
    new_pending_transactions,
    /// Syncing status
    syncing,
};

/// Subscription filter for logs
pub const LogFilter = struct {
    /// Contract address (optional)
    address: ?[]const u8 = null,

    /// Event topics (optional)
    topics: ?[][]const u8 = null,

    /// From block (optional)
    from_block: ?[]const u8 = null,

    /// To block (optional)
    to_block: ?[]const u8 = null,
};

/// Subscription ID
pub const SubscriptionId = []const u8;

/// WebSocket connection state
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
    closed,
};

/// Block header from subscription
pub const BlockHeader = struct {
    /// Block number
    number: []const u8,

    /// Block hash
    hash: []const u8,

    /// Parent hash
    parent_hash: []const u8,

    /// Timestamp
    timestamp: []const u8,

    /// Miner/coinbase
    miner: []const u8,

    /// Base fee per gas (EIP-1559)
    base_fee_per_gas: ?[]const u8 = null,

    /// Gas limit
    gas_limit: []const u8,

    /// Gas used
    gas_used: []const u8,

    /// Free allocated memory
    pub fn deinit(self: BlockHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.number);
        allocator.free(self.hash);
        allocator.free(self.parent_hash);
        allocator.free(self.timestamp);
        allocator.free(self.miner);
        if (self.base_fee_per_gas) |fee| allocator.free(fee);
        allocator.free(self.gas_limit);
        allocator.free(self.gas_used);
    }
};

/// Event log from subscription
pub const EventLog = struct {
    /// Log address
    address: []const u8,

    /// Topics
    topics: [][]const u8,

    /// Data
    data: []const u8,

    /// Block number
    block_number: []const u8,

    /// Transaction hash
    transaction_hash: []const u8,

    /// Transaction index
    transaction_index: []const u8,

    /// Block hash
    block_hash: []const u8,

    /// Log index
    log_index: []const u8,

    /// Removed flag
    removed: bool = false,

    /// Free allocated memory
    pub fn deinit(self: EventLog, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
        for (self.topics) |topic| {
            allocator.free(topic);
        }
        allocator.free(self.topics);
        allocator.free(self.data);
        allocator.free(self.block_number);
        allocator.free(self.transaction_hash);
        allocator.free(self.transaction_index);
        allocator.free(self.block_hash);
        allocator.free(self.log_index);
    }
};

/// Subscription event
pub const SubscriptionEvent = union(enum) {
    new_block: BlockHeader,
    pending_tx: []const u8,
    log: EventLog,
    error_msg: []const u8,

    /// Free allocated memory
    pub fn deinit(self: SubscriptionEvent, allocator: std.mem.Allocator) void {
        switch (self) {
            .new_block => |block| block.deinit(allocator),
            .pending_tx => |tx| allocator.free(tx),
            .log => |log| log.deinit(allocator),
            .error_msg => |msg| allocator.free(msg),
        }
    }
};

/// Event callback function type
pub const EventCallback = *const fn (
    subscription_id: SubscriptionId,
    event: SubscriptionEvent,
    user_data: ?*anyopaque,
) void;

/// Subscription handle
pub const Subscription = struct {
    /// Subscription ID from server
    id: SubscriptionId,

    /// Subscription type
    sub_type: SubscriptionType,

    /// Event callback
    callback: EventCallback,

    /// User data passed to callback
    user_data: ?*anyopaque = null,

    /// Active flag
    active: bool = true,
};

/// WebSocket client for EVM chains
pub const WsClient = struct {
    allocator: std.mem.Allocator,

    /// WebSocket URL
    ws_url: []const u8,

    /// Connection state
    state: ConnectionState = .disconnected,

    /// Active subscriptions
    subscriptions: std.StringHashMap(Subscription),

    /// Request ID counter
    request_id: u64 = 1,

    /// Auto-reconnect flag
    auto_reconnect: bool = true,

    /// Reconnect delay (milliseconds)
    reconnect_delay_ms: u64 = 5000,

    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},

    /// Initialize WebSocket client
    pub fn init(
        allocator: std.mem.Allocator,
        ws_url: []const u8,
    ) !*WsClient {
        const self = try allocator.create(WsClient);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .ws_url = try allocator.dupe(u8, ws_url),
            .subscriptions = std.StringHashMap(Subscription).init(allocator),
        };

        return self;
    }

    /// Clean up
    pub fn deinit(self: *WsClient) void {
        // Close all subscriptions
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.subscriptions.deinit();

        self.allocator.free(self.ws_url);
        self.allocator.destroy(self);
    }

    /// Connect to WebSocket server
    pub fn connect(self: *WsClient) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state == .connected) {
            return; // Already connected
        }

        self.state = .connecting;

        // Note: Actual WebSocket connection would be implemented here
        // For now, this is a skeleton structure
        // Real implementation would use websocket library

        std.log.info("WebSocket connecting to {s}", .{self.ws_url});

        // Simulate connection
        self.state = .connected;
    }

    /// Disconnect from WebSocket server
    pub fn disconnect(self: *WsClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state == .disconnected) {
            return;
        }

        // Unsubscribe all
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.active = false;
        }

        self.state = .disconnected;
        std.log.info("WebSocket disconnected", .{});
    }

    /// Subscribe to new block headers
    pub fn subscribeNewHeads(
        self: *WsClient,
        callback: EventCallback,
        user_data: ?*anyopaque,
    ) !SubscriptionId {
        return self.subscribe(.new_heads, null, callback, user_data);
    }

    /// Subscribe to pending transactions
    pub fn subscribePendingTransactions(
        self: *WsClient,
        callback: EventCallback,
        user_data: ?*anyopaque,
    ) !SubscriptionId {
        return self.subscribe(.pending_transactions, null, callback, user_data);
    }

    /// Subscribe to event logs
    pub fn subscribeLogs(
        self: *WsClient,
        filter: LogFilter,
        callback: EventCallback,
        user_data: ?*anyopaque,
    ) !SubscriptionId {
        return self.subscribe(.logs, filter, callback, user_data);
    }

    /// Generic subscribe method
    fn subscribe(
        self: *WsClient,
        sub_type: SubscriptionType,
        filter: ?LogFilter,
        callback: EventCallback,
        user_data: ?*anyopaque,
    ) !SubscriptionId {
        _ = filter; // Will be used in full implementation

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state != .connected) {
            return error.NotConnected;
        }

        // Generate subscription ID (in real implementation, comes from server)
        const sub_id = try std.fmt.allocPrint(
            self.allocator,
            "0x{x}",
            .{self.request_id},
        );
        self.request_id += 1;

        // Create subscription
        const subscription = Subscription{
            .id = sub_id,
            .sub_type = sub_type,
            .callback = callback,
            .user_data = user_data,
        };

        try self.subscriptions.put(sub_id, subscription);

        std.log.info("Subscribed: {s} (type: {})", .{ sub_id, sub_type });

        return sub_id;
    }

    /// Unsubscribe from a subscription
    pub fn unsubscribe(self: *WsClient, sub_id: SubscriptionId) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.subscriptions.fetchRemove(sub_id)) |entry| {
            self.allocator.free(entry.key);
            std.log.info("Unsubscribed: {s}", .{sub_id});
        } else {
            return error.SubscriptionNotFound;
        }
    }

    /// Check if connected
    pub fn isConnected(self: *const WsClient) bool {
        return self.state == .connected;
    }

    /// Get subscription count
    pub fn getSubscriptionCount(self: *const WsClient) usize {
        return self.subscriptions.count();
    }
};

/// WebSocket manager with reconnection
pub const WsManager = struct {
    allocator: std.mem.Allocator,
    client: *WsClient,
    running: bool = false,

    /// Initialize manager
    pub fn init(
        allocator: std.mem.Allocator,
        ws_url: []const u8,
    ) !*WsManager {
        const self = try allocator.create(WsManager);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .client = try WsClient.init(allocator, ws_url),
        };

        return self;
    }

    /// Clean up
    pub fn deinit(self: *WsManager) void {
        self.stop();
        self.client.deinit();
        self.allocator.destroy(self);
    }

    /// Start manager with auto-reconnect
    pub fn start(self: *WsManager) !void {
        self.running = true;

        // Connect initially
        try self.client.connect();
    }

    /// Stop manager
    pub fn stop(self: *WsManager) void {
        self.running = false;
        self.client.disconnect();
    }

    /// Reconnection loop (should run in separate thread)
    pub fn reconnectLoop(self: *WsManager) void {
        while (self.running) {
            if (!self.client.isConnected() and self.client.auto_reconnect) {
                std.log.info("Attempting to reconnect...", .{});

                self.client.connect() catch |err| {
                    std.log.err("Reconnection failed: {}", .{err});
                };

                // Wait before retry
                std.time.sleep(self.client.reconnect_delay_ms * std.time.ns_per_ms);
            }

            // Check every second
            std.time.sleep(std.time.ns_per_s);
        }
    }
};

// Tests
const testing = std.testing;

test "SubscriptionType enum" {
    const sub_type: SubscriptionType = .new_heads;
    try testing.expect(sub_type == .new_heads);
}

test "ConnectionState enum" {
    var state: ConnectionState = .disconnected;
    try testing.expect(state == .disconnected);

    state = .connected;
    try testing.expect(state == .connected);
}

test "LogFilter structure" {
    const filter = LogFilter{
        .address = "0x1234",
        .topics = null,
    };

    try testing.expect(filter.address != null);
    try testing.expect(filter.topics == null);
}
