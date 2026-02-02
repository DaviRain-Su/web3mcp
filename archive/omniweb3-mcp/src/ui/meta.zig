const std = @import("std");

/// UI metadata for MCP Apps
pub const UiMeta = struct {
    resourceUri: []const u8,

    /// Create UI metadata for transaction viewer
    pub fn transaction(allocator: std.mem.Allocator, chain: []const u8, tx_hash: []const u8, network: []const u8) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            "ui://transaction?chain={s}&txHash={s}&network={s}",
            .{ chain, tx_hash, network },
        );
    }

    /// Create UI metadata for swap interface
    pub fn swap(allocator: std.mem.Allocator, chain: []const u8, network: []const u8) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            "ui://swap?chain={s}&network={s}",
            .{ chain, network },
        );
    }

    /// Create UI metadata for balance dashboard
    pub fn balance(allocator: std.mem.Allocator, chain: []const u8, address: []const u8, network: []const u8) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            "ui://balance?chain={s}&address={s}&network={s}",
            .{ chain, address, network },
        );
    }
};

/// Tool result with UI metadata support
/// This is a custom extension to mcp.tools.ToolResult
pub fn ResultWithUi(comptime T: type) type {
    return struct {
        data: T,
        _meta: ?struct {
            ui: struct {
                resourceUri: []const u8,
            },
        } = null,

        /// Serialize to JSON with _meta field
        pub fn toJson(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            return std.json.stringifyAlloc(allocator, self, .{});
        }
    };
}

/// Create a tool result with UI metadata embedded in the JSON response
pub fn createUiResult(allocator: std.mem.Allocator, data_json: []const u8, ui_resource_uri: []const u8) ![]const u8 {
    // Build new JSON with _meta field
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    // Find the last closing brace
    var trimmed_len = data_json.len;
    while (trimmed_len > 0) : (trimmed_len -= 1) {
        const c = data_json[trimmed_len - 1];
        if (c == '}') {
            trimmed_len -= 1;
            break;
        }
        if (c != ' ' and c != '\n' and c != '\r' and c != '\t') break;
    }

    // Copy everything before the last }
    try result.appendSlice(allocator, data_json[0..trimmed_len]);

    // Add _meta field
    const meta_field = try std.fmt.allocPrint(
        allocator,
        ",\"_meta\":{{\"ui\":{{\"resourceUri\":\"{s}\"}}}}}}",
        .{ui_resource_uri},
    );
    defer allocator.free(meta_field);

    try result.appendSlice(allocator, meta_field);

    return result.toOwnedSlice(allocator);
}
