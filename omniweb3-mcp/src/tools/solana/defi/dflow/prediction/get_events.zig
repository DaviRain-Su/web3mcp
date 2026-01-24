const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");

/// Get paginated list of prediction market events (dFlow).
///
/// Parameters:
/// - limit: Max events to return (optional)
/// - cursor: Pagination cursor (optional)
/// - include_markets: Include nested markets (optional, default: false)
///
/// Returns JSON with list of events
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const limit = mcp.tools.getInteger(args, "limit");
    const cursor = mcp.tools.getString(args, "cursor");
    const include_markets = mcp.tools.getBoolean(args, "include_markets") orelse false;

    // Build URL
    var url = std.fmt.allocPrint(allocator, "{s}", .{endpoints.dflow.pm_events}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    var has_params = false;
    if (limit) |l| {
        const new_url = std.fmt.allocPrint(allocator, "{s}?limit={d}", .{ url, l }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        allocator.free(url);
        url = new_url;
        has_params = true;
    }
    if (cursor) |c| {
        const sep: []const u8 = if (has_params) "&" else "?";
        const new_url = std.fmt.allocPrint(allocator, "{s}{s}cursor={s}", .{ url, sep, c }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        allocator.free(url);
        url = new_url;
        has_params = true;
    }
    if (include_markets) {
        const sep: []const u8 = if (has_params) "&" else "?";
        const new_url = std.fmt.allocPrint(allocator, "{s}{s}includeMarkets=true", .{ url, sep }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        allocator.free(url);
        url = new_url;
    }

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow events: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow events response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        api: []const u8,
        events: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .api = "prediction-market-metadata",
        .events = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
