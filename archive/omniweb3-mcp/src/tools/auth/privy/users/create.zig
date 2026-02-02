//! Privy Create User Tool
//!
//! Creates a new user with linked accounts and optionally pre-generates wallets.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// Create a new Privy user
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    // Get account parameters
    const email = mcp.tools.getString(args, "email");
    const phone = mcp.tools.getString(args, "phone");
    const wallet_address = mcp.tools.getString(args, "wallet_address");

    // At least one account type is required
    if (email == null and phone == null and wallet_address == null) {
        return client.errorResult(allocator, "At least one account type required: email, phone, or wallet_address");
    }

    // Get wallet creation options
    const create_solana = mcp.tools.getBoolean(args, "create_solana_wallet") orelse false;
    const create_ethereum = mcp.tools.getBoolean(args, "create_ethereum_wallet") orelse false;

    // Build linked_accounts JSON array
    var linked_accounts: []const u8 = "[]";
    var owned_linked_accounts: ?[]u8 = null;
    defer if (owned_linked_accounts) |la| allocator.free(la);

    if (email != null and phone != null and wallet_address != null) {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"email\",\"address\":\"{s}\"}},{{\"type\":\"phone\",\"number\":\"{s}\"}},{{\"type\":\"wallet\",\"address\":\"{s}\",\"chain_type\":\"ethereum\"}}]",
            .{ email.?, phone.?, wallet_address.? },
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    } else if (email != null and phone != null) {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"email\",\"address\":\"{s}\"}},{{\"type\":\"phone\",\"number\":\"{s}\"}}]",
            .{ email.?, phone.? },
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    } else if (email != null and wallet_address != null) {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"email\",\"address\":\"{s}\"}},{{\"type\":\"wallet\",\"address\":\"{s}\",\"chain_type\":\"ethereum\"}}]",
            .{ email.?, wallet_address.? },
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    } else if (phone != null and wallet_address != null) {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"phone\",\"number\":\"{s}\"}},{{\"type\":\"wallet\",\"address\":\"{s}\",\"chain_type\":\"ethereum\"}}]",
            .{ phone.?, wallet_address.? },
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    } else if (email) |e| {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"email\",\"address\":\"{s}\"}}]",
            .{e},
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    } else if (phone) |p| {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"phone\",\"number\":\"{s}\"}}]",
            .{p},
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    } else if (wallet_address) |w| {
        owned_linked_accounts = std.fmt.allocPrint(
            allocator,
            "[{{\"type\":\"wallet\",\"address\":\"{s}\",\"chain_type\":\"ethereum\"}}]",
            .{w},
        ) catch return mcp.tools.ToolError.OutOfMemory;
        linked_accounts = owned_linked_accounts.?;
    }

    // Build request body
    const body = if (create_solana and create_ethereum)
        std.fmt.allocPrint(allocator, "{{\"linked_accounts\":{s},\"create_embedded_wallets\":{{\"solana\":true,\"ethereum\":true}}}}", .{linked_accounts})
    else if (create_solana)
        std.fmt.allocPrint(allocator, "{{\"linked_accounts\":{s},\"create_embedded_wallets\":{{\"solana\":true}}}}", .{linked_accounts})
    else if (create_ethereum)
        std.fmt.allocPrint(allocator, "{{\"linked_accounts\":{s},\"create_embedded_wallets\":{{\"ethereum\":true}}}}", .{linked_accounts})
    else
        std.fmt.allocPrint(allocator, "{{\"linked_accounts\":{s}}}", .{linked_accounts});

    const request_body = body catch return mcp.tools.ToolError.OutOfMemory;
    defer allocator.free(request_body);

    // Make API request
    const response = client.privyPost(allocator, "/users", request_body) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Privy API error: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return client.errorResult(allocator, msg);
    };
    defer allocator.free(response);

    return client.jsonResult(allocator, response);
}
