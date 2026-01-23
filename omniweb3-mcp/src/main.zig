const std = @import("std");
const mcp = @import("mcp");
const tools = @import("tools/registry.zig");

pub fn main() void {
    run() catch |err| {
        mcp.reportError(err);
    };
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = mcp.Server.init(.{
        .name = "omniweb3-mcp",
        .version = "0.1.0",
        .title = "Omni Web3 MCP",
        .description = "Cross-chain Web3 MCP server for AI agents",
        .allocator = allocator,
    });
    defer server.deinit();

    // Register tools
    try tools.registerAll(&server);

    // Enable logging
    server.enableLogging();

    // Run stdio transport
    try server.run(.stdio);
}
