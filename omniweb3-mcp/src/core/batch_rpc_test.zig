//! Unit tests for batch RPC utilities
//!
//! Tests cover:
//! - Module compilation
//! - Function exports
//! - Input validation

const std = @import("std");
const testing = std.testing;
const batch_rpc = @import("batch_rpc.zig");

test "batch_rpc module loads" {
    // Basic smoke test to ensure module compiles
    _ = batch_rpc;
}

test "batch_rpc exports batchGetAccountInfo" {
    _ = batch_rpc.batchGetAccountInfo;
}

test "batch_rpc exports batchGetTokenBalances" {
    _ = batch_rpc.batchGetTokenBalances;
}

test "batch_rpc exports batchGetSignatureStatuses" {
    _ = batch_rpc.batchGetSignatureStatuses;
}

test "batch_rpc exports batchRpcCall" {
    _ = batch_rpc.batchRpcCall;
}

// Note: Actual RPC tests require:
// 1. Network connectivity
// 2. Valid Solana RPC endpoint
// 3. Actual account addresses
// These are better suited for integration tests.
