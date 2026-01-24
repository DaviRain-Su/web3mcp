//! Centralized RPC endpoint configuration.
//!
//! All external service endpoints should be defined here for easy maintenance.
//! When APIs are updated or deprecated, only this file needs to be modified.

const std = @import("std");

// =============================================================================
// Solana RPC Endpoints
// =============================================================================

pub const solana = struct {
    pub const mainnet = "https://api.mainnet-beta.solana.com";
    pub const devnet = "https://api.devnet.solana.com";
    pub const testnet = "https://api.testnet.solana.com";
    pub const localhost = "http://localhost:8899";

    /// Resolve Solana RPC endpoint by network name.
    /// Returns devnet as default for unknown networks.
    pub fn resolve(network: []const u8) []const u8 {
        if (std.mem.eql(u8, network, "mainnet")) return mainnet;
        if (std.mem.eql(u8, network, "testnet")) return testnet;
        if (std.mem.eql(u8, network, "localhost")) return localhost;
        return devnet;
    }
};

// =============================================================================
// Jupiter API Endpoints
// Docs: https://dev.jup.ag/api-reference
// =============================================================================

pub const jupiter = struct {
    /// Base URL for Jupiter API
    pub const base = "https://api.jup.ag";

    /// Metis Swap API - Quote endpoint
    /// GET /swap/v1/quote
    pub const quote = base ++ "/swap/v1/quote";

    /// Price API V3
    /// GET /price/v3
    pub const price = base ++ "/price/v3";

    /// Ultra Swap API - Order endpoint (for future use)
    /// POST /ultra/v1/order
    pub const ultra_order = base ++ "/ultra/v1/order";

    /// Ultra Swap API - Execute endpoint (for future use)
    /// POST /ultra/v1/execute
    pub const ultra_execute = base ++ "/ultra/v1/execute";
};

// =============================================================================
// EVM RPC Endpoints (for future use)
// =============================================================================

pub const evm = struct {
    pub const ethereum = struct {
        pub const mainnet = "https://eth.llamarpc.com";
        pub const sepolia = "https://rpc.sepolia.org";
        pub const localhost = "http://localhost:8545";
    };

    pub const bsc = struct {
        pub const mainnet = "https://bsc-dataseed.binance.org";
        pub const testnet = "https://data-seed-prebsc-1-s1.binance.org:8545";
    };

    pub const avalanche = struct {
        pub const mainnet = "https://api.avax.network/ext/bc/C/rpc";
        pub const fuji = "https://api.avax-test.network/ext/bc/C/rpc";
    };

    pub const polygon = struct {
        pub const mainnet = "https://polygon-rpc.com";
        pub const mumbai = "https://rpc-mumbai.maticvigil.com";
    };

    pub const arbitrum = struct {
        pub const mainnet = "https://arb1.arbitrum.io/rpc";
        pub const sepolia = "https://sepolia-rollup.arbitrum.io/rpc";
    };

    pub const optimism = struct {
        pub const mainnet = "https://mainnet.optimism.io";
        pub const sepolia = "https://sepolia.optimism.io";
    };

    pub const base = struct {
        pub const mainnet = "https://mainnet.base.org";
        pub const sepolia = "https://sepolia.base.org";
    };
};
