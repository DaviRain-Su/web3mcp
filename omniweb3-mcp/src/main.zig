const std = @import("std");
const mcp = @import("mcp");
const tools = @import("tools/registry.zig");
const evm_runtime = @import("core/evm_runtime.zig");
const ui_server = @import("ui/server.zig");

/// Smart MCP Server with Contract Discovery
/// Only loads static tools (~175) + uses unified interfaces for contracts
/// User only needs to configure ONE server!
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        mcp.reportError(err);
        return err;
    };
}

fn run(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Initialize EVM runtime
    try evm_runtime.init(allocator, init.minimal.environ);
    defer evm_runtime.deinit();

    std.log.info("omniweb3-smart starting...", .{});

    // Create MCP server
    var server = mcp.Server.init(.{
        .name = "omniweb3-smart",
        .version = "0.2.0",
        .title = "Omniweb3 Smart MCP",
        .description = "Smart Web3 MCP with unified interfaces and contract discovery",
        .instructions =
        \\This server provides a smart approach to Web3 interactions:
        \\
        \\1. Use 'discover_contracts' to find available contracts on different chains
        \\2. Use 'call_contract' (unified interface) to interact with any contract
        \\3. Use 'get_balance', 'transfer' for common operations
        \\
        \\This approach keeps context small (<200 tools) while supporting unlimited contracts!
        ,
        .allocator = allocator,
    });
    defer server.deinit();

    // Register static tools only
    std.log.info("Registering static tools...", .{});
    try tools.common.registerAll(&server);
    try tools.unified.registerAll(&server);
    try tools.evm.registerAll(&server);
    try tools.solana.registerAll(&server);
    try tools.privy.registerAll(&server);

    // Register discovery tools
    std.log.info("Registering discovery tools...", .{});
    try registerDiscoveryTools(&server, allocator, &init.io);

    // Register UI resources
    std.log.info("Registering UI resources...", .{});
    try ui_server.registerResources(&server, allocator);

    server.enableLogging();

    const tool_count = tools.toolCount() + 3; // +3 for discovery tools (discover_contracts, discover_chains, discover_programs)
    std.log.info("omniweb3-smart ready: {} tools (static + discovery)", .{tool_count});
    std.log.info("EVM Chains: Ethereum, BSC, Polygon, Avalanche (mainnet/testnet)", .{});
    std.log.info("Solana Networks: Mainnet-beta, Devnet, Testnet", .{});
    std.log.info("Dynamic: discover_contracts/programs + call_contract/program", .{});

    // Run in stdio mode
    try server.run(.stdio);
}

fn registerDiscoveryTools(server: *mcp.Server, allocator: std.mem.Allocator, io: *const std.Io) !void {
    // Tool 1: discover_contracts - EVM contracts
    {
        const Context = struct {
            allocator: std.mem.Allocator,
            io: *const std.Io,
        };
        const ctx = try allocator.create(Context);
        ctx.* = .{ .allocator = allocator, .io = io };

        const tool = mcp.Tool{
            .name = "discover_contracts",
            .description =
            \\Discover available smart contracts from contracts.json.
            \\Returns contract addresses, ABIs, and usage information.
            \\
            \\After discovering contracts, use the 'call_contract' tool to interact with them.
            \\
            \\Example workflow:
            \\1. discover_contracts(chain="bsc")
            \\2. call_contract(chain="bsc", contract="0x...", function="balanceOf", args=["0xAddress"])
            ,
            .inputSchema = .{
                .type = "object",
                .properties = null,
                .required = null,
            },
            .handler = handleDiscoverContracts,
            .user_data = ctx,
        };

        try server.addTool(tool);
    }

    // Tool 2: discover_chains
    {
        const Context = struct {
            allocator: std.mem.Allocator,
        };
        const ctx = try allocator.create(Context);
        ctx.* = .{ .allocator = allocator };

        const tool = mcp.Tool{
            .name = "discover_chains",
            .description = "List all supported blockchain chains with their chain IDs and RPC endpoints",
            .inputSchema = .{
                .type = "object",
                .properties = null,
                .required = null,
            },
            .handler = handleDiscoverChains,
            .user_data = ctx,
        };

        try server.addTool(tool);
    }

    // Tool 3: discover_programs - Solana programs
    {
        const Context = struct {
            allocator: std.mem.Allocator,
            io: *const std.Io,
        };
        const ctx = try allocator.create(Context);
        ctx.* = .{ .allocator = allocator, .io = io };

        const tool = mcp.Tool{
            .name = "discover_programs",
            .description = "Discover available Solana programs from idl_registry/programs.json. Returns program IDs, IDLs, and usage information.",
            .inputSchema = .{
                .type = "object",
                .properties = null,
                .required = null,
            },
            .handler = handleDiscoverPrograms,
            .user_data = ctx,
        };

        try server.addTool(tool);
    }
}

