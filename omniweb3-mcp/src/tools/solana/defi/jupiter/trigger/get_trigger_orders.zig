const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Get Jupiter trigger (limit) orders for a Solana account.
///
/// Parameters:
/// - account: Base58 Solana account address (required)
/// - status: Order status filter: "active" or "history" (optional, default: active)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with trigger orders
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const account = mcp.tools.getString(args, "account") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: account") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const status = mcp.tools.getString(args, "status") orelse "active";
    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.trigger_orders;
    const use_api_key = true; // Always use API key from environment variable
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    const url = std.fmt.allocPrint(
        allocator,
        "{s}?user={s}&status={s}",
        .{ endpoint_override, account, status },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get trigger orders: {s}", .{@errorName(err)}) catch {
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
        account: []const u8,
        status: []const u8,
        orders: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .account = account,
        .status = status,
        .orders = parsed.value,
        .endpoint = endpoint_override,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

