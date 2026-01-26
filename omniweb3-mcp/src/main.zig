const std = @import("std");
const mcp = @import("mcp");
const tools = @import("tools/registry.zig");
const dynamic_tools = @import("tools/dynamic/registry.zig");
const evm_runtime = @import("core/evm_runtime.zig");
const http_server = @import("http_server.zig");

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        mcp.reportError(err);
        return err;
    };
}

fn run(init: std.process.Init) !void {
    // Wrap GPA with a thread-safe allocator for multi-threaded HTTP workers.
    var ts_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = init.gpa };
    const allocator = ts_allocator.allocator();

    try evm_runtime.init(allocator, init.minimal.environ);
    defer evm_runtime.deinit();

    // Initialize dynamic tool registry
    var dyn_registry = dynamic_tools.DynamicToolRegistry.init(allocator);
    defer dyn_registry.deinit();

    // Load Jupiter v6 program from IDL (optional - only if RPC URL available)
    const rpc_url = init.environ_map.get("SOLANA_RPC_URL") orelse "https://api.mainnet-beta.solana.com";
    const enable_dynamic = init.environ_map.get("ENABLE_DYNAMIC_TOOLS");

    if (enable_dynamic == null or std.mem.eql(u8, enable_dynamic.?, "true")) {
        std.log.info("Loading dynamic tools from Jupiter IDL...", .{});
        dyn_registry.loadJupiter(rpc_url, &init.io) catch |err| {
            std.log.warn("Failed to load Jupiter dynamic tools: {}", .{err});
            std.log.warn("Continuing with static tools only...", .{});
        };
    } else {
        std.log.info("Dynamic tools disabled via ENABLE_DYNAMIC_TOOLS=false", .{});
    }

    const host = init.environ_map.get("HOST") orelse "0.0.0.0";
    const port = parsePort(init.environ_map.get("PORT") orelse "8765") catch 8765;
    const workers = parseWorkers(init.environ_map.get("MCP_WORKERS") orelse "4") catch 4;

    const setup = http_server.ServerSetup{
        .name = "omniweb3-mcp",
        .version = "0.1.0",
        .title = "Omni Web3 MCP",
        .description = "Cross-chain Web3 MCP server for AI agents (Hybrid: Static + Dynamic Tools)",
        .enable_logging = true,
        .register = tools.registerAllWithDynamic,
        .dynamic_registry = &dyn_registry,
    };

    try http_server.runHttpServer(allocator, init.io, .{
        .host = host,
        .port = port,
        .workers = workers,
        .setup = setup,
    });
}

fn parsePort(value: []const u8) !u16 {
    const port = try std.fmt.parseInt(u16, value, 10);
    if (port == 0) return error.InvalidPort;
    return port;
}

fn parseWorkers(value: []const u8) !usize {
    const workers = try std.fmt.parseInt(usize, value, 10);
    if (workers == 0) return error.InvalidWorkers;
    return if (workers > 64) 64 else workers;
}
