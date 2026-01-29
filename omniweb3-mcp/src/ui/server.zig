const std = @import("std");
const mcp = @import("mcp");
const resources = @import("resources_single.zig");

/// Register UI resources with MCP server
pub fn registerResources(server: *mcp.Server, _: std.mem.Allocator) !void {
    // Register transaction viewer resource template
    {
        const resource = mcp.resources.Resource{
            .uri = "ui://transaction",
            .name = "Transaction Viewer",
            .description = "Interactive UI for viewing blockchain transaction details",
            .mimeType = "text/html;profile=mcp-app",
            .handler = handleTransactionResource,
            .user_data = null,
        };
        try server.addResource(resource);
    }

    // Register swap interface resource template
    {
        const resource = mcp.resources.Resource{
            .uri = "ui://swap",
            .name = "Swap Interface",
            .description = "Interactive UI for token swapping",
            .mimeType = "text/html;profile=mcp-app",
            .handler = handleSwapResource,
            .user_data = null,
        };
        try server.addResource(resource);
    }

    // Register balance dashboard resource template
    {
        const resource = mcp.resources.Resource{
            .uri = "ui://balance",
            .name = "Balance Dashboard",
            .description = "Interactive UI for viewing wallet balances",
            .mimeType = "text/html;profile=mcp-app",
            .handler = handleBalanceResource,
            .user_data = null,
        };
        try server.addResource(resource);
    }

    // Register asset resources
    {
        const asset_resource = mcp.resources.Resource{
            .uri = "ui://assets",
            .name = "UI Assets",
            .description = "JavaScript, CSS and other UI assets",
            .mimeType = "application/javascript",
            .handler = handleAssetResource,
            .user_data = null,
        };
        try server.addResource(asset_resource);
    }
}

fn handleTransactionResource(allocator: std.mem.Allocator, uri: []const u8) mcp.resources.ResourceError!mcp.resources.ResourceContent {
    _ = uri; // URI params would be parsed here in production

    const html = resources.Resources.transaction_html;
    const html_copy = allocator.dupe(u8, html) catch {
        return mcp.resources.ResourceError.OutOfMemory;
    };

    return .{
        .uri = "ui://transaction",
        .mimeType = "text/html;profile=mcp-app",
        .text = html_copy,
    };
}

fn handleSwapResource(allocator: std.mem.Allocator, uri: []const u8) mcp.resources.ResourceError!mcp.resources.ResourceContent {
    _ = uri;

    const html = resources.Resources.swap_html;
    const html_copy = allocator.dupe(u8, html) catch {
        return mcp.resources.ResourceError.OutOfMemory;
    };

    return .{
        .uri = "ui://swap",
        .mimeType = "text/html;profile=mcp-app",
        .text = html_copy,
    };
}

fn handleBalanceResource(allocator: std.mem.Allocator, uri: []const u8) mcp.resources.ResourceError!mcp.resources.ResourceContent {
    _ = uri;

    const html = resources.Resources.balance_html;
    const html_copy = allocator.dupe(u8, html) catch {
        return mcp.resources.ResourceError.OutOfMemory;
    };

    return .{
        .uri = "ui://balance",
        .mimeType = "text/html;profile=mcp-app",
        .text = html_copy,
    };
}

fn handleAssetResource(allocator: std.mem.Allocator, uri: []const u8) mcp.resources.ResourceError!mcp.resources.ResourceContent {
    // Parse asset path from URI: ui://assets/transaction-405npdBf.js
    const path = if (std.mem.indexOf(u8, uri, "ui://assets/")) |_|
        uri["ui://assets/".len..]
    else
        return mcp.resources.ResourceError.InvalidUri;

    const content = resources.Resources.get(path) orelse {
        return mcp.resources.ResourceError.NotFound;
    };

    const content_copy = allocator.dupe(u8, content) catch {
        return mcp.resources.ResourceError.OutOfMemory;
    };

    // Detect MIME type
    const mime_type = if (std.mem.endsWith(u8, path, ".js"))
        "application/javascript"
    else if (std.mem.endsWith(u8, path, ".css"))
        "text/css"
    else
        "application/octet-stream";

    return .{
        .uri = uri,
        .mimeType = mime_type,
        .text = content_copy,
    };
}
