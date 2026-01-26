//! Unit tests for price subscription module

const std = @import("std");
const testing = std.testing;
const price_subscription = @import("price_subscription.zig");

test "price_subscription module loads" {
    // Basic smoke test to ensure module compiles
    _ = price_subscription;
}

test "resolveWsEndpoint mainnet" {
    const endpoint = price_subscription.resolveWsEndpoint("mainnet");
    try testing.expectEqualStrings("wss://api.mainnet-beta.solana.com", endpoint);
}

test "resolveWsEndpoint devnet" {
    const endpoint = price_subscription.resolveWsEndpoint("devnet");
    try testing.expectEqualStrings("wss://api.devnet.solana.com", endpoint);
}

test "resolveWsEndpoint testnet" {
    const endpoint = price_subscription.resolveWsEndpoint("testnet");
    try testing.expectEqualStrings("wss://api.testnet.solana.com", endpoint);
}

test "resolveWsEndpoint localhost" {
    const endpoint = price_subscription.resolveWsEndpoint("localhost");
    try testing.expectEqualStrings("ws://localhost:8900", endpoint);
}

test "resolveWsEndpoint unknown defaults to devnet" {
    const endpoint = price_subscription.resolveWsEndpoint("unknown");
    try testing.expectEqualStrings("wss://api.devnet.solana.com", endpoint);
}

// Note: Actual WebSocket tests require:
// 1. Network connectivity
// 2. Valid Solana WebSocket endpoint
// 3. Real pool addresses
// These are better suited for integration tests.
