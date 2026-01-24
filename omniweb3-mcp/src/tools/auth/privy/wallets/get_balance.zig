//! Privy Get Wallet Balance Tool
//!
//! Retrieves the balance of a wallet.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// Get balance of a Privy wallet
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const wallet_id = mcp.tools.getString(args, "wallet_id") orelse {
        return client.errorResult(allocator, "Missing required parameter: wallet_id");
    };

    // Build path
    const path = std.fmt.allocPrint(allocator, "/wallets/{s}/balance", .{wallet_id}) catch {
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
