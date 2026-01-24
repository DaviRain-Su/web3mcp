//! Common tools registry.
//!
//! Registers common utility tools that work across all chains.

const mcp = @import("mcp");
const ping = @import("ping.zig");

/// Tool definitions for common utilities.
pub const tools = [_]mcp.tools.Tool{
    .{
        .name = "ping",
        .description = "Health check - returns pong",
        .handler = ping.handle,
    },
};

/// Register all common tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
