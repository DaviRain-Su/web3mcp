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

    std.log.info("Dynamic tools configuration: ENABLE_DYNAMIC_TOOLS={s}, SOLANA_RPC_URL={s}", .{
        if (enable_dynamic) |v| v else "(not set, default=enabled)",
        rpc_url,
    });

    if (enable_dynamic == null or std.mem.eql(u8, enable_dynamic.?, "true")) {
        std.log.info("Loading dynamic tools from Solana programs...", .{});
        dyn_registry.loadSolanaPrograms(rpc_url, &init.io) catch |err| {
            std.log.err("Failed to load Solana dynamic tools: {}", .{err});
            std.log.err("Continuing with static tools only...", .{});
            std.log.err("Please check:", .{});
            std.log.err("  1. IDL files exist in idl_registry/", .{});
            std.log.err("  2. Network connectivity to Solana FM API", .{});
            std.log.err("  3. SOLANA_RPC_URL is valid: {s}", .{rpc_url});
        };

        std.log.info("Dynamic tools: {}", .{dyn_registry.toolCount()});
    } else {
        std.log.info("Dynamic tools disabled via ENABLE_DYNAMIC_TOOLS={s}", .{enable_dynamic.?});
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
