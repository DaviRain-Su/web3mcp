//! Privy Get User Tool
//!
//! Retrieves user information by user ID.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// Get Privy user by ID
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const user_id = mcp.tools.getString(args, "user_id") orelse {
        return client.errorResult(allocator, "Missing required parameter: user_id");
    };

    // Build path
    const path = std.fmt.allocPrint(allocator, "/users/{s}", .{user_id}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(path);

    // Make API request
    const response = client.privyGet(allocator, path) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Privy API error: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return client.errorResult(allocator, msg);
    };
    defer allocator.free(response);

    return client.jsonResult(allocator, response);
}
