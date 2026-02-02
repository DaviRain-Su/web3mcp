const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");

/// Get live data for prediction market milestones (dFlow).
///
/// Relays live data from the Kalshi API for one or more milestones.
///
/// Parameters:
/// - milestones: Comma-separated list of milestones (required)
///
/// Returns JSON with live data
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const milestones = mcp.tools.getString(args, "milestones") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: milestones") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const url = std.fmt.allocPrint(allocator, "{s}?milestones={s}", .{ endpoints.dflow.pm_live_data, milestones }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow live data: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow live data response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        api: []const u8,
        live_data: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .api = "prediction-market-metadata",
        .live_data = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
