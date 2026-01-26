//! Unit tests for chain adapter initialization
//!
//! Tests cover:
//! - Module exports and type checking

const std = @import("std");
const testing = std.testing;
const chain = @import("chain.zig");

// Note: Adapter initialization tests require network connectivity
// and are better suited for integration tests. These unit tests
// only verify that the module compiles and exports expected types.

test "chain module exports expected types" {
    // Verify module exports
    _ = chain.SolanaAdapter;
    _ = chain.EvmAdapter;
    _ = chain.initSolanaAdapter;
    _ = chain.initEvmAdapter;
}

test "chain module loads" {
    // Basic smoke test to ensure module compiles
    _ = chain;
}
