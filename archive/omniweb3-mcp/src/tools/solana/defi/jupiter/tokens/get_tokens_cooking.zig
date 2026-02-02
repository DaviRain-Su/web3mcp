const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const process = std.process;

/// Get approved content for currently trending (cooking) tokens on Jupiter.
///
/// Parameters:
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with trending token content
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.tokens_content_cooking;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    const body = secure_http.secureGet(allocator, endpoint_base, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get trending token content: {s}", .{@errorName(err)}) catch {
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
        trending: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .trending = parsed.value,
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
