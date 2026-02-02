//! Batch RPC Utilities
//!
//! Optimize Solana RPC calls by batching multiple requests into a single
//! HTTP request. This significantly reduces network latency and improves
//! performance for operations that need to query multiple accounts.
//!
//! Benefits:
//! - Reduce network round trips from N to 1
//! - Lower latency (100 queries: ~50s → ~500ms)
//! - Reduce RPC node load
//! - More efficient resource usage

const std = @import("std");
const solana_sdk = @import("solana_sdk");
const endpoints = @import("endpoints.zig");
const solana_helpers = @import("solana_helpers.zig");
const evm_runtime = @import("evm_runtime.zig");

const PublicKey = solana_sdk.PublicKey;

/// Batch get account info for multiple addresses
///
/// Instead of making N individual getAccountInfo calls, this makes a single
/// batch request. Maximum 100 accounts per batch (Solana RPC limit).
///
/// Parameters:
/// - allocator: Memory allocator
/// - addresses: Array of base58 public keys (max 100)
/// - network: Network name (mainnet/devnet/testnet)
/// - endpoint: Optional custom RPC endpoint
///
/// Returns: JSON string with array of account info results
pub fn batchGetAccountInfo(
    allocator: std.mem.Allocator,
    addresses: []const []const u8,
    network: []const u8,
    endpoint: ?[]const u8,
) ![]u8 {
    if (addresses.len == 0) {
        return error.EmptyAddressList;
    }

    if (addresses.len > 100) {
        return error.TooManyAccounts; // Solana RPC batch limit
    }

    const rpc_url = endpoint orelse endpoints.solana.resolve(network);

    // Build batch JSON-RPC request
    var batch_array = std.json.Array.init(allocator);
    defer batch_array.deinit();

    for (addresses, 0..) |address, i| {
        var request = std.json.ObjectMap.init(allocator);

        try request.put("jsonrpc", .{ .string = "2.0" });
        try request.put("id", .{ .integer = @intCast(i) });
        try request.put("method", .{ .string = "getAccountInfo" });

        var params = std.json.Array.init(allocator);
        try params.append(.{ .string = address });

        // Options
        var options = std.json.ObjectMap.init(allocator);
        try options.put("encoding", .{ .string = "base64" });
        try params.append(.{ .object = options });

        try request.put("params", .{ .array = params });

        try batch_array.append(.{ .object = request });
    }

    const request_body = try solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .array = batch_array });
    defer allocator.free(request_body);

    // Send batch request using HTTP POST
    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = rpc_url },
        .method = .POST,
        .payload = request_body,
        .response_writer = &out.writer,
        .extra_headers = &headers,
    }) catch {
        out.deinit();
        return error.FetchFailed;
    };

    if (fetch_result.status.class() != .success) {
        out.deinit();
        return error.FetchFailed;
    }

    return out.toOwnedSlice();
}

/// Batch get multiple token balances for an owner
///
/// Queries balances for multiple SPL tokens in a single batch request.
///
/// Parameters:
/// - allocator: Memory allocator
/// - owner: Owner public key (base58)
/// - mints: Array of token mint addresses (max 100)
/// - network: Network name
/// - endpoint: Optional custom RPC endpoint
///
/// Returns: JSON string with array of token balance results
pub fn batchGetTokenBalances(
    allocator: std.mem.Allocator,
    owner: []const u8,
    mints: []const []const u8,
    network: []const u8,
    endpoint: ?[]const u8,
) ![]u8 {
    if (mints.len == 0) {
        return error.EmptyMintsList;
    }

    if (mints.len > 100) {
        return error.TooManyMints;
    }

    const rpc_url = endpoint orelse endpoints.solana.resolve(network);

    // Build batch request for getTokenAccountsByOwner
    var batch_array = std.json.Array.init(allocator);
    defer batch_array.deinit();

    for (mints, 0..) |mint, i| {
        var request = std.json.ObjectMap.init(allocator);

        try request.put("jsonrpc", .{ .string = "2.0" });
        try request.put("id", .{ .integer = @intCast(i) });
        try request.put("method", .{ .string = "getTokenAccountsByOwner" });

        var params = std.json.Array.init(allocator);
        try params.append(.{ .string = owner });

        // Filter by mint
        var filter = std.json.ObjectMap.init(allocator);
        try filter.put("mint", .{ .string = mint });
        try params.append(.{ .object = filter });

        // Options
        var options = std.json.ObjectMap.init(allocator);
        try options.put("encoding", .{ .string = "jsonParsed" });
        try params.append(.{ .object = options });

        try request.put("params", .{ .array = params });

        try batch_array.append(.{ .object = request });
    }

    const request_body = try solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .array = batch_array });
    defer allocator.free(request_body);

    // Send batch request using HTTP POST
    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = rpc_url },
        .method = .POST,
        .payload = request_body,
        .response_writer = &out.writer,
        .extra_headers = &headers,
    }) catch {
        out.deinit();
        return error.FetchFailed;
    };

    if (fetch_result.status.class() != .success) {
        out.deinit();
        return error.FetchFailed;
    }

    return out.toOwnedSlice();
}

