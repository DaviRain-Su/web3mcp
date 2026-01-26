//! Unit tests for Solana helper functions
//!
//! Tests cover:
//! - Endpoint resolution
//! - PublicKey parsing
//! - Signature parsing
//! - Base64 encoding
//! - JSON stringification

const std = @import("std");
const testing = std.testing;
const helpers = @import("solana_helpers.zig");
const solana_sdk = @import("solana_sdk");

const PublicKey = solana_sdk.PublicKey;
const Signature = solana_sdk.Signature;

// Test endpoint resolution for all networks
test "resolveEndpoint - mainnet" {
    const endpoint = helpers.resolveEndpoint("mainnet");
    try testing.expect(std.mem.indexOf(u8, endpoint, "mainnet-beta") != null);
}

test "resolveEndpoint - devnet" {
    const endpoint = helpers.resolveEndpoint("devnet");
    try testing.expect(std.mem.indexOf(u8, endpoint, "devnet") != null);
}

test "resolveEndpoint - testnet" {
    const endpoint = helpers.resolveEndpoint("testnet");
    try testing.expect(std.mem.indexOf(u8, endpoint, "testnet") != null);
}

test "resolveEndpoint - localhost" {
    const endpoint = helpers.resolveEndpoint("localhost");
    try testing.expect(std.mem.indexOf(u8, endpoint, "localhost") != null);
    try testing.expect(std.mem.indexOf(u8, endpoint, "8899") != null);
}

test "resolveEndpoint - unknown network defaults to devnet" {
    const endpoint = helpers.resolveEndpoint("unknown");
    try testing.expect(std.mem.indexOf(u8, endpoint, "devnet") != null);
}

// Test PublicKey parsing
test "parsePublicKey - valid address" {
    // Well-known System Program address
    const system_program = "11111111111111111111111111111111";
    const pubkey = try helpers.parsePublicKey(system_program);

    // Verify it can be converted back to string
    var buf: [44]u8 = undefined;
    const str = pubkey.toBase58(&buf);
    try testing.expectEqualStrings(system_program, str);
}

test "parsePublicKey - valid Jupiter program address" {
    // Jupiter v6 program
    const jupiter_program = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";
    const pubkey = try helpers.parsePublicKey(jupiter_program);

    // Verify roundtrip
    var buf: [44]u8 = undefined;
    const str = pubkey.toBase58(&buf);
    try testing.expectEqualStrings(jupiter_program, str);
}

test "parsePublicKey - invalid address returns error" {
    const invalid_address = "not-a-valid-address";
    const result = helpers.parsePublicKey(invalid_address);
    try testing.expectError(error.Invalid, result);
}

test "parsePublicKey - empty address returns error" {
    const result = helpers.parsePublicKey("");
    try testing.expectError(error.Invalid, result);
}

// Test Signature parsing
test "parseSignature - valid signature" {
    // Use a real Solana signature (64 bytes encoded in base58, which is typically 87-88 chars)
    // This is a valid signature format from Solana blockchain
    const valid_sig = "5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW";
    const sig = try helpers.parseSignature(valid_sig);

    // Verify roundtrip
    var buf: [88]u8 = undefined;
    const str = sig.toBase58(&buf);
    try testing.expectEqualStrings(valid_sig, str);
}

test "parseSignature - invalid signature returns error" {
    const invalid_sig = "not-a-valid-signature";
    const result = helpers.parseSignature(invalid_sig);
    // Solana SDK returns InvalidBase58Digit for invalid characters
    try testing.expectError(error.InvalidBase58Digit, result);
}

// Test base64 encoding
test "base64EncodeAlloc - empty input" {
    const allocator = testing.allocator;
    const input: []const u8 = &.{};

    const encoded = try helpers.base64EncodeAlloc(allocator, input);
    defer allocator.free(encoded);

    try testing.expectEqual(@as(usize, 0), encoded.len);
}

