const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Search Jupiter tokens by symbol, name or mint address.
///
/// Parameters:
/// - query: Search query (symbol, name, or mint address) (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with matching tokens
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const query = mcp.tools.getString(args, "query") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: query") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.tokens_search;
    const use_api_key = true; // Always use API key from environment variable
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    // URL encode the query
    const encoded_query = urlEncode(allocator, query) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(encoded_query);

    const url = std.fmt.allocPrint(
        allocator,
        "{s}?query={s}",
        .{ endpoint_override, encoded_query },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to search tokens: {s}", .{@errorName(err)}) catch {
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
        query: []const u8,
        tokens: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .query = query,
        .tokens = parsed.value,
        .endpoint = endpoint_override,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;

    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(allocator, c);
        } else {
            const high: u4 = @truncate(c >> 4);
            const low: u4 = @truncate(c & 0x0F);
            try result.appendSlice(allocator, &[_]u8{ '%', hexDigit(high), hexDigit(low) });
        }
    }

    return result.toOwnedSlice(allocator);
}

fn hexDigit(n: u4) u8 {
    const val: u8 = n;
    return if (val < 10) '0' + val else 'A' + (val - 10);
}
