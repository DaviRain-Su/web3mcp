//! EVM Chain Configurations
//!
//! Defines chain-specific configurations for all supported EVM-compatible chains.
//! All chains share the same JSON-RPC interface but differ in chain ID, RPC endpoints, etc.

/// Chain configuration
pub const ChainConfig = struct {
    /// Chain ID (56=BSC, 1=Ethereum, 137=Polygon, etc.)
    chain_id: u64,

    /// Human-readable chain name
    name: []const u8,

    /// RPC endpoint URL
    rpc_url: []const u8,

    /// Block explorer URL
    explorer_url: []const u8,

    /// Native token symbol (BNB, ETH, MATIC, etc.)
    native_token: []const u8,

    /// Average block time in seconds
    block_time_seconds: u64,
};

/// Binance Smart Chain Mainnet
pub const BSC_MAINNET = ChainConfig{
    .chain_id = 56,
    .name = "BSC",
    .rpc_url = "https://bsc-dataseed.binance.org/",
    .explorer_url = "https://bscscan.com",
    .native_token = "BNB",
    .block_time_seconds = 3,
};

/// Binance Smart Chain Testnet
pub const BSC_TESTNET = ChainConfig{
    .chain_id = 97,
    .name = "BSC Testnet",
    .rpc_url = "https://data-seed-prebsc-1-s1.binance.org:8545/",
    .explorer_url = "https://testnet.bscscan.com",
    .native_token = "tBNB",
    .block_time_seconds = 3,
};

/// Ethereum Mainnet
pub const ETHEREUM_MAINNET = ChainConfig{
    .chain_id = 1,
    .name = "Ethereum",
    .rpc_url = "https://eth.llamarpc.com",
    .explorer_url = "https://etherscan.io",
    .native_token = "ETH",
    .block_time_seconds = 12,
};

/// Ethereum Sepolia Testnet
pub const ETHEREUM_SEPOLIA = ChainConfig{
    .chain_id = 11155111,
    .name = "Sepolia",
    .rpc_url = "https://rpc.sepolia.org",
    .explorer_url = "https://sepolia.etherscan.io",
    .native_token = "SepoliaETH",
    .block_time_seconds = 12,
};

/// Polygon Mainnet
pub const POLYGON_MAINNET = ChainConfig{
    .chain_id = 137,
    .name = "Polygon",
    .rpc_url = "https://polygon-rpc.com",
    .explorer_url = "https://polygonscan.com",
    .native_token = "MATIC",
    .block_time_seconds = 2,
};

/// Polygon Mumbai Testnet
pub const POLYGON_MUMBAI = ChainConfig{
    .chain_id = 80001,
    .name = "Mumbai",
    .rpc_url = "https://rpc-mumbai.maticvigil.com",
    .explorer_url = "https://mumbai.polygonscan.com",
    .native_token = "MATIC",
    .block_time_seconds = 2,
};

/// Arbitrum One
pub const ARBITRUM_ONE = ChainConfig{
    .chain_id = 42161,
    .name = "Arbitrum One",
    .rpc_url = "https://arb1.arbitrum.io/rpc",
    .explorer_url = "https://arbiscan.io",
    .native_token = "ETH",
    .block_time_seconds = 1,
};

/// Optimism Mainnet
pub const OPTIMISM_MAINNET = ChainConfig{
    .chain_id = 10,
    .name = "Optimism",
    .rpc_url = "https://mainnet.optimism.io",
    .explorer_url = "https://optimistic.etherscan.io",
    .native_token = "ETH",
    .block_time_seconds = 2,
};

/// Get chain config by chain ID
pub fn getChainById(chain_id: u64) ?ChainConfig {
    return switch (chain_id) {
        56 => BSC_MAINNET,
        97 => BSC_TESTNET,
        1 => ETHEREUM_MAINNET,
        11155111 => ETHEREUM_SEPOLIA,
        137 => POLYGON_MAINNET,
        80001 => POLYGON_MUMBAI,
        42161 => ARBITRUM_ONE,
        10 => OPTIMISM_MAINNET,
        else => null,
    };
}

/// Get chain config by name (case-insensitive)
pub fn getChainByName(name: []const u8) ?ChainConfig {
    const std = @import("std");

    if (std.ascii.eqlIgnoreCase(name, "bsc")) return BSC_MAINNET;
    if (std.ascii.eqlIgnoreCase(name, "bsc-testnet")) return BSC_TESTNET;
    if (std.ascii.eqlIgnoreCase(name, "ethereum")) return ETHEREUM_MAINNET;
    if (std.ascii.eqlIgnoreCase(name, "sepolia")) return ETHEREUM_SEPOLIA;
    if (std.ascii.eqlIgnoreCase(name, "polygon")) return POLYGON_MAINNET;
    if (std.ascii.eqlIgnoreCase(name, "mumbai")) return POLYGON_MUMBAI;
    if (std.ascii.eqlIgnoreCase(name, "arbitrum")) return ARBITRUM_ONE;
    if (std.ascii.eqlIgnoreCase(name, "optimism")) return OPTIMISM_MAINNET;

    return null;
}

// Tests
const testing = @import("std").testing;

test "getChainById" {
    const bsc = getChainById(56);
    try testing.expect(bsc != null);
    try testing.expectEqualStrings("BSC", bsc.?.name);
    try testing.expectEqual(@as(u64, 56), bsc.?.chain_id);

    const eth = getChainById(1);
    try testing.expect(eth != null);
    try testing.expectEqualStrings("Ethereum", eth.?.name);

    const unknown = getChainById(999999);
    try testing.expect(unknown == null);
}

test "getChainByName" {
    const bsc = getChainByName("bsc");
    try testing.expect(bsc != null);
    try testing.expectEqual(@as(u64, 56), bsc.?.chain_id);

    const bsc_upper = getChainByName("BSC");
    try testing.expect(bsc_upper != null);
    try testing.expectEqual(@as(u64, 56), bsc_upper.?.chain_id);

    const polygon = getChainByName("polygon");
    try testing.expect(polygon != null);
    try testing.expectEqual(@as(u64, 137), polygon.?.chain_id);

    const unknown = getChainByName("unknown");
    try testing.expect(unknown == null);
}
