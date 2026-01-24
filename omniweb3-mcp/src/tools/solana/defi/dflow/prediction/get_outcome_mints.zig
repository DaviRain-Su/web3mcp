const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");

/// Get all outcome mints from prediction markets (dFlow).
///
/// Returns a flat list of all yes_mint and no_mint pubkeys from all supported markets.
///
/// Parameters:
/// - min_close_ts: Minimum close timestamp to filter (optional)
///
/// Returns JSON with list of outcome mints
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const min_close_ts = mcp.tools.getInteger(args, "min_close_ts");

    const url = if (min_close_ts) |ts| blk: {
        break :blk std.fmt.allocPrint(allocator, "{s}?minCloseTs={d}", .{ endpoints.dflow.pm_outcome_mints, ts }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    } else blk: {
        break :blk std.fmt.allocPrint(allocator, "{s}", .{endpoints.dflow.pm_outcome_mints}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(url);

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow outcome mints: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow outcome mints response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        api: []const u8,
        outcome_mints: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .api = "prediction-market-metadata",
        .outcome_mints = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
