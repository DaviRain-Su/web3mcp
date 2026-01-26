//! Unit tests for Wallet Provider functionality
//!
//! Tests cover:
//! - WalletType enum conversion
//! - ChainType enum conversion
//! - Wallet configuration validation
//! - Error handling

const std = @import("std");
const testing = std.testing;
const wallet_provider = @import("wallet_provider.zig");

// Test WalletType.fromString
test "WalletType.fromString - valid local" {
    const wallet_type = wallet_provider.WalletType.fromString("local");
    try testing.expect(wallet_type != null);
    try testing.expectEqual(wallet_provider.WalletType.local, wallet_type.?);
}

test "WalletType.fromString - valid privy" {
    const wallet_type = wallet_provider.WalletType.fromString("privy");
    try testing.expect(wallet_type != null);
    try testing.expectEqual(wallet_provider.WalletType.privy, wallet_type.?);
}

test "WalletType.fromString - invalid type returns null" {
    const wallet_type = wallet_provider.WalletType.fromString("invalid");
    try testing.expect(wallet_type == null);
}

test "WalletType.fromString - empty string returns null" {
    const wallet_type = wallet_provider.WalletType.fromString("");
    try testing.expect(wallet_type == null);
}

test "WalletType.fromString - case sensitive" {
    const wallet_type = wallet_provider.WalletType.fromString("Local");
    try testing.expect(wallet_type == null);
}

// Test ChainType.fromString
test "ChainType.fromString - valid solana" {
    const chain_type = wallet_provider.ChainType.fromString("solana");
    try testing.expect(chain_type != null);
    try testing.expectEqual(wallet_provider.ChainType.solana, chain_type.?);
}

test "ChainType.fromString - valid ethereum" {
    const chain_type = wallet_provider.ChainType.fromString("ethereum");
    try testing.expect(chain_type != null);
    try testing.expectEqual(wallet_provider.ChainType.ethereum, chain_type.?);
}

test "ChainType.fromString - evm maps to ethereum" {
    const chain_type = wallet_provider.ChainType.fromString("evm");
    try testing.expect(chain_type != null);
    try testing.expectEqual(wallet_provider.ChainType.ethereum, chain_type.?);
}

test "ChainType.fromString - invalid type returns null" {
    const chain_type = wallet_provider.ChainType.fromString("bitcoin");
    try testing.expect(chain_type == null);
}

test "ChainType.fromString - case sensitive" {
    const chain_type = wallet_provider.ChainType.fromString("Solana");
    try testing.expect(chain_type == null);
}

// Test WalletConfig structure
test "WalletConfig - local Solana configuration" {
    const config = wallet_provider.WalletConfig{
        .wallet_type = .local,
        .chain = .solana,
        .keypair_path = "/path/to/keypair.json",
        .network = "mainnet",
    };

    try testing.expectEqual(wallet_provider.WalletType.local, config.wallet_type);
    try testing.expectEqual(wallet_provider.ChainType.solana, config.chain);
    try testing.expect(config.keypair_path != null);
    try testing.expectEqualStrings("/path/to/keypair.json", config.keypair_path.?);
}

test "WalletConfig - local EVM configuration" {
    const config = wallet_provider.WalletConfig{
        .wallet_type = .local,
        .chain = .ethereum,
        .private_key = "0x1234567890abcdef",
        .network = "mainnet",
    };

    try testing.expectEqual(wallet_provider.WalletType.local, config.wallet_type);
    try testing.expectEqual(wallet_provider.ChainType.ethereum, config.chain);
    try testing.expect(config.private_key != null);
    try testing.expectEqualStrings("0x1234567890abcdef", config.private_key.?);
}

test "WalletConfig - Privy configuration" {
    const config = wallet_provider.WalletConfig{
        .wallet_type = .privy,
        .chain = .solana,
        .wallet_id = "privy-wallet-123",
        .network = "mainnet",
        .sponsor = true,
    };

    try testing.expectEqual(wallet_provider.WalletType.privy, config.wallet_type);
    try testing.expect(config.wallet_id != null);
    try testing.expectEqualStrings("privy-wallet-123", config.wallet_id.?);
    try testing.expectEqual(true, config.sponsor);
}

test "WalletConfig - default values" {
    const config = wallet_provider.WalletConfig{
        .wallet_type = .local,
        .chain = .solana,
    };

    try testing.expect(config.keypair_path == null);
    try testing.expect(config.private_key == null);
    try testing.expect(config.wallet_id == null);
    try testing.expectEqualStrings("mainnet", config.network);
    try testing.expectEqual(false, config.sponsor);
}

// Test SignResult structure
test "SignResult - with signature" {
    const result = wallet_provider.SignResult{
        .signed_transaction = "base64_encoded_tx",
        .signature = "signature_hash",
        .sent = true,
    };

    try testing.expectEqualStrings("base64_encoded_tx", result.signed_transaction);
    try testing.expect(result.signature != null);
    try testing.expectEqualStrings("signature_hash", result.signature.?);
    try testing.expectEqual(true, result.sent);
}

test "SignResult - without signature" {
    const result = wallet_provider.SignResult{
        .signed_transaction = "base64_encoded_tx",
        .sent = false,
    };

    try testing.expectEqualStrings("base64_encoded_tx", result.signed_transaction);
    try testing.expect(result.signature == null);
    try testing.expectEqual(false, result.sent);
}
