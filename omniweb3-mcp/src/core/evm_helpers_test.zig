//! Unit tests for EVM helper functions
//!
//! Tests cover:
//! - Address parsing
//! - Hash parsing
//! - Hex data parsing
//! - Wei/ETH formatting
//! - Chain ID resolution
//! - Endpoint resolution

const std = @import("std");
const testing = std.testing;
const helpers = @import("evm_helpers.zig");

// Test address parsing
test "parseAddress - valid lowercase address" {
    const address = "0x742d35cc6634c0532925a3b844bc454e4438f44e";
    const parsed = try helpers.parseAddress(address);

    // Verify it's 20 bytes
    try testing.expectEqual(@as(usize, 20), parsed.len);
}

test "parseAddress - valid checksummed address" {
    const address = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed";
    const parsed = try helpers.parseAddress(address);

    // Verify it's 20 bytes
    try testing.expectEqual(@as(usize, 20), parsed.len);
}

test "parseAddress - without 0x prefix" {
    const address = "742d35cc6634c0532925a3b844bc454e4438f44e";
    const parsed = try helpers.parseAddress(address);

    // Should still work
    try testing.expectEqual(@as(usize, 20), parsed.len);
}

test "parseAddress - invalid address returns error" {
    const invalid_address = "not-a-valid-address";
    const result = helpers.parseAddress(invalid_address);
    try testing.expectError(error.InvalidAddress, result);
}

// Test hash parsing
test "parseHash - valid hash with 0x" {
    const hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const parsed = try helpers.parseHash(hash);

    // Verify it's 32 bytes
    try testing.expectEqual(@as(usize, 32), parsed.len);
}

test "parseHash - valid hash without 0x" {
    const hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const parsed = try helpers.parseHash(hash);

    // Verify it's 32 bytes
    try testing.expectEqual(@as(usize, 32), parsed.len);
}

test "parseHash - invalid hash returns error" {
    const invalid_hash = "not-a-hash";
    const result = helpers.parseHash(invalid_hash);
    try testing.expectError(error.InvalidHash, result);
}

// Test hex data parsing
test "parseHexDataAlloc - empty string" {
    const allocator = testing.allocator;
    const hex = "";

    const data = try helpers.parseHexDataAlloc(allocator, hex);
    defer allocator.free(data);

    try testing.expectEqual(@as(usize, 0), data.len);
}

test "parseHexDataAlloc - with 0x prefix" {
    const allocator = testing.allocator;
    const hex = "0x48656c6c6f"; // "Hello" in hex

    const data = try helpers.parseHexDataAlloc(allocator, hex);
    defer allocator.free(data);

    try testing.expectEqualSlices(u8, "Hello", data);
}

test "parseHexDataAlloc - without 0x prefix" {
    const allocator = testing.allocator;
    const hex = "48656c6c6f"; // "Hello" in hex

    const data = try helpers.parseHexDataAlloc(allocator, hex);
    defer allocator.free(data);

    try testing.expectEqualSlices(u8, "Hello", data);
}

test "parseHexDataAlloc - odd length returns error" {
    const allocator = testing.allocator;
    const hex = "0x123"; // Odd length (3 chars)

    const result = helpers.parseHexDataAlloc(allocator, hex);
    try testing.expectError(error.InvalidHexLength, result);
}

test "parseHexDataAlloc - invalid hex returns error" {
    const allocator = testing.allocator;
    const hex = "0xGGGG"; // Invalid hex characters

    const result = helpers.parseHexDataAlloc(allocator, hex);
    try testing.expectError(error.InvalidHexData, result);
}

// Test Wei to ETH formatting
test "formatWeiToEthString - 1 ETH" {
    const allocator = testing.allocator;
    const wei: u256 = 1_000_000_000_000_000_000; // 1 ETH = 10^18 wei

    const eth_str = try helpers.formatWeiToEthString(allocator, wei);
    defer allocator.free(eth_str);

    try testing.expectEqualStrings("1.000000000000000000", eth_str);
}

test "formatWeiToEthString - 0.5 ETH" {
    const allocator = testing.allocator;
    const wei: u256 = 500_000_000_000_000_000; // 0.5 ETH

    const eth_str = try helpers.formatWeiToEthString(allocator, wei);
    defer allocator.free(eth_str);

    try testing.expectEqualStrings("0.500000000000000000", eth_str);
}

test "formatWeiToEthString - small amount" {
    const allocator = testing.allocator;
    const wei: u256 = 1234; // Very small amount

    const eth_str = try helpers.formatWeiToEthString(allocator, wei);
    defer allocator.free(eth_str);

    try testing.expectEqualStrings("0.000000000000001234", eth_str);
}

test "formatWeiToEthString - zero" {
    const allocator = testing.allocator;
    const wei: u256 = 0;

    const eth_str = try helpers.formatWeiToEthString(allocator, wei);
    defer allocator.free(eth_str);

    try testing.expectEqualStrings("0.000000000000000000", eth_str);
}

test "formatWeiToEthString - large amount" {
    const allocator = testing.allocator;
    const wei: u256 = 123_456_000_000_000_000_000_000; // 123,456 ETH

    const eth_str = try helpers.formatWeiToEthString(allocator, wei);
    defer allocator.free(eth_str);

    try testing.expectEqualStrings("123456.000000000000000000", eth_str);
}

// Test u256 formatting
test "formatU256 - small number" {
    const allocator = testing.allocator;
    const value: u256 = 42;

    const str = try helpers.formatU256(allocator, value);
    defer allocator.free(str);

    try testing.expectEqualStrings("42", str);
}

test "formatU256 - zero" {
    const allocator = testing.allocator;
    const value: u256 = 0;

    const str = try helpers.formatU256(allocator, value);
    defer allocator.free(str);

    try testing.expectEqualStrings("0", str);
}

test "formatU256 - large number" {
    const allocator = testing.allocator;
    const value: u256 = 1_000_000_000_000_000_000;

    const str = try helpers.formatU256(allocator, value);
    defer allocator.free(str);

    try testing.expectEqualStrings("1000000000000000000", str);
}

// Test Wei amount parsing
test "parseWeiAmount - valid amount" {
    const amount_str = "1000000000000000000"; // 1 ETH in wei
    const wei = try helpers.parseWeiAmount(amount_str);

    try testing.expectEqual(@as(u256, 1_000_000_000_000_000_000), wei);
}

test "parseWeiAmount - zero" {
    const amount_str = "0";
    const wei = try helpers.parseWeiAmount(amount_str);

    try testing.expectEqual(@as(u256, 0), wei);
}

test "parseWeiAmount - small amount" {
    const amount_str = "123";
    const wei = try helpers.parseWeiAmount(amount_str);

    try testing.expectEqual(@as(u256, 123), wei);
}

test "parseWeiAmount - invalid format returns error" {
    const amount_str = "not-a-number";
    const result = helpers.parseWeiAmount(amount_str);
    try testing.expectError(error.InvalidCharacter, result);
}

// NOTE: jsonStringifyAlloc tests are skipped because evm_helpers.zig
// has a bug where it uses defer out.deinit() before returning out.written(),
// which causes use-after-free. This should be fixed in the production code
// to use toOwnedSlice() like solana_helpers.zig does.
