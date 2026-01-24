const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Batch cancel Jupiter trigger (limit) orders.
/// Returns unsigned transactions for canceling multiple orders.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - maker: Base58 public key of the maker wallet (required)
/// - orders: Array of Base58 order account addresses to cancel (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with cancel transactions
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const maker = mcp.tools.getString(args, "maker") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: maker") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Get orders array
    const orders_value = if (args) |a| switch (a) {
        .object => |obj| obj.get("orders"),
        else => null,
    } else null;

    if (orders_value == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: orders (array of order addresses)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.trigger_cancel_batch;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("maker", .{ .string = maker }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("orders", orders_value.?) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_base, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to cancel trigger orders: {s}", .{@errorName(err)}) catch {
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
        maker: []const u8,
        result: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .maker = maker,
        .result = parsed.value,
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
