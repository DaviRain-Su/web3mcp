//! Privy List Users Tool
//!
//! Get all users in your Privy app with pagination.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// List all Privy users
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const cursor = mcp.tools.getString(args, "cursor");
    const limit = mcp.tools.getInteger(args, "limit");

    // Build path with query string
    const path = if (cursor != null and limit != null)
        std.fmt.allocPrint(allocator, "/users?cursor={s}&limit={d}", .{ cursor.?, limit.? })
    else if (cursor) |c|
        std.fmt.allocPrint(allocator, "/users?cursor={s}", .{c})
    else if (limit) |l|
        std.fmt.allocPrint(allocator, "/users?limit={d}", .{l})
    else
        std.fmt.allocPrint(allocator, "/users", .{});

    const path_str = path catch return mcp.tools.ToolError.OutOfMemory;
    defer allocator.free(path_str);

    // Make API request
    const response = client.privyGet(allocator, path_str) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Privy API error: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return client.errorResult(allocator, msg);
    };
    defer allocator.free(response);

    return client.jsonResult(allocator, response);
}
