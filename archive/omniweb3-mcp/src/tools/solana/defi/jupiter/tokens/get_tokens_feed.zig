const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const process = std.process;

/// Get paginated content feed for a specific token mint.
///
/// Parameters:
/// - mint: Base58 token mint address (required)
/// - page: Page number for pagination (optional, default: 1)
/// - limit: Number of items per page (optional, default: 20)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with paginated content feed
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const mint = mcp.tools.getString(args, "mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const page = mcp.tools.getInteger(args, "page") orelse 1;
    const limit = mcp.tools.getInteger(args, "limit") orelse 20;

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.tokens_content_feed;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    const url = std.fmt.allocPrint(allocator, "{s}/{s}?page={d}&limit={d}", .{ endpoint_base, mint, page, limit }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token content feed: {s}", .{@errorName(err)}) catch {
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
        mint: []const u8,
        page: i64,
        feed: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .mint = mint,
        .page = page,
        .feed = parsed.value,
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
