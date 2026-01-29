const std = @import("std");

/// Embedded UI resources for MCP Apps (Single-file HTML - 官方规范)
pub const Resources = struct {
    /// Transaction Viewer UI (完整单文件HTML，包含所有JS/CSS)
    pub const transaction_html = @embedFile("dist-single/transaction/mcp-app.html");

    /// Swap Interface UI (完整单文件HTML)
    pub const swap_html = @embedFile("dist-single/swap/mcp-app.html");

    /// Balance Dashboard UI (完整单文件HTML)
    pub const balance_html = @embedFile("dist-single/balance/mcp-app.html");

    /// Get resource by name (简化版，只需HTML)
    pub fn get(name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, "transaction")) return transaction_html;
        if (std.mem.eql(u8, name, "swap")) return swap_html;
        if (std.mem.eql(u8, name, "balance")) return balance_html;
        return null;
    }
};