fn handleDiscoverContracts(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    _ = args;

    // Read contracts.json using std.Io
    const io = evm_runtime.io();
    const file = std.Io.Dir.cwd().openFile(io, "abi_registry/contracts.json", .{}) catch {
        // Fallback to hardcoded if file not found
        return fallbackHardcodedContracts(allocator);
    };
    defer file.close(io);

    const stat = file.stat(io) catch {
        return fallbackHardcodedContracts(allocator);
    };

    const content = allocator.alloc(u8, stat.size) catch {
        return fallbackHardcodedContracts(allocator);
    };
    defer allocator.free(content);

    _ = file.readPositionalAll(io, content, 0) catch {
        return fallbackHardcodedContracts(allocator);
    };

    // Parse JSON
    const parsed = std.json.parseFromSlice(
        struct {
            evm_contracts: []struct {
                chain: []const u8,
                chain_id: u64,
                address: []const u8,
                name: []const u8,
                display_name: []const u8,
                category: []const u8,
                enabled: bool,
                description: []const u8,
            },
        },
        allocator,
        content,
        .{},
    ) catch {
        return fallbackHardcodedContracts(allocator);
    };
    defer parsed.deinit();

    // Build JSON response
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator,
        \\{
        \\  "contracts": [
    );

    var count: usize = 0;
    for (parsed.value.evm_contracts) |contract| {
        if (!contract.enabled) continue;

        if (count > 0) try result.appendSlice(allocator, ",\n");

        const contract_entry = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "name": "{s}",
            \\      "display_name": "{s}",
            \\      "chain": "{s}",
            \\      "chain_id": {d},
            \\      "address": "{s}",
            \\      "category": "{s}",
            \\      "description": "{s}",
            \\      "abi_file": "abi_registry/{s}.json",
            \\      "usage": "Use call_contract(chain='{s}', contract='{s}', function='...', args=[...]) to interact"
            \\    }}
        , .{
            contract.name,
            contract.display_name,
            contract.chain,
            contract.chain_id,
            contract.address,
            contract.category,
            contract.description,
            contract.name,
            contract.chain,
            contract.name,
        });
        defer allocator.free(contract_entry);
        try result.appendSlice(allocator, contract_entry);

        count += 1;
    }

    try result.appendSlice(allocator,
        \\
        \\  ],
        \\  "total":
    );
    const total_str = try std.fmt.allocPrint(allocator, "{d}", .{count});
    defer allocator.free(total_str);
    try result.appendSlice(allocator, total_str);
    try result.appendSlice(allocator,
        \\,
        \\  "message": "Use the 'call_contract' tool to interact with these contracts. You can specify contracts by name (e.g., 'pancake_testnet') or address."
        \\}
    );

    const text = try result.toOwnedSlice(allocator);
    return mcp.tools.textResult(allocator, text);
}

fn fallbackHardcodedContracts(allocator: std.mem.Allocator) mcp.tools.ToolError!mcp.tools.ToolResult {
    const text = try allocator.dupe(u8,
        \\{
        \\  "contracts": [
        \\    {
        \\      "name": "pancake_testnet",
        \\      "display_name": "PancakeSwap Router V2 (Testnet)",
        \\      "chain": "bsc",
        \\      "chain_id": 97,
        \\      "address": "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
        \\      "category": "dex",
        \\      "description": "PancakeSwap V2 Router on BSC Testnet - swap, liquidity",
        \\      "abi_file": "abi_registry/pancake_testnet.json",
        \\      "usage": "Use call_contract(chain='bsc', contract='pancake_testnet', function='...', args=[...]) to interact"
        \\    },
        \\    {
        \\      "name": "wbnb_test",
        \\      "display_name": "Wrapped BNB (Testnet)",
        \\      "chain": "bsc",
        \\      "chain_id": 97,
        \\      "address": "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
        \\      "category": "token",
        \\      "description": "WBNB ERC20 token on BSC Testnet",
        \\      "abi_file": "abi_registry/wbnb_test.json",
        \\      "usage": "Use call_contract(chain='bsc', contract='wbnb_test', function='balanceOf', args=['0xAddress']) to interact"
        \\    },
        \\    {
        \\      "name": "busd_test",
        \\      "display_name": "Binance USD (Testnet)",
        \\      "chain": "bsc",
        \\      "chain_id": 97,
        \\      "address": "0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee",
        \\      "category": "token",
        \\      "description": "BUSD stablecoin on BSC Testnet",
        \\      "abi_file": "abi_registry/busd_test.json",
        \\      "usage": "Use call_contract(chain='bsc', contract='busd_test', function='balanceOf', args=['0xAddress']) to interact"
        \\    }
        \\  ],
        \\  "total": 3,
        \\  "message": "Using hardcoded contracts (contracts.json not found). Use the 'call_contract' tool to interact."
        \\}
    );

    return mcp.tools.textResult(allocator, text);
}