/// Batch get signature statuses
///
/// Check the status of multiple transactions in a single request.
///
/// Parameters:
/// - allocator: Memory allocator
/// - signatures: Array of transaction signatures (max 256)
/// - network: Network name
/// - endpoint: Optional custom RPC endpoint
///
/// Returns: JSON string with array of signature status results
pub fn batchGetSignatureStatuses(
    allocator: std.mem.Allocator,
    signatures: []const []const u8,
    network: []const u8,
    endpoint: ?[]const u8,
) ![]u8 {
    if (signatures.len == 0) {
        return error.EmptySignaturesList;
    }

    if (signatures.len > 256) {
        return error.TooManySignatures; // Solana RPC limit for getSignatureStatuses
    }

    const rpc_url = endpoint orelse endpoints.solana.resolve(network);

    // getSignatureStatuses accepts multiple signatures in a single call
    var request = std.json.ObjectMap.init(allocator);
    defer request.deinit();

    try request.put("jsonrpc", .{ .string = "2.0" });
    try request.put("id", .{ .integer = 1 });
    try request.put("method", .{ .string = "getSignatureStatuses" });

    var params = std.json.Array.init(allocator);

    // Array of signatures
    var sigs_array = std.json.Array.init(allocator);
    for (signatures) |sig| {
        try sigs_array.append(.{ .string = sig });
    }
    try params.append(.{ .array = sigs_array });

    // Options
    var options = std.json.ObjectMap.init(allocator);
    try options.put("searchTransactionHistory", .{ .bool = true });
    try params.append(.{ .object = options });

    try request.put("params", .{ .array = params });

    const request_body = try solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request });
    defer allocator.free(request_body);

    // Send batch request using HTTP POST
    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = rpc_url },
        .method = .POST,
        .payload = request_body,
        .response_writer = &out.writer,
        .extra_headers = &headers,
    }) catch {
        out.deinit();
        return error.FetchFailed;
    };

    if (fetch_result.status.class() != .success) {
        out.deinit();
        return error.FetchFailed;
    }

    return out.toOwnedSlice();
}

/// Batch get multiple accounts (generic version)
///
/// Query multiple accounts with custom RPC methods in a single batch.
///
/// Parameters:
/// - allocator: Memory allocator
/// - requests: Array of RPC request objects
/// - network: Network name
/// - endpoint: Optional custom RPC endpoint
///
/// Returns: JSON string with array of results
pub fn batchRpcCall(
    allocator: std.mem.Allocator,
    requests: []const std.json.Value,
    network: []const u8,
    endpoint: ?[]const u8,
) ![]u8 {
    if (requests.len == 0) {
        return error.EmptyRequestsList;
    }

    if (requests.len > 100) {
        return error.TooManyRequests;
    }

    const rpc_url = endpoint orelse endpoints.solana.resolve(network);

    // Build batch array from requests
    var batch_array = std.json.Array.init(allocator);
    defer batch_array.deinit();

    for (requests, 0..) |req, i| {
        if (req != .object) {
            return error.InvalidRequestFormat;
        }

        var request = std.json.ObjectMap.init(allocator);

        try request.put("jsonrpc", .{ .string = "2.0" });
        try request.put("id", .{ .integer = @intCast(i) });

        // Copy method and params from input
        if (req.object.get("method")) |method| {
            try request.put("method", method);
        } else {
            return error.MissingMethod;
        }

        if (req.object.get("params")) |params| {
            try request.put("params", params);
        }

        try batch_array.append(.{ .object = request });
    }

    const request_body = try solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .array = batch_array });
    defer allocator.free(request_body);

    // Send batch request using HTTP POST
    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = rpc_url },
        .method = .POST,
        .payload = request_body,
        .response_writer = &out.writer,
        .extra_headers = &headers,
    }) catch {
        out.deinit();
        return error.FetchFailed;
    };

    if (fetch_result.status.class() != .success) {
        out.deinit();
        return error.FetchFailed;
    }

    return out.toOwnedSlice();
}
