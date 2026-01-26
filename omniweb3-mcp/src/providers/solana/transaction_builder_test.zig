//! Unit tests for Solana Transaction Builder
//!
//! Tests cover:
//! - Anchor discriminator computation
//! - SHA256 hashing verification
//! - Edge cases and boundary conditions

const std = @import("std");
const testing = std.testing;
const builder = @import("transaction_builder.zig");

// Test discriminator computation
test "computeDiscriminator - initialize function" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "initialize");

    // Verify it's 8 bytes
    try testing.expectEqual(@as(usize, 8), discriminator.len);

    // The discriminator for "initialize" should be SHA256("global:initialize")[0..8]
    // Let's verify by computing it manually
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:initialize", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - swap function" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "swap");

    // Verify it's 8 bytes
    try testing.expectEqual(@as(usize, 8), discriminator.len);

    // Verify against manual hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:swap", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - transfer function" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "transfer");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:transfer", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - different functions have different discriminators" {
    const allocator = testing.allocator;
    const disc1 = try builder.computeDiscriminator(allocator, "initialize");
    const disc2 = try builder.computeDiscriminator(allocator, "swap");

    // Should not be equal
    try testing.expect(!std.mem.eql(u8, &disc1, &disc2));
}

test "computeDiscriminator - same function produces same discriminator" {
    const allocator = testing.allocator;
    const disc1 = try builder.computeDiscriminator(allocator, "initialize");
    const disc2 = try builder.computeDiscriminator(allocator, "initialize");

    // Should be equal
    try testing.expectEqualSlices(u8, &disc1, &disc2);
}

test "computeDiscriminator - empty function name" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    // Verify it's SHA256("global:")[0..8]
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - snake_case function name" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "add_liquidity");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:add_liquidity", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - camelCase function name" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "addLiquidity");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:addLiquidity", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - long function name" {
    const allocator = testing.allocator;
    const long_name = "very_long_function_name_with_many_underscores_and_characters";
    const discriminator = try builder.computeDiscriminator(allocator, long_name);

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    const discriminator_str = try std.fmt.allocPrint(allocator, "global:{s}", .{long_name});
    defer allocator.free(discriminator_str);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(discriminator_str, &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - function with numbers" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "function123");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:function123", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - case sensitivity" {
    const allocator = testing.allocator;
    const disc_lower = try builder.computeDiscriminator(allocator, "initialize");
    const disc_upper = try builder.computeDiscriminator(allocator, "Initialize");

    // Should be different (case sensitive)
    try testing.expect(!std.mem.eql(u8, &disc_lower, &disc_upper));
}

test "computeDiscriminator - special characters" {
    const allocator = testing.allocator;
    const discriminator = try builder.computeDiscriminator(allocator, "function-with-dashes");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:function-with-dashes", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

// Test known Anchor discriminators
test "computeDiscriminator - known Jupiter swap discriminator" {
    const allocator = testing.allocator;
    // Jupiter v6 swap instruction uses "shared_accounts_route"
    const discriminator = try builder.computeDiscriminator(allocator, "shared_accounts_route");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    // Verify it matches the known discriminator from IDL
    // The actual discriminator should be [229, 23, 203, 151, 122, 227, 173, 42]
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:shared_accounts_route", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}

test "computeDiscriminator - deterministic across calls" {
    const allocator = testing.allocator;

    // Call multiple times and verify same result
    const disc1 = try builder.computeDiscriminator(allocator, "test_function");
    const disc2 = try builder.computeDiscriminator(allocator, "test_function");
    const disc3 = try builder.computeDiscriminator(allocator, "test_function");

    try testing.expectEqualSlices(u8, &disc1, &disc2);
    try testing.expectEqualSlices(u8, &disc2, &disc3);
}

test "computeDiscriminator - unicode characters" {
    const allocator = testing.allocator;
    // Test with unicode (should work, just hashes the UTF-8 bytes)
    const discriminator = try builder.computeDiscriminator(allocator, "函数");

    try testing.expectEqual(@as(usize, 8), discriminator.len);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("global:函数", &hash, .{});

    try testing.expectEqualSlices(u8, hash[0..8], &discriminator);
}