fn handleDiscoverChains(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    _ = args;

    const text = try allocator.dupe(u8,
        \\{
        \\  "chains": [
        \\    {
        \\      "name": "bsc",
        \\      "display_name": "Binance Smart Chain",
        \\      "mainnet": 56,
        \\      "testnet": 97,
        \\      "type": "evm",
        \\      "rpc": "https://bsc-dataseed1.binance.org"
        \\    },
        \\    {
        \\      "name": "ethereum",
        \\      "display_name": "Ethereum",
        \\      "mainnet": 1,
        \\      "testnet": 11155111,
        \\      "type": "evm",
        \\      "rpc": "https://eth.llamarpc.com"
        \\    },
        \\    {
        \\      "name": "polygon",
        \\      "display_name": "Polygon",
        \\      "mainnet": 137,
        \\      "testnet": 80002,
        \\      "type": "evm",
        \\      "rpc": "https://polygon-rpc.com"
        \\    },
        \\    {
        \\      "name": "avalanche",
        \\      "display_name": "Avalanche C-Chain",
        \\      "mainnet": 43114,
        \\      "testnet": 43113,
        \\      "type": "evm",
        \\      "rpc": "https://api.avax.network/ext/bc/C/rpc"
        \\    },
        \\    {
        \\      "name": "solana",
        \\      "display_name": "Solana",
        \\      "type": "solana",
        \\      "rpc": "https://api.mainnet-beta.solana.com"
        \\    }
        \\  ],
        \\  "usage": "Use these chain names with get_balance, transfer, call_contract, and other unified tools"
        \\}
    );

    return mcp.tools.textResult(allocator, text);
}

fn handleDiscoverPrograms(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    _ = args;

    // Read programs.json using std.Io
    const io = evm_runtime.io();
    const file = std.Io.Dir.cwd().openFile(io, "idl_registry/programs.json", .{}) catch {
        // Fallback to hardcoded if file not found
        return fallbackHardcodedPrograms(allocator);
    };
    defer file.close(io);

    const stat = file.stat(io) catch {
        return fallbackHardcodedPrograms(allocator);
    };

    const content = allocator.alloc(u8, stat.size) catch {
        return fallbackHardcodedPrograms(allocator);
    };
    defer allocator.free(content);

    _ = file.readPositionalAll(io, content, 0) catch {
        return fallbackHardcodedPrograms(allocator);
    };

    // Parse JSON
    const parsed = std.json.parseFromSlice(
        struct {
            solana_programs: []struct {
                id: []const u8,
                name: []const u8,
                display_name: []const u8,
                category: []const u8,
                enabled: bool,
                description: []const u8,
            },
        },
        allocator,
        content,
        .{},
    ) catch {
        return fallbackHardcodedPrograms(allocator);
    };
    defer parsed.deinit();

    // Build JSON response
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator,
        \\{
        \\  "programs": [
    );

    var count: usize = 0;
    for (parsed.value.solana_programs) |program| {
        if (!program.enabled) continue;

        if (count > 0) try result.appendSlice(allocator, ",\n");

        const program_entry = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "id": "{s}",
            \\      "name": "{s}",
            \\      "display_name": "{s}",
            \\      "category": "{s}",
            \\      "description": "{s}",
            \\      "idl_file": "idl_registry/{s}.json",
            \\      "note": "Solana program calling requires instruction building (more complex than EVM)"
            \\    }}
        , .{
            program.id,
            program.name,
            program.display_name,
            program.category,
            program.description,
            program.id,
        });
        defer allocator.free(program_entry);
        try result.appendSlice(allocator, program_entry);

        count += 1;
    }

    try result.appendSlice(allocator,
        \\
        \\  ],
        \\  "total":
    );
    const total_str = try std.fmt.allocPrint(allocator, "{d}", .{count});
    defer allocator.free(total_str);
    try result.appendSlice(allocator, total_str);
    try result.appendSlice(allocator,
        \\,
        \\  "message": "Solana programs discovered. Note: Direct program calling is more complex than EVM contracts and requires instruction building with accounts."
        \\}
    );

    const text = try result.toOwnedSlice(allocator);
    return mcp.tools.textResult(allocator, text);
}

fn fallbackHardcodedPrograms(allocator: std.mem.Allocator) mcp.tools.ToolError!mcp.tools.ToolResult {
    const text = try allocator.dupe(u8,
        \\{
        \\  "programs": [
        \\    {
        \\      "id": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
        \\      "name": "jupiter",
        \\      "display_name": "Jupiter v6",
        \\      "category": "dex_aggregator",
        \\      "description": "Jupiter aggregator v6",
        \\      "idl_file": "idl_registry/JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4.json"
        \\    },
        \\    {
        \\      "id": "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",
        \\      "name": "orca",
        \\      "display_name": "Orca Whirlpool",
        \\      "category": "dex",
        \\      "description": "Orca concentrated liquidity pools",
        \\      "idl_file": "idl_registry/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json"
        \\    }
        \\  ],
        \\  "total": 2,
        \\  "message": "Using hardcoded programs (programs.json not found). Note: Solana program calling requires instruction building."
        \\}
    );

    return mcp.tools.textResult(allocator, text);
}
