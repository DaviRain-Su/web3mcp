const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const process = std.process;

/// Get Jupiter tokens by category.
///
/// Parameters:
/// - category: Token category (e.g., "pump", "moonshot") (required)
/// - interval: Time interval (e.g., "5m", "1h", "6h", "24h") (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with tokens for the given category
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const category = mcp.tools.getString(args, "category") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: category") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const interval = mcp.tools.getString(args, "interval") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: interval") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.tokens_category;
    const api_key = mcp.tools.getString(args, "api_key");
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    const url = std.fmt.allocPrint(
        allocator,
        "{s}/{s}/{s}",
        .{ endpoint_base, category, interval },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = fetchHttp(allocator, url, api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get tokens by category: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        category: []const u8,
        interval: []const u8,
        tokens: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .category = category,
        .interval = interval,
        .tokens = parsed.value,
        .endpoint = endpoint_base,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn fetchHttp(allocator: std.mem.Allocator, url: []const u8, api_key: ?[]const u8, insecure: bool) ![]u8 {
    if (insecure) {
        return fetchViaCurl(allocator, url, api_key, true);
    }

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
    }) catch {
        return fetchViaCurl(allocator, url, api_key, false);
    };

    if (fetch_result.status.class() != .success) {
        return fetchViaCurl(allocator, url, api_key, false);
    }

    return out.toOwnedSlice();
}

fn fetchViaCurl(allocator: std.mem.Allocator, url: []const u8, api_key: ?[]const u8, insecure: bool) ![]u8 {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "curl");
    if (insecure) {
        try argv.append(allocator, "-k");
    }
    try argv.append(allocator, "-sL");

    var header_value: ?[]u8 = null;
    defer if (header_value) |value| allocator.free(value);

    if (api_key) |key| {
        try argv.append(allocator, "-H");
        header_value = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{key});
        try argv.append(allocator, header_value.?);
    }

    try argv.append(allocator, url);

    const result = try process.run(allocator, evm_runtime.io(), .{
        .argv = argv.items,
        .max_output_bytes = 2 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        allocator.free(result.stdout);
        return error.FetchFailed;
    }
    return result.stdout;
}
