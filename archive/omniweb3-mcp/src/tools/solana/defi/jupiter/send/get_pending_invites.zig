const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const process = std.process;

/// Get pending Jupiter Send invites for an address.
///
/// Parameters:
/// - address: Base58 public key to check pending invites for (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with pending invites
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const address = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.send_pending;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    const url = std.fmt.allocPrint(allocator, "{s}?address={s}", .{ endpoint_base, address }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get pending invites: {s}", .{@errorName(err)}) catch {
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
        address: []const u8,
        pending_invites: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .address = address,
        .pending_invites = parsed.value,
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
