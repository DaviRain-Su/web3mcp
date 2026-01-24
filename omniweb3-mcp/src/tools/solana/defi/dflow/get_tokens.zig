const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");

/// Get list of supported tokens on dFlow (Solana-only).
///
/// Returns the list of tokens that dFlow supports for swapping.
///
/// Parameters: None
///
/// Returns JSON with list of supported tokens
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    _ = args;

    const body = secure_http.dflowGet(allocator, endpoints.dflow.tokens) catch |err| {
        const msg = if (err == error.ApiKeyRequired)
            "dFlow API requires authentication. Please set DFLOW_API_KEY environment variable. Get your API key at https://pond.dflow.net/quickstart/api-keys"
        else
            std.fmt.allocPrint(allocator, "Failed to fetch dFlow tokens: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow tokens response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        tokens: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .tokens = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
