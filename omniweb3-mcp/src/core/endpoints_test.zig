//! Unit tests for endpoint configuration
//!
//! Tests cover:
//! - Solana RPC endpoint resolution
//! - Jupiter API endpoint URLs
//! - dFlow API endpoint URLs
//! - Meteora API endpoint URLs
//! - EVM RPC endpoint URLs

const std = @import("std");
const testing = std.testing;
const endpoints = @import("endpoints.zig");

// =============================================================================
// Solana Endpoints Tests
// =============================================================================

test "solana endpoints are valid URLs" {
    // Verify all Solana endpoints start with http
    try testing.expect(std.mem.startsWith(u8, endpoints.solana.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.solana.devnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.solana.testnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.solana.localhost, "http://"));
}

test "solana.resolve - all networks" {
    // Test mainnet resolution
    const mainnet = endpoints.solana.resolve("mainnet");
    try testing.expectEqualStrings(endpoints.solana.mainnet, mainnet);

    // Test devnet resolution
    const devnet = endpoints.solana.resolve("devnet");
    try testing.expectEqualStrings(endpoints.solana.devnet, devnet);

    // Test testnet resolution
    const testnet = endpoints.solana.resolve("testnet");
    try testing.expectEqualStrings(endpoints.solana.testnet, testnet);

    // Test localhost resolution
    const localhost = endpoints.solana.resolve("localhost");
    try testing.expectEqualStrings(endpoints.solana.localhost, localhost);
}

test "solana.resolve - unknown network defaults to devnet" {
    const result = endpoints.solana.resolve("unknown-network");
    try testing.expectEqualStrings(endpoints.solana.devnet, result);

    const empty = endpoints.solana.resolve("");
    try testing.expectEqualStrings(endpoints.solana.devnet, empty);
}

test "solana.resolve - case sensitive" {
    // Network names are case-sensitive
    const mainnet_caps = endpoints.solana.resolve("MAINNET");
    try testing.expectEqualStrings(endpoints.solana.devnet, mainnet_caps); // Should default

    const mainnet_lower = endpoints.solana.resolve("mainnet");
    try testing.expectEqualStrings(endpoints.solana.mainnet, mainnet_lower);
}

// =============================================================================
// Jupiter Endpoints Tests
// =============================================================================

test "jupiter base URL is valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.base, "https://"));
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.base, "jup.ag") != null);
}

test "jupiter swap endpoints are properly formed" {
    // All swap endpoints should start with base URL
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.quote, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.swap, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.program_labels, endpoints.jupiter.base));

    // Verify paths
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.quote, "/swap/") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.quote, "/quote") != null);
}

test "jupiter ultra endpoints are properly formed" {
    // All ultra endpoints should start with base
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_order, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_execute, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_balances, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_holdings, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_shield, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_search, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.ultra_routers, endpoints.jupiter.base));

    // Verify all contain /ultra/ path
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.ultra_order, "/ultra/") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.ultra_execute, "/ultra/") != null);
}

test "jupiter price endpoint is valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.price, endpoints.jupiter.base));
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.price, "/price/") != null);
}

test "jupiter tokens endpoints are properly formed" {
    // Tokens endpoints
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.tokens_search, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.tokens_tag, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.tokens_category, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.tokens_recent, endpoints.jupiter.base));

    // Verify /tokens/ path
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.tokens_search, "/tokens/") != null);
}

test "jupiter portfolio endpoints are properly formed" {
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.portfolio_positions, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.portfolio_platforms, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.portfolio_staked_jup, endpoints.jupiter.base));

    // Verify /portfolio/ path
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.portfolio_positions, "/portfolio/") != null);
}

test "jupiter lend endpoints are properly formed" {
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.lend_positions, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.lend_earnings, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.lend_tokens, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.lend_mint, endpoints.jupiter.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.jupiter.lend_redeem, endpoints.jupiter.base));

    // Verify /lend/ path
    try testing.expect(std.mem.indexOf(u8, endpoints.jupiter.lend_positions, "/lend/") != null);
}

