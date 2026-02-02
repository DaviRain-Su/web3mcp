//! Unit tests for ABI resolver

const std = @import("std");
const testing = std.testing;
const abi_resolver = @import("abi_resolver.zig");

test "abi_resolver module loads" {
    _ = abi_resolver;
}

test "load contract metadata" {
    // Skip: requires filesystem access, better as integration test
    return error.SkipZigTest;
}

test "load WBNB ABI" {
    // Skip: requires filesystem access, better as integration test
    return error.SkipZigTest;
}

test "load PancakeSwap Router ABI" {
    // Skip: requires filesystem access, better as integration test
    return error.SkipZigTest;
}

test "resolve ABI path" {
    const allocator = testing.allocator;

    const path = try abi_resolver.resolveAbiPath(allocator, "bsc", "wbnb");
    defer allocator.free(path);

    try testing.expectEqualStrings("abi_registry/bsc/wbnb.json", path);
}

test "check ABI exists" {
    // Skip: requires filesystem access, better as integration test
    return error.SkipZigTest;
}
