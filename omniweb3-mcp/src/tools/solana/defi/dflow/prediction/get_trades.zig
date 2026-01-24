const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");

/// Get paginated prediction market trades (dFlow).
///
/// Parameters:
/// - ticker: Market ticker (optional, filter by market)
/// - limit: Max trades to return (optional)
/// - cursor: Pagination cursor (optional)
/// - min_ts: Minimum timestamp (optional)
/// - max_ts: Maximum timestamp (optional)
///
/// Returns JSON with list of trades
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const ticker = mcp.tools.getString(args, "ticker");
    const limit = mcp.tools.getInteger(args, "limit");
    const cursor = mcp.tools.getString(args, "cursor");
    const min_ts = mcp.tools.getInteger(args, "min_ts");
    const max_ts = mcp.tools.getInteger(args, "max_ts");

    var url = std.fmt.allocPrint(allocator, "{s}", .{endpoints.dflow.pm_trades}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    var has_params = false;
    if (ticker) |t| {
        const new_url = std.fmt.allocPrint(allocator, "{s}?ticker={s}", .{ url, t }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        allocator.free(url);
        url = new_url;
        has_params = true;
    }
    if (limit) |l| {
        const sep: []const u8 = if (has_params) "&" else "?";
        const new_url = std.fmt.allocPrint(allocator, "{s}{s}limit={d}", .{ url, sep, l }) catch {
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
    if (min_ts) |ts| {
        const sep: []const u8 = if (has_params) "&" else "?";
        const new_url = std.fmt.allocPrint(allocator, "{s}{s}min_ts={d}", .{ url, sep, ts }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        allocator.free(url);
        url = new_url;
        has_params = true;
    }
    if (max_ts) |ts| {
        const sep: []const u8 = if (has_params) "&" else "?";
        const new_url = std.fmt.allocPrint(allocator, "{s}{s}max_ts={d}", .{ url, sep, ts }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        allocator.free(url);
        url = new_url;
    }

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow trades: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow trades response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        api: []const u8,
        trades: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .api = "prediction-market-metadata",
        .trades = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