// =============================================================================
// dFlow Endpoints Tests
// =============================================================================

test "dflow base URLs are valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.base, "https://"));
    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.base, "dflow") != null);

    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.prediction_base, "https://"));
    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.prediction_base, "prediction") != null);
}

test "dflow swap endpoints are properly formed" {
    // Order API
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.order, endpoints.dflow.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.order_status, endpoints.dflow.base));

    // Quote and swap
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.quote, endpoints.dflow.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.swap, endpoints.dflow.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.swap_instructions, endpoints.dflow.base));

    // Intent
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.intent, endpoints.dflow.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.submit_intent, endpoints.dflow.base));
}

test "dflow prediction market endpoints are properly formed" {
    // Events
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.pm_events, endpoints.dflow.prediction_base));
    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.pm_events, "/events") != null);

    // Markets
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.pm_markets, endpoints.dflow.prediction_base));
    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.pm_markets, "/markets") != null);

    // Orderbook
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.pm_orderbook, endpoints.dflow.prediction_base));
    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.pm_orderbook, "/orderbook") != null);
}

test "dflow token and venue endpoints are valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.tokens, endpoints.dflow.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.tokens_with_decimals, endpoints.dflow.base));
    try testing.expect(std.mem.startsWith(u8, endpoints.dflow.venues, endpoints.dflow.base));

    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.tokens, "/tokens") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.dflow.venues, "/venues") != null);
}

// =============================================================================
// Meteora Endpoints Tests
// =============================================================================

test "meteora base URLs are valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.dlmm_base, "https://"));
    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.dlmm_base, "meteora") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.dlmm_base, "dlmm") != null);

    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.damm_base, "https://"));
    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.damm_base, "meteora") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.damm_base, "amm") != null);
}

test "meteora DLMM endpoints are properly formed" {
    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.dlmm_pairs_all, endpoints.meteora.dlmm_base));
    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.dlmm_pair, endpoints.meteora.dlmm_base));
    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.dlmm_pairs_by_groups, endpoints.meteora.dlmm_base));

    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.dlmm_pairs_all, "/pair/") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.dlmm_pair, "/pair") != null);
}

test "meteora DAMM endpoints are properly formed" {
    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.damm_pools, endpoints.meteora.damm_base));
    try testing.expect(std.mem.startsWith(u8, endpoints.meteora.damm_pool, endpoints.meteora.damm_base));

    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.damm_pools, "/pool/") != null);
    try testing.expect(std.mem.indexOf(u8, endpoints.meteora.damm_pool, "/pool") != null);
}

// =============================================================================
// EVM Endpoints Tests
// =============================================================================

test "ethereum endpoints are valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.ethereum.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.ethereum.sepolia, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.ethereum.localhost, "http://"));

    try testing.expect(std.mem.indexOf(u8, endpoints.evm.ethereum.localhost, "8545") != null);
}

test "BSC endpoints are valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.bsc.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.bsc.testnet, "https://"));

    try testing.expect(std.mem.indexOf(u8, endpoints.evm.bsc.mainnet, "binance") != null);
}

test "layer 2 endpoints are valid" {
    // Polygon
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.polygon.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.polygon.mumbai, "https://"));

    // Arbitrum
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.arbitrum.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.arbitrum.sepolia, "https://"));

    // Optimism
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.optimism.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.optimism.sepolia, "https://"));

    // Base
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.base.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.base.sepolia, "https://"));
}

test "avalanche endpoints are valid" {
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.avalanche.mainnet, "https://"));
    try testing.expect(std.mem.startsWith(u8, endpoints.evm.avalanche.fuji, "https://"));

    try testing.expect(std.mem.indexOf(u8, endpoints.evm.avalanche.mainnet, "avax") != null);
}
