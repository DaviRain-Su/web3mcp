const std = @import("std");
const mcp = @import("mcp");

/// Ping tool handler - returns "pong" for health check
pub fn handle(allocator: std.mem.Allocator, _: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    return mcp.tools.textResult(allocator, "pong from omniweb3-mcp") catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
