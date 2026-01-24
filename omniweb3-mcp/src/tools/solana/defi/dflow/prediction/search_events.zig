const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");

/// Search prediction market events (dFlow).
///
/// Returns events with nested markets which match the search query.
///
/// Parameters:
/// - query: Search query (required)
/// - limit: Max results to return (optional)
///
/// Returns JSON with matching events
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const query = mcp.tools.getString(args, "query") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: query") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const limit = mcp.tools.getInteger(args, "limit");

    const url = if (limit) |l| blk: {
        break :blk std.fmt.allocPrint(allocator, "{s}?query={s}&limit={d}", .{ endpoints.dflow.pm_search, query, l }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    } else blk: {
        break :blk std.fmt.allocPrint(allocator, "{s}?query={s}", .{ endpoints.dflow.pm_search, query }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(url);

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to search dFlow events: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow search response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        api: []const u8,
        query: []const u8,
        results: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .api = "prediction-market-metadata",
        .query = query,
        .results = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
