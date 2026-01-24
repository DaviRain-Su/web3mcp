const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Execute a signed Jupiter Ultra swap transaction.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
/// NEVER pass signed transactions as command-line arguments.
///
/// Parameters:
/// - signed_transaction: Base64-encoded signed transaction (required)
/// - request_id: Request ID from ultra_order response (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with execution result
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const signed_transaction = mcp.tools.getString(args, "signed_transaction") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: signed_transaction") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const request_id = mcp.tools.getString(args, "request_id") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: request_id") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.ultra_execute;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("signedTransaction", .{ .string = signed_transaction }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("requestId", .{ .string = request_id }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_override, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to execute Ultra swap: {s}", .{@errorName(err)}) catch {
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
        request_id: []const u8,
        result: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .request_id = request_id,
        .result = parsed.value,
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
