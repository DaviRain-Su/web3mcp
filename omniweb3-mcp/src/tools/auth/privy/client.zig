//! Privy API Client
//!
//! HTTP client for Privy REST API with authentication handling.
//! Base URL: https://api.privy.io
//!
//! Authentication requires:
//! - Basic Auth: app_id:app_secret (base64 encoded)
//! - Header: privy-app-id

const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../core/evm_runtime.zig");

/// Privy API base URL
pub const BASE_URL = "https://api.privy.io";

/// Privy API version prefix
pub const API_VERSION = "/v1";

/// Get Privy App ID from environment
pub fn getAppId() ?[]const u8 {
    const result = std.c.getenv("PRIVY_APP_ID");
    if (result) |ptr| {
        return std.mem.span(ptr);
    }
    return null;
}

/// Get Privy App Secret from environment
pub fn getAppSecret() ?[]const u8 {
    const result = std.c.getenv("PRIVY_APP_SECRET");
    if (result) |ptr| {
        return std.mem.span(ptr);
    }
    return null;
}

/// Check if Privy is configured
pub fn isConfigured() bool {
    return getAppId() != null and getAppSecret() != null;
}

/// Build Basic Auth header value
pub fn buildAuthHeader(allocator: std.mem.Allocator) ![]const u8 {
    const app_id = getAppId() orelse return error.MissingAppId;
    const app_secret = getAppSecret() orelse return error.MissingAppSecret;

    // Build "app_id:app_secret"
    const credentials = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ app_id, app_secret });
    defer allocator.free(credentials);

    // Base64 encode
    const encoded_len = std.base64.standard.Encoder.calcSize(credentials.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, credentials);

    // Build "Basic <encoded>"
    const auth_header = try std.fmt.allocPrint(allocator, "Basic {s}", .{encoded});
    allocator.free(encoded);

    return auth_header;
}

/// Build full API URL
pub fn buildUrl(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ BASE_URL, API_VERSION, path });
}

/// Make authenticated GET request to Privy API
pub fn privyGet(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const url = try buildUrl(allocator, path);
    defer allocator.free(url);

    const auth_header = try buildAuthHeader(allocator);
    defer allocator.free(auth_header);

    const app_id = getAppId() orelse return error.MissingAppId;

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    var headers: [3]std.http.Header = .{
        .{ .name = "Authorization", .value = auth_header },
        .{ .name = "privy-app-id", .value = app_id },
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &out.writer,
        .extra_headers = &headers,
    }) catch {
        return error.FetchFailed;
    };

    if (fetch_result.status.class() != .success) {
        return error.FetchFailed;
    }

    return out.toOwnedSlice();
}

/// Make authenticated POST request to Privy API
pub fn privyPost(allocator: std.mem.Allocator, path: []const u8, body: []const u8) ![]u8 {
    const url = try buildUrl(allocator, path);
    defer allocator.free(url);

    const auth_header = try buildAuthHeader(allocator);
    defer allocator.free(auth_header);

    const app_id = getAppId() orelse return error.MissingAppId;

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    var headers: [3]std.http.Header = .{
        .{ .name = "Authorization", .value = auth_header },
        .{ .name = "privy-app-id", .value = app_id },
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .response_writer = &out.writer,
        .extra_headers = &headers,
    }) catch {
        return error.FetchFailed;
    };

    if (fetch_result.status.class() != .success) {
        return error.FetchFailed;
    }

    return out.toOwnedSlice();
}

/// Chain types supported by Privy wallets
pub const ChainType = enum {
    ethereum,
    solana,
    cosmos,
    stellar,
    sui,
    aptos,
    movement,
    tron,
    bitcoin_segwit,
    near,
    ton,
    starknet,
    spark,

    pub fn toString(self: ChainType) []const u8 {
        return switch (self) {
            .ethereum => "ethereum",
            .solana => "solana",
            .cosmos => "cosmos",
            .stellar => "stellar",
            .sui => "sui",
            .aptos => "aptos",
            .movement => "movement",
            .tron => "tron",
            .bitcoin_segwit => "bitcoin-segwit",
            .near => "near",
            .ton => "ton",
            .starknet => "starknet",
            .spark => "spark",
        };
    }
};

/// Solana network CAIP-2 identifiers
pub const SolanaNetwork = struct {
    pub const MAINNET = "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp";
    pub const DEVNET = "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1";
    pub const TESTNET = "solana:4uhcVJyU9pJkvQyS88uRDiswHXSCkY3z";

    pub fn fromNetwork(network: []const u8) []const u8 {
        if (std.mem.eql(u8, network, "mainnet")) return MAINNET;
        if (std.mem.eql(u8, network, "devnet")) return DEVNET;
        if (std.mem.eql(u8, network, "testnet")) return TESTNET;
        return DEVNET; // Default to devnet
    }
};

/// EVM network CAIP-2 identifiers
pub const EvmNetwork = struct {
    pub const ETHEREUM_MAINNET = "eip155:1";
    pub const ETHEREUM_SEPOLIA = "eip155:11155111";
    pub const AVALANCHE_MAINNET = "eip155:43114";
    pub const AVALANCHE_FUJI = "eip155:43113";
    pub const BNB_MAINNET = "eip155:56";
    pub const BNB_TESTNET = "eip155:97";
};

/// Helper to create error result
pub fn errorResult(allocator: std.mem.Allocator, message: []const u8) mcp.tools.ToolError!mcp.tools.ToolResult {
    return mcp.tools.errorResult(allocator, message) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

/// Helper to create JSON result
pub fn jsonResult(allocator: std.mem.Allocator, json_str: []const u8) mcp.tools.ToolError!mcp.tools.ToolResult {
    return mcp.tools.textResult(allocator, json_str) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
