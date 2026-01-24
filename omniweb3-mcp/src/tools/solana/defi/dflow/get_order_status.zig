const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");

/// Get dFlow order status by transaction signature (Solana-only).
///
/// Check the status of a submitted dFlow order/swap.
///
/// Parameters:
/// - signature: Transaction signature to check (required)
///
/// Returns JSON with order status
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const signature = mcp.tools.getString(args, "signature") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: signature") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Build URL with query parameters
    const url = std.fmt.allocPrint(
        allocator,
        "{s}?signature={s}",
        .{ endpoints.dflow.order_status, signature },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow order status: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow order status response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        signature: []const u8,
        status: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .signature = signature,
        .status = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
