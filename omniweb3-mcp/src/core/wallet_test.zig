//! Unit tests for wallet utilities
//!
//! Tests cover:
//! - Error handling for invalid keys
//! - EVM address derivation

const std = @import("std");
const testing = std.testing;
const wallet = @import("wallet.zig");

// Note: File system tests (loadSolanaKeypair) are skipped because they
// require actual file access which may not be reliable in test environment

test "loadEvmPrivateKey - invalid hex returns error" {
    const allocator = testing.allocator;

    // Invalid private key (not valid hex)
    const invalid_key = "not-a-valid-private-key";
    const result = wallet.loadEvmPrivateKey(allocator, invalid_key, null);

    // Should return an error
    try testing.expect(std.meta.isError(result));
}

test "loadEvmPrivateKey - short key returns error" {
    const allocator = testing.allocator;

    // Too short to be a valid private key
    const short_key = "0x1234";
    const result = wallet.loadEvmPrivateKey(allocator, short_key, null);

    // Should return an error
    try testing.expect(std.meta.isError(result));
}

test "deriveEvmAddress - valid test key" {
    // Use a valid non-zero, non-trivial private key
    // This is a randomly generated test key (not for real use)
    const test_key: [32]u8 = .{
        0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x11, 0x22,
        0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa,
        0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x11, 0x22, 0x33,
        0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb,
    };

    const address = try wallet.deriveEvmAddress(test_key);

    // Address should be 20 bytes
    try testing.expectEqual(@as(usize, 20), address.len);

    // Address should not be all zeros
    var is_all_zero = true;
    for (address) |b| {
        if (b != 0) {
            is_all_zero = false;
            break;
        }
    }
    try testing.expect(!is_all_zero);
}

test "deriveEvmAddress - deterministic" {
    // Same key should always produce same address
    const test_key: [32]u8 = .{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x11,
        0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99,
        0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x11, 0x22,
    };

    const address1 = try wallet.deriveEvmAddress(test_key);
    const address2 = try wallet.deriveEvmAddress(test_key);

    // Both addresses should be identical
    try testing.expectEqualSlices(u8, &address1, &address2);
}

test "deriveEvmAddress - different keys produce different addresses" {
    const key1: [32]u8 = .{
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    };

    const key2: [32]u8 = .{
        0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
        0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
        0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
        0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
    };

    const address1 = try wallet.deriveEvmAddress(key1);
    const address2 = try wallet.deriveEvmAddress(key2);

    // Addresses should be different
    try testing.expect(!std.mem.eql(u8, &address1, &address2));
}
