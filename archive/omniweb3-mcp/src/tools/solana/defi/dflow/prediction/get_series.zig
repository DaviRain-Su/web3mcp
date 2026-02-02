const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");

/// Get all prediction market series templates (dFlow).
///
/// A series represents a template for recurring events.
///
/// Parameters: None
///
/// Returns JSON with list of series
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    _ = args;

    const body = secure_http.dflowGet(allocator, endpoints.dflow.pm_series) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow series: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow series response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        api: []const u8,
        series: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .api = "prediction-market-metadata",
        .series = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
