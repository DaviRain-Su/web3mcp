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

// Test imports
test {
    // Import all modules with test blocks to include them in test builds

    // Core modules
    _ = @import("core/borsh.zig");
    _ = @import("core/borsh_test.zig");
    _ = @import("core/chain_test.zig");
    _ = @import("core/endpoints_test.zig");
    _ = @import("core/evm_helpers_test.zig");
    _ = @import("core/http_utils_test.zig");
    _ = @import("core/solana_helpers_test.zig");
    _ = @import("core/wallet_provider_test.zig");
    _ = @import("core/wallet_test.zig");
    _ = @import("core/batch_rpc_test.zig");
    _ = @import("core/price_subscription_test.zig");

    // Solana provider modules
    _ = @import("providers/solana/idl_resolver.zig");
    _ = @import("providers/solana/provider.zig");
    _ = @import("providers/solana/tool_generator.zig");
    _ = @import("providers/solana/transaction_builder.zig");
    _ = @import("providers/solana/transaction_builder_test.zig");

    // Tool registry modules
    _ = @import("tools/dynamic/registry.zig");
    _ = @import("tools/registry.zig");

    // Meteora modules
    _ = @import("tools/solana/defi/meteora/constants.zig");
    _ = @import("tools/solana/defi/meteora/helpers_test.zig");
    _ = @import("tools/solana/defi/meteora/math_test.zig");

    // Jupiter modules
    _ = @import("tools/solana/defi/jupiter/constants.zig");
    _ = @import("tools/solana/defi/jupiter/constants_extra_test.zig");
    _ = @import("tools/solana/defi/jupiter/helpers_test.zig");
    _ = @import("tools/solana/defi/jupiter/batch/batch_swap_test.zig");
    _ = @import("tools/solana/defi/jupiter/batch/batch_trigger_orders_test.zig");

    // Trading strategies
    _ = @import("tools/solana/strategies/grid_trading_test.zig");
}
