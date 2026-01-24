const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Create a Jupiter Send clawback transaction.
/// Allows reclaiming unclaimed sent tokens.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - sender: Base58 public key of the original sender wallet (required)
/// - invite_id: The invite ID to clawback (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with unsigned clawback transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const sender = mcp.tools.getString(args, "sender") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: sender") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const invite_id = mcp.tools.getString(args, "invite_id") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: invite_id") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.send_clawback;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("sender", .{ .string = sender }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("inviteId", .{ .string = invite_id }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_base, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create clawback transaction: {s}", .{@errorName(err)}) catch {
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
        sender: []const u8,
        invite_id: []const u8,
        transaction: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .sender = sender,
        .invite_id = invite_id,
        .transaction = parsed.value,
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
