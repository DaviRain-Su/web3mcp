//! EVM RPC Connection Pool
//!
//! Provides connection pooling, load balancing, and failover for RPC endpoints.
//! Improves performance and reliability through:
//! - Multiple endpoint support
//! - Automatic failover
//! - Load balancing (round-robin, random, least-connections)
//! - Health checks
//! - Connection reuse

const std = @import("std");
const rpc_client = @import("./rpc_client.zig");

const EvmRpcClient = rpc_client.EvmRpcClient;
const TransactionRequest = rpc_client.TransactionRequest;
const BlockTag = rpc_client.BlockTag;

/// Load balancing strategy
pub const LoadBalanceStrategy = enum {
    /// Round-robin distribution
    round_robin,
    /// Random selection
    random,
    /// Least active connections
    least_connections,
    /// Fastest response time
    fastest,
};

/// Connection health status
pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,
};

/// RPC endpoint configuration
pub const EndpointConfig = struct {
    /// RPC URL
    url: []const u8,

    /// Priority (lower = higher priority)
    priority: u8 = 0,

    /// Weight for weighted load balancing
    weight: u8 = 1,

    /// Maximum concurrent requests
    max_concurrent: usize = 100,

    /// Request timeout in milliseconds
    timeout_ms: u64 = 30000,
};

/// Connection statistics
pub const ConnectionStats = struct {
    /// Total requests made
    total_requests: u64 = 0,

    /// Successful requests
    successful_requests: u64 = 0,

    /// Failed requests
    failed_requests: u64 = 0,

    /// Total response time (ms)
    total_response_time_ms: u64 = 0,

    /// Average response time (ms)
    pub fn avgResponseTime(self: ConnectionStats) u64 {
        if (self.successful_requests == 0) return 0;
        return self.total_response_time_ms / self.successful_requests;
    }

    /// Success rate (0-100)
    pub fn successRate(self: ConnectionStats) u8 {
        if (self.total_requests == 0) return 100;
        const rate = (self.successful_requests * 100) / self.total_requests;
        return @intCast(rate);
    }
};

/// Single RPC connection
pub const RpcConnection = struct {
    /// Connection ID
    id: usize,

    /// Endpoint configuration
    config: EndpointConfig,

    /// RPC client instance
    client: EvmRpcClient,

    /// Health status
    health: HealthStatus = .healthy,

    /// Current active requests
    active_requests: usize = 0,

    /// Statistics
    stats: ConnectionStats = .{},

    /// Last health check timestamp
    last_health_check: i64 = 0,

    /// Initialize connection
    pub fn init(
        allocator: std.mem.Allocator,
        id: usize,
        config: EndpointConfig,
        chain_config: @import("./chains.zig").ChainConfig,
    ) !RpcConnection {
        // Create RPC client with custom URL
        var modified_chain_config = chain_config;
        modified_chain_config.rpc_url = config.url;

        return RpcConnection{
            .id = id,
            .config = config,
            .client = try EvmRpcClient.init(allocator, modified_chain_config),
            .last_health_check = std.time.timestamp(),
        };
    }

    /// Check if connection is available
    pub fn isAvailable(self: *const RpcConnection) bool {
        return self.health != .unhealthy and
            self.active_requests < self.config.max_concurrent;
    }

    /// Record request start
    pub fn startRequest(self: *RpcConnection) void {
        self.active_requests += 1;
        self.stats.total_requests += 1;
    }

    /// Record request completion
    pub fn completeRequest(self: *RpcConnection, success: bool, response_time_ms: u64) void {
        self.active_requests -= 1;

        if (success) {
            self.stats.successful_requests += 1;
            self.stats.total_response_time_ms += response_time_ms;
        } else {
            self.stats.failed_requests += 1;
        }

        // Update health based on recent performance
        self.updateHealth();
    }

    /// Update health status based on statistics
    fn updateHealth(self: *RpcConnection) void {
        const success_rate = self.stats.successRate();

        if (success_rate >= 95) {
            self.health = .healthy;
        } else if (success_rate >= 80) {
            self.health = .degraded;
        } else {
            self.health = .unhealthy;
        }
    }
};

