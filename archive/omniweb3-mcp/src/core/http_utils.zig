//! Shared HTTP utilities for making API requests

const std = @import("std");
const evm_runtime = @import("evm_runtime.zig");

/// Fetch URL using Zig's HTTP client
/// Parameters:
/// - allocator: Memory allocator
/// - url: Full URL to fetch
/// - api_key: Optional API key (sent as x-api-key header)
/// - insecure: Whether to skip TLS verification (currently not implemented)
pub fn fetch(allocator: std.mem.Allocator, url: []const u8, api_key: ?[]const u8, insecure: bool) ![]u8 {
    _ = insecure; // TODO: implement insecure mode if needed

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    var headers: [1]std.http.Header = undefined;
    const extra_headers = if (api_key) |key| blk: {
        headers[0] = .{ .name = "x-api-key", .value = key };
        break :blk headers[0..1];
    } else &.{};

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &out.writer,
        .extra_headers = extra_headers,
    }) catch |err| {
        out.deinit();
        return err;
    };

    if (fetch_result.status.class() != .success) {
        out.deinit();
        return error.HttpError;
    }

    return out.toOwnedSlice();
}
