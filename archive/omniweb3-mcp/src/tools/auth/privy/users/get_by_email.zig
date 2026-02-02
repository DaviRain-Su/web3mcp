//! Privy Get User by Email Tool
//!
//! Looks up a user by their email address.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// URL encode a string (simple encoding for @ and +)
fn urlEncodeEmail(allocator: std.mem.Allocator, email: []const u8) ![]u8 {
    // Count how many extra chars we need
    var extra: usize = 0;
    for (email) |c| {
        if (c == '@' or c == '+') extra += 2; // %40 or %2B = 3 chars instead of 1
    }

    const result = try allocator.alloc(u8, email.len + extra);
    var i: usize = 0;
    for (email) |c| {
        if (c == '@') {
            result[i] = '%';
            result[i + 1] = '4';
            result[i + 2] = '0';
            i += 3;
        } else if (c == '+') {
            result[i] = '%';
            result[i + 1] = '2';
            result[i + 2] = 'B';
            i += 3;
        } else {
            result[i] = c;
            i += 1;
        }
    }
    return result;
}

/// Get Privy user by email address
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const email = mcp.tools.getString(args, "email") orelse {
        return client.errorResult(allocator, "Missing required parameter: email");
    };

    // URL encode email
    const encoded_email = urlEncodeEmail(allocator, email) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(encoded_email);

    // Build path
    const path = std.fmt.allocPrint(allocator, "/users/email/{s}", .{encoded_email}) catch {
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