/// RPC Connection Pool
pub const RpcPool = struct {
    allocator: std.mem.Allocator,

    /// All connections
    connections: []RpcConnection,

    /// Load balance strategy
    strategy: LoadBalanceStrategy = .round_robin,

    /// Round-robin counter
    round_robin_index: usize = 0,

    /// Random number generator
    rng: std.rand.DefaultPrng,

    /// Health check interval (seconds)
    health_check_interval: u64 = 60,

    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},

    /// Initialize RPC pool
    pub fn init(
        allocator: std.mem.Allocator,
        endpoints: []const EndpointConfig,
        chain_config: @import("./chains.zig").ChainConfig,
        strategy: LoadBalanceStrategy,
    ) !*RpcPool {
        if (endpoints.len == 0) {
            return error.NoEndpoints;
        }

        const self = try allocator.create(RpcPool);
        errdefer allocator.destroy(self);

        // Initialize connections
        var connections = try allocator.alloc(RpcConnection, endpoints.len);
        errdefer allocator.free(connections);

        for (endpoints, 0..) |endpoint_config, i| {
            connections[i] = try RpcConnection.init(
                allocator,
                i,
                endpoint_config,
                chain_config,
            );
        }

        self.* = .{
            .allocator = allocator,
            .connections = connections,
            .strategy = strategy,
            .rng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp())),
        };

        return self;
    }

    /// Clean up
    pub fn deinit(self: *RpcPool) void {
        self.allocator.free(self.connections);
        self.allocator.destroy(self);
    }

    /// Get connection using load balancing strategy
    pub fn getConnection(self: *RpcPool) !*RpcConnection {
        self.mutex.lock();
        defer self.mutex.unlock();

        return switch (self.strategy) {
            .round_robin => self.getConnectionRoundRobin(),
            .random => self.getConnectionRandom(),
            .least_connections => self.getConnectionLeastConnections(),
            .fastest => self.getConnectionFastest(),
        };
    }

    /// Round-robin selection
    fn getConnectionRoundRobin(self: *RpcPool) !*RpcConnection {
        const start_index = self.round_robin_index;

        // Try to find available connection
        for (0..self.connections.len) |_| {
            const conn = &self.connections[self.round_robin_index];
            self.round_robin_index = (self.round_robin_index + 1) % self.connections.len;

            if (conn.isAvailable()) {
                return conn;
            }
        }

        // No available connections, return first one anyway
        self.round_robin_index = (start_index + 1) % self.connections.len;
        return &self.connections[start_index];
    }

    /// Random selection
    fn getConnectionRandom(self: *RpcPool) !*RpcConnection {
        // Get available connections
        var available_count: usize = 0;
        for (self.connections) |*conn| {
            if (conn.isAvailable()) {
                available_count += 1;
            }
        }

        if (available_count == 0) {
            // Return random connection even if not available
            const idx = self.rng.random().intRangeAtMost(usize, 0, self.connections.len - 1);
            return &self.connections[idx];
        }

        // Select random available connection
        const target = self.rng.random().intRangeAtMost(usize, 0, available_count - 1);
        var count: usize = 0;

        for (self.connections) |*conn| {
            if (conn.isAvailable()) {
                if (count == target) {
                    return conn;
                }
                count += 1;
            }
        }

        unreachable;
    }

    /// Least connections selection
    fn getConnectionLeastConnections(self: *RpcPool) !*RpcConnection {
        var best: ?*RpcConnection = null;
        var min_active: usize = std.math.maxInt(usize);

        for (self.connections) |*conn| {
            if (conn.health == .unhealthy) continue;

            if (conn.active_requests < min_active) {
                min_active = conn.active_requests;
                best = conn;
            }
        }

        return best orelse &self.connections[0];
    }

    /// Fastest response time selection
    fn getConnectionFastest(self: *RpcPool) !*RpcConnection {
        var best: ?*RpcConnection = null;
        var min_response: u64 = std.math.maxInt(u64);

        for (self.connections) |*conn| {
            if (conn.health == .unhealthy) continue;

            const avg_time = conn.stats.avgResponseTime();
            if (avg_time < min_response or (avg_time == 0 and best == null)) {
                min_response = avg_time;
                best = conn;
            }
        }

        return best orelse &self.connections[0];
    }

    /// Perform health check on all connections
    pub fn healthCheck(self: *RpcPool) !void {
        const now = std.time.timestamp();

        for (self.connections) |*conn| {
            // Skip if checked recently
            if (now - conn.last_health_check < self.health_check_interval) {
                continue;
            }

            // Simple health check: get chain ID
            const start = std.time.milliTimestamp();
            const result = conn.client.ethChainId() catch |err| {
                std.log.warn("Health check failed for connection {d}: {}", .{ conn.id, err });
                conn.health = .unhealthy;
                conn.last_health_check = now;
                continue;
            };
            const duration = @as(u64, @intCast(std.time.milliTimestamp() - start));

            self.allocator.free(result);

            // Update health based on response time
            if (duration < 1000) {
                conn.health = .healthy;
            } else if (duration < 3000) {
                conn.health = .degraded;
            } else {
                conn.health = .unhealthy;
            }

            conn.last_health_check = now;
        }
    }

    /// Get pool statistics
    pub fn getPoolStats(self: *RpcPool) PoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = PoolStats{};

        for (self.connections) |*conn| {
            stats.total_connections += 1;

            switch (conn.health) {
                .healthy => stats.healthy_connections += 1,
                .degraded => stats.degraded_connections += 1,
                .unhealthy => stats.unhealthy_connections += 1,
            }

            stats.total_requests += conn.stats.total_requests;
            stats.successful_requests += conn.stats.successful_requests;
            stats.failed_requests += conn.stats.failed_requests;
            stats.active_requests += conn.active_requests;

            if (conn.stats.avgResponseTime() > stats.max_avg_response_time) {
                stats.max_avg_response_time = conn.stats.avgResponseTime();
            }
        }

        return stats;
    }

    /// Execute RPC call with automatic retry and failover
    pub fn executeWithRetry(
        self: *RpcPool,
        comptime func: anytype,
        args: anytype,
        max_retries: usize,
    ) !@typeInfo(@TypeOf(func)).Fn.return_type.? {
        var last_error: anyerror = error.AllConnectionsFailed;
        var attempts: usize = 0;

        while (attempts < max_retries) : (attempts += 1) {
            const conn = try self.getConnection();

            const start_time = std.time.milliTimestamp();
            conn.startRequest();

            const result = @call(.auto, func, .{&conn.client} ++ args) catch |err| {
                const duration = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                conn.completeRequest(false, duration);
                last_error = err;
                continue;
            };

            const duration = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            conn.completeRequest(true, duration);

            return result;
        }

        return last_error;
    }
};

