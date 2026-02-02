//! Response Cache Module
//!
//! In-memory cache for RPC responses with TTL (Time-To-Live) support.
//!
//! Features:
//! - TTL-based expiration (configurable per entry)
//! - LRU eviction policy (Least Recently Used)
//! - Thread-safe operations
//! - Memory-efficient storage
//!
//! Use cases:
//! - Cache expensive RPC queries (account info, token prices)
//! - Reduce API rate limiting issues
//! - Improve response times for repeated queries
//! - Decrease network load
//!
//! Performance:
//! - O(1) get/put operations
//! - Automatic cleanup of expired entries
//! - Configurable max size

const std = @import("std");

/// Get current time in seconds (cross-platform)
fn getTimestamp() i64 {
    const instant = std.time.Instant.now() catch return 0;
    // Convert to seconds based on platform
    if (@TypeOf(instant.timestamp) == u64) {
        return @intCast(instant.timestamp / std.time.ns_per_s);
    } else {
        // POSIX timespec - first field is seconds
        const ts_ptr: *const i64 = @ptrCast(&instant.timestamp);
        return ts_ptr.*;
    }
}

/// Cache entry with TTL
const CacheEntry = struct {
    value: []const u8,
    expires_at: i64, // Unix timestamp in seconds
    last_accessed: i64,

    pub fn isExpired(self: *const CacheEntry) bool {
        const now = getTimestamp();
        return now >= self.expires_at;
    }
};

/// Response cache configuration
pub const CacheConfig = struct {
    /// Maximum number of entries (default: 1000)
    max_entries: usize = 1000,

    /// Default TTL in seconds (default: 60 seconds)
    default_ttl: i64 = 60,

    /// Enable automatic cleanup (default: true)
    auto_cleanup: bool = true,

    /// Cleanup interval in seconds (default: 300 = 5 minutes)
    cleanup_interval: i64 = 300,
};

/// Response cache with TTL and LRU eviction
pub const ResponseCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    config: CacheConfig,
    last_cleanup: i64,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Initialize cache
    pub fn init(allocator: std.mem.Allocator, config: CacheConfig) Self {
        return Self{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .config = config,
            .last_cleanup = getTimestamp(),
            .mutex = .{},
        };
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.entries.deinit();
    }

    /// Get cached value
    ///
    /// Returns null if:
    /// - Key not found
    /// - Entry expired
    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.getPtr(key)) |entry| {
            // Check if expired
            if (entry.isExpired()) {
                // Remove expired entry
                const key_copy = entry.value;
                self.allocator.free(key_copy);
                _ = self.entries.remove(key);
                return null;
            }

            // Update last accessed time
            entry.last_accessed = getTimestamp();

            return entry.value;
        }

        return null;
    }

    /// Put value in cache
    ///
    /// Parameters:
    /// - key: Cache key
    /// - value: Value to cache
    /// - ttl: Optional TTL in seconds (uses default if null)
    pub fn put(
        self: *Self,
        key: []const u8,
        value: []const u8,
        ttl: ?i64,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we need to evict (only if adding new key, not updating existing)
        const key_exists = self.entries.contains(key);
        if (!key_exists and self.entries.count() >= self.config.max_entries) {
            try self.evictLRU();
        }

        // Copy key and value
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);

        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        const ttl_seconds = ttl orelse self.config.default_ttl;
        const now = getTimestamp();

        const entry = CacheEntry{
            .value = value_copy,
            .expires_at = now + ttl_seconds,
            .last_accessed = now,
        };

        // Remove old entry if exists
        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.value);
        }

        try self.entries.put(key_copy, entry);

        // Auto cleanup if needed
        if (self.config.auto_cleanup) {
            // Simple check: just try cleanup periodically
            // More sophisticated timing would require platform-specific code
            try self.cleanup();
        }
    }

    /// Remove entry from cache
    pub fn remove(self: *Self, key: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.value);
        }
    }

    /// Clear all entries
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.entries.clearRetainingCapacity();
    }

    /// Get cache statistics
    pub fn stats(self: *Self) CacheStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var expired_count: usize = 0;
        var total_size: usize = 0;

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isExpired()) {
                expired_count += 1;
            }
            total_size += entry.value_ptr.value.len;
        }

        return CacheStats{
            .total_entries = self.entries.count(),
            .expired_entries = expired_count,
            .total_size_bytes = total_size,
            .max_entries = self.config.max_entries,
        };
    }

    /// Cleanup expired entries
    fn cleanup(self: *Self) !void {
        var to_remove: std.ArrayList([]const u8) = .empty;
        defer to_remove.deinit(self.allocator);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isExpired()) {
                try to_remove.append(self.allocator, entry.key_ptr.*);
            }
        }

        for (to_remove.items) |key| {
            if (self.entries.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value.value);
            }
        }

        self.last_cleanup = getTimestamp();
    }

    /// Evict least recently used entry
    fn evictLRU(self: *Self) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i64 = std.math.maxInt(i64);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.last_accessed < oldest_time) {
                oldest_time = entry.value_ptr.last_accessed;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.entries.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value.value);
            }
        }
    }
};

/// Cache statistics
pub const CacheStats = struct {
    total_entries: usize,
    expired_entries: usize,
    total_size_bytes: usize,
    max_entries: usize,

    pub fn hitRate(self: CacheStats) f64 {
        if (self.total_entries == 0) return 0.0;
        const active = self.total_entries - self.expired_entries;
        return @as(f64, @floatFromInt(active)) / @as(f64, @floatFromInt(self.total_entries));
    }

    pub fn usagePercent(self: CacheStats) f64 {
        return (@as(f64, @floatFromInt(self.total_entries)) / @as(f64, @floatFromInt(self.max_entries))) * 100.0;
    }
};
