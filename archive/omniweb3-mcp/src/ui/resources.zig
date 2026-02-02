const std = @import("std");

/// Embedded UI resources for MCP Apps
pub const Resources = struct {
    /// Transaction Viewer UI (HTML + inline CSS/JS)
    pub const transaction_html = @embedFile("dist/src/transaction/index.html");
    pub const transaction_js = @embedFile("dist/assets/transaction-405npdBf.js");
    pub const transaction_styles = @embedFile("dist/assets/styles-bMaF86Yt.css");
    pub const transaction_icon_check = @embedFile("dist/assets/IconCheck-Dgek7_c4.js");
    pub const transaction_icon_alert = @embedFile("dist/assets/IconAlertTriangle-DX8Cw7OO.js");
    pub const transaction_icon_copy = @embedFile("dist/assets/IconCopy-OjnGQHF9.js");
    pub const transaction_mcp_mock = @embedFile("dist/assets/mcp-mock-Djoxi6Yz.js");
    pub const transaction_main_styles = @embedFile("dist/assets/styles-ADafKn7R.js");

    /// Swap Interface UI
    pub const swap_html = @embedFile("dist/src/swap/index.html");
    pub const swap_js = @embedFile("dist/assets/swap-BY5IDdUV.js");

    /// Balance Dashboard UI
    pub const balance_html = @embedFile("dist/src/balance/index.html");
    pub const balance_js = @embedFile("dist/assets/balance-BHciln2K.js");

    /// Serve a UI resource by path
    pub fn get(path: []const u8) ?[]const u8 {
        // Remove leading slash if present
        const clean_path = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;

        if (std.mem.eql(u8, clean_path, "transaction.html")) return transaction_html;
        if (std.mem.eql(u8, clean_path, "swap.html")) return swap_html;
        if (std.mem.eql(u8, clean_path, "balance.html")) return balance_html;

        // Asset files - support both with and without "assets/" prefix
        const asset_path = if (std.mem.startsWith(u8, clean_path, "assets/"))
            clean_path["assets/".len..]
        else
            clean_path;

        if (std.mem.eql(u8, asset_path, "transaction-405npdBf.js")) return transaction_js;
        if (std.mem.eql(u8, asset_path, "swap-BY5IDdUV.js")) return swap_js;
        if (std.mem.eql(u8, asset_path, "balance-BHciln2K.js")) return balance_js;
        if (std.mem.eql(u8, asset_path, "styles-bMaF86Yt.css")) return transaction_styles;
        if (std.mem.eql(u8, asset_path, "styles-ADafKn7R.js")) return transaction_main_styles;
        if (std.mem.eql(u8, asset_path, "IconCheck-Dgek7_c4.js")) return transaction_icon_check;
        if (std.mem.eql(u8, asset_path, "IconAlertTriangle-DX8Cw7OO.js")) return transaction_icon_alert;
        if (std.mem.eql(u8, asset_path, "IconCopy-OjnGQHF9.js")) return transaction_icon_copy;
        if (std.mem.eql(u8, asset_path, "mcp-mock-Djoxi6Yz.js")) return transaction_mcp_mock;

        return null;
    }
};