/// Pool statistics
pub const PoolStats = struct {
    total_connections: usize = 0,
    healthy_connections: usize = 0,
    degraded_connections: usize = 0,
    unhealthy_connections: usize = 0,
    total_requests: u64 = 0,
    successful_requests: u64 = 0,
    failed_requests: u64 = 0,
    active_requests: usize = 0,
    max_avg_response_time: u64 = 0,

    /// Calculate overall success rate
    pub fn successRate(self: PoolStats) u8 {
        if (self.total_requests == 0) return 100;
        const rate = (self.successful_requests * 100) / self.total_requests;
        return @intCast(rate);
    }
};

// Tests
const testing = std.testing;

test "ConnectionStats calculations" {
    var stats = ConnectionStats{
        .total_requests = 100,
        .successful_requests = 95,
        .failed_requests = 5,
        .total_response_time_ms = 9500,
    };

    try testing.expectEqual(@as(u64, 100), stats.avgResponseTime());
    try testing.expectEqual(@as(u8, 95), stats.successRate());
}

test "PoolStats calculations" {
    const stats = PoolStats{
        .total_connections = 3,
        .healthy_connections = 2,
        .total_requests = 1000,
        .successful_requests = 980,
        .failed_requests = 20,
    };

    try testing.expectEqual(@as(u8, 98), stats.successRate());
}

test "LoadBalanceStrategy enum" {
    const strategy: LoadBalanceStrategy = .round_robin;
    try testing.expect(strategy == .round_robin);
}
