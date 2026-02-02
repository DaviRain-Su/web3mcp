const std = @import("std");

/// Embedded UI resources for MCP Apps (Single-file HTML - 官方规范)
pub const Resources = struct {
    /// Balance Dashboard UI (完整单文件HTML)
    pub const balance_html = @embedFile("dist-single/balance/mcp-app.html");

    /// Get resource by name (简化版，只需HTML)
    pub fn get(name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, "balance")) return balance_html;
        return null;
    }
};
