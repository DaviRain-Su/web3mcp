const std = @import("std");
const mcp = @import("mcp");
const tools = @import("tools/registry.zig");
const evm_runtime = @import("core/evm_runtime.zig");

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        mcp.reportError(err);
        return err;
    };
}

fn run(init: std.process.Init) !void {
    const allocator = init.gpa;

    try evm_runtime.init(allocator, init.minimal.environ);
    defer evm_runtime.deinit();

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
