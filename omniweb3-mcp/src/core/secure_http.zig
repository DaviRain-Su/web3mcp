const std = @import("std");
const evm_runtime = @import("evm_runtime.zig");

/// Secure HTTP client using native Zig std.http.Client.
/// - Reads API key from JUPITER_API_KEY environment variable (never from user input)
/// - No external dependencies (no curl)
/// - No temp files, no process list exposure
/// Get Jupiter API key from environment variable.
/// Returns null if not set.
pub fn getJupiterApiKey() ?[]const u8 {
    const result = std.c.getenv("JUPITER_API_KEY");
    if (result) |ptr| {
        return std.mem.span(ptr);
    }
    return null;
}

/// Get dFlow API key from environment variable.
/// Returns null if not set.
pub fn getDflowApiKey() ?[]const u8 {
    const result = std.c.getenv("DFLOW_API_KEY");
    if (result) |ptr| {
        return std.mem.span(ptr);
    }
    return null;
}

/// Secure POST request using native Zig HTTP client.
pub fn securePost(
    allocator: std.mem.Allocator,
    url: []const u8,
    body: []const u8,
    use_api_key: bool,
    insecure: bool,
) ![]u8 {
    _ = insecure; // Native Zig HTTP handles TLS automatically

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    // Build headers: Content-Type + optional x-api-key
    var headers: [2]std.http.Header = undefined;
    var header_count: usize = 0;

    headers[header_count] = .{ .name = "Content-Type", .value = "application/json" };
    header_count += 1;

    if (use_api_key) {
        if (getJupiterApiKey()) |key| {
            headers[header_count] = .{ .name = "x-api-key", .value = key };
            header_count += 1;
        }
    }

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .response_writer = &out.writer,
        .extra_headers = headers[0..header_count],
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

/// Secure GET request using native Zig HTTP client.
pub fn secureGet(
    allocator: std.mem.Allocator,
    url: []const u8,
    use_api_key: bool,
    insecure: bool,
) ![]u8 {
    _ = insecure; // Native Zig HTTP handles TLS automatically

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    // Build headers: optional x-api-key
    var headers: [1]std.http.Header = undefined;
    const extra_headers = if (use_api_key) blk: {
        if (getJupiterApiKey()) |key| {
            headers[0] = .{ .name = "x-api-key", .value = key };
            break :blk headers[0..1];
        }
        break :blk headers[0..0];
    } else headers[0..0];

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &out.writer,
        .extra_headers = extra_headers,
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

/// Secure GET request for dFlow API using native Zig HTTP client.
/// Returns error.ApiKeyRequired if DFLOW_API_KEY environment variable is not set.
pub fn dflowGet(
    allocator: std.mem.Allocator,
    url: []const u8,
) ![]u8 {
    const api_key = getDflowApiKey() orelse return error.ApiKeyRequired;

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    // Build headers: x-api-key for dFlow (required)
    var headers: [1]std.http.Header = .{
        .{ .name = "x-api-key", .value = api_key },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
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

/// Secure POST request for dFlow API using native Zig HTTP client.
/// Returns error.ApiKeyRequired if DFLOW_API_KEY environment variable is not set.
pub fn dflowPost(
    allocator: std.mem.Allocator,
    url: []const u8,
    body: []const u8,
) ![]u8 {
    const api_key = getDflowApiKey() orelse return error.ApiKeyRequired;

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    // Build headers: Content-Type + x-api-key for dFlow (required)
    var headers: [2]std.http.Header = .{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "x-api-key", .value = api_key },
    };

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
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
