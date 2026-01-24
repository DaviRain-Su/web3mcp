//! Simple MCP Client Example
//!
//! This example demonstrates how to create an MCP client
//! that connects to a server.

const std = @import("std");
const mcp = @import("mcp");

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        mcp.reportError(err);
    };
}

fn run(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Get command line args for server path
    var args_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_it.deinit();

    const argv0_z = args_it.next() orelse return;
    const argv0 = try allocator.dupe(u8, std.mem.sliceTo(argv0_z, 0));
    defer allocator.free(argv0);

    const server_cmd_z = args_it.next() orelse {
        std.debug.print("Usage: {s} <server-command>\n", .{argv0});
        std.debug.print("Example: {s} zig-out/bin/example-server\n", .{argv0});
        return;
    };
    _ = server_cmd_z;

    // Create client
    var client = mcp.Client.init(.{
        .name = "simple-client",
        .version = "1.0.0",
        .title = "Simple MCP Client",
        .allocator = allocator,
    });
    defer client.deinit();

    // Enable capabilities
    client.enableSampling();
    client.enableRoots(true);

    // Add some roots
    try client.addRoot("file:///home/user/documents", "Documents");
    try client.addRoot("file:///home/user/projects", "Projects");

    std.debug.print("MCP Client initialized\n", .{});
    std.debug.print("Client: {s} v{s}\n", .{ client.config.name, client.config.version });
    std.debug.print("Roots configured: {d}\n", .{client.roots_list.items.len});

    // In a real implementation, you would:
    // 1. Connect to server: try client.connectStdio(args[1], &.{});
    // 2. List tools: try client.listTools();
    // 3. Call tools: try client.callTool("greet", args);
    // 4. Handle responses in an event loop

    std.debug.print("\nTo connect to a server, run:\n", .{});
    std.debug.print("  echo '{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{}}}}' | .\\zig-out\\bin\\example-server\n", .{});
}