test "base64EncodeAlloc - simple string" {
    const allocator = testing.allocator;
    const input = "Hello, World!";

    const encoded = try helpers.base64EncodeAlloc(allocator, input);
    defer allocator.free(encoded);

    // "Hello, World!" in base64 is "SGVsbG8sIFdvcmxkIQ=="
    try testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", encoded);
}

test "base64EncodeAlloc - binary data" {
    const allocator = testing.allocator;
    const input: []const u8 = &.{ 0x00, 0x01, 0x02, 0x03, 0xFF };

    const encoded = try helpers.base64EncodeAlloc(allocator, input);
    defer allocator.free(encoded);

    // Verify it's valid base64 (should decode back to original)
    try testing.expect(encoded.len > 0);

    // Base64 encoded should only contain valid characters
    for (encoded) |c| {
        const is_valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '+' or c == '/' or c == '=';
        try testing.expect(is_valid);
    }
}

test "base64EncodeAlloc - transaction-like data" {
    const allocator = testing.allocator;
    // Simulate a small transaction
    var tx_data: [64]u8 = undefined;
    for (&tx_data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    const encoded = try helpers.base64EncodeAlloc(allocator, &tx_data);
    defer allocator.free(encoded);

    // Verify encoded length is approximately 4/3 of input
    // Base64 encoding increases size by ~33%
    const expected_min = (tx_data.len * 4) / 3;
    try testing.expect(encoded.len >= expected_min);
}

// Test JSON stringification
test "jsonStringifyAlloc - simple object" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        value: u64,
    };

    const obj = TestStruct{
        .name = "test",
        .value = 42,
    };

    const json = try helpers.jsonStringifyAlloc(allocator, obj);
    defer allocator.free(json);

    // Verify contains key fields
    try testing.expect(std.mem.indexOf(u8, json, "name") != null);
    try testing.expect(std.mem.indexOf(u8, json, "test") != null);
    try testing.expect(std.mem.indexOf(u8, json, "value") != null);
    try testing.expect(std.mem.indexOf(u8, json, "42") != null);
}

test "jsonStringifyAlloc - nested object" {
    const allocator = testing.allocator;

    const Inner = struct {
        id: u32,
    };

    const Outer = struct {
        inner: Inner,
        flag: bool,
    };

    const obj = Outer{
        .inner = .{ .id = 123 },
        .flag = true,
    };

    const json = try helpers.jsonStringifyAlloc(allocator, obj);
    defer allocator.free(json);

    // Verify nested structure
    try testing.expect(std.mem.indexOf(u8, json, "inner") != null);
    try testing.expect(std.mem.indexOf(u8, json, "id") != null);
    try testing.expect(std.mem.indexOf(u8, json, "123") != null);
    try testing.expect(std.mem.indexOf(u8, json, "flag") != null);
    try testing.expect(std.mem.indexOf(u8, json, "true") != null);
}

test "jsonStringifyAlloc - optional fields null not emitted" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        required: u64,
        optional: ?[]const u8 = null,
    };

    const obj = TestStruct{
        .required = 100,
        .optional = null,
    };

    const json = try helpers.jsonStringifyAlloc(allocator, obj);
    defer allocator.free(json);

    // Verify null fields are not emitted (emit_null_optional_fields = false)
    try testing.expect(std.mem.indexOf(u8, json, "required") != null);
    try testing.expect(std.mem.indexOf(u8, json, "100") != null);
    // "optional" key should not appear
    try testing.expect(std.mem.indexOf(u8, json, "optional") == null);
}

test "jsonStringifyAlloc - array" {
    const allocator = testing.allocator;

    const arr = [_]u32{ 1, 2, 3, 4, 5 };

    const json = try helpers.jsonStringifyAlloc(allocator, arr);
    defer allocator.free(json);

    // Verify array format
    try testing.expect(std.mem.indexOf(u8, json, "[") != null);
    try testing.expect(std.mem.indexOf(u8, json, "]") != null);
    try testing.expect(std.mem.indexOf(u8, json, "1") != null);
    try testing.expect(std.mem.indexOf(u8, json, "5") != null);
}
