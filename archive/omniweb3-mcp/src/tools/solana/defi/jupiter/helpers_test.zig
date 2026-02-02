//! Unit tests for Jupiter helper functions
//!
//! Tests cover:
//! - extractTransactionBase64() - Extract transaction from JSON responses
//! - Error message helpers
//! - Transaction processing utilities

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

// Test extractTransactionBase64 with swapTransaction field
test "extractTransactionBase64 - swapTransaction field" {
    const allocator = testing.allocator;

    const json_str =
        \\{"swapTransaction":"dGVzdF90eF9kYXRh"}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result != null);
    try testing.expectEqualStrings("dGVzdF90eF9kYXRh", result.?);
}

// Test extractTransactionBase64 with direct transaction field
test "extractTransactionBase64 - transaction string field" {
    const allocator = testing.allocator;

    const json_str =
        \\{"transaction":"YW5vdGhlcl90eF9kYXRh"}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result != null);
    try testing.expectEqualStrings("YW5vdGhlcl90eF9kYXRh", result.?);
}

// Test extractTransactionBase64 with nested transaction object
test "extractTransactionBase64 - nested transaction object" {
    const allocator = testing.allocator;

    const json_str =
        \\{"transaction":{"transaction":"bmVzdGVkX3R4X2RhdGE="}}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result != null);
    try testing.expectEqualStrings("bmVzdGVkX3R4X2RhdGE=", result.?);
}

// Test extractTransactionBase64 with serializedTransaction in nested object
test "extractTransactionBase64 - nested serializedTransaction" {
    const allocator = testing.allocator;

    const json_str =
        \\{"transaction":{"serializedTransaction":"c2VyaWFsaXplZF90eA=="}}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result != null);
    try testing.expectEqualStrings("c2VyaWFsaXplZF90eA==", result.?);
}

// Test extractTransactionBase64 with data wrapper
test "extractTransactionBase64 - data.transaction field" {
    const allocator = testing.allocator;

    const json_str =
        \\{"data":{"transaction":"ZGF0YV90eF9kYXRh"}}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result != null);
    try testing.expectEqualStrings("ZGF0YV90eF9kYXRh", result.?);
}

// Test extractTransactionBase64 with data.serializedTransaction
test "extractTransactionBase64 - data.serializedTransaction field" {
    const allocator = testing.allocator;

    const json_str =
        \\{"data":{"serializedTransaction":"ZGF0YV9zZXJpYWxpemVk"}}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result != null);
    try testing.expectEqualStrings("ZGF0YV9zZXJpYWxpemVk", result.?);
}

// Test extractTransactionBase64 with no transaction field
test "extractTransactionBase64 - missing transaction" {
    const allocator = testing.allocator;

    const json_str =
        \\{"someOtherField":"value"}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result == null);
}

// Test extractTransactionBase64 with non-object value
test "extractTransactionBase64 - non-object value" {
    const allocator = testing.allocator;

    const json_str =
        \\"just a string"
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const result = helpers.extractTransactionBase64(parsed.value);
    try testing.expect(result == null);
}

// Test userResolveErrorMessage
test "userResolveErrorMessage - all error types" {
    const msg1 = helpers.userResolveErrorMessage(error.MissingUser);
    try testing.expect(std.mem.indexOf(u8, msg1, "Missing required parameter") != null);

    const msg2 = helpers.userResolveErrorMessage(error.InvalidWalletType);
    try testing.expect(std.mem.indexOf(u8, msg2, "Invalid wallet_type") != null);

    const msg3 = helpers.userResolveErrorMessage(error.MissingWalletId);
    try testing.expect(std.mem.indexOf(u8, msg3, "wallet_id is required") != null);

    const msg4 = helpers.userResolveErrorMessage(error.PrivyNotConfigured);
    try testing.expect(std.mem.indexOf(u8, msg4, "Privy not configured") != null);

    const msg5 = helpers.userResolveErrorMessage(error.OutOfMemory);
    try testing.expect(std.mem.indexOf(u8, msg5, "Failed to resolve") != null);
}

// Test signErrorMessage
test "signErrorMessage - all error types" {
    const msg1 = helpers.signErrorMessage(error.InvalidWalletType);
    try testing.expect(std.mem.indexOf(u8, msg1, "Invalid wallet_type") != null);

    const msg2 = helpers.signErrorMessage(error.MissingWalletId);
    try testing.expect(std.mem.indexOf(u8, msg2, "wallet_id is required") != null);

    const msg3 = helpers.signErrorMessage(error.PrivyNotConfigured);
    try testing.expect(std.mem.indexOf(u8, msg3, "Privy not configured") != null);

    const msg4 = helpers.signErrorMessage(error.LocalSignAndSendNotImplemented);
    try testing.expect(std.mem.indexOf(u8, msg4, "Local wallet sign+send not yet implemented") != null);

    const msg5 = helpers.signErrorMessage(error.LocalSigningNotImplemented);
    try testing.expect(std.mem.indexOf(u8, msg5, "Local wallet signing not yet implemented") != null);

    const msg6 = helpers.signErrorMessage(error.OutOfMemory);
    try testing.expect(std.mem.indexOf(u8, msg6, "Failed to sign") != null);
}
