//! Dynamic Tool Registry
//!
//! Manages dynamically generated MCP tools from blockchain program metadata (IDL/ABI).
//! Unlike static tools which are manually coded, dynamic tools are generated at runtime
//! from contract interfaces.
//!
//! Current support:
//! - Solana/Anchor programs (via IDL)
//! - EVM contracts (via ABI) - Ethereum, BSC, Polygon, etc.
//! - Future: Cosmos (Protobuf), etc.

const std = @import("std");
const mcp = @import("mcp");
const SolanaProvider = @import("../../providers/solana/provider.zig").SolanaProvider;
const EvmProvider = @import("../../providers/evm/provider.zig").EvmProvider;
const chain_provider = @import("../../core/chain_provider.zig");
const handler_mod = @import("./handler.zig");
const abi_resolver = @import("../../providers/evm/abi_resolver.zig");
const tool_generator = @import("../../providers/evm/tool_generator.zig");

const ContractMeta = chain_provider.ContractMeta;
const FunctionCall = chain_provider.FunctionCall;

/// Global registry pointer for dynamic tool handlers
var global_registry: ?*DynamicToolRegistry = null;

/// Dynamic tool registry that holds all auto-generated tools
pub const DynamicToolRegistry = struct {
    allocator: std.mem.Allocator,
    solana_provider: ?*SolanaProvider,
    evm_providers: std.StringHashMap(*EvmProvider), // chain_name -> provider
    tools: std.ArrayList(DynamicTool),
    program_metas: std.ArrayList(ContractMeta), // Store all loaded program metadata
    contract_metas: std.ArrayList(ContractMeta), // Store EVM contract metadata

    /// A dynamically generated tool with its metadata
    pub const DynamicTool = struct {
        tool: mcp.tools.Tool,
        meta: ?*const ContractMeta, // Optional: used for Solana, not needed for EVM
        function_name: []const u8,
        chain_type: chain_provider.ChainType,
    };

    pub fn init(allocator: std.mem.Allocator) DynamicToolRegistry {
        return .{
            .allocator = allocator,
            .solana_provider = null,
            .evm_providers = std.StringHashMap(*EvmProvider).init(allocator),
            .tools = .empty,
            .program_metas = .empty,
            .contract_metas = .empty,
        };
    }

    pub fn deinit(self: *DynamicToolRegistry) void {
        // Clean up tools
        for (self.tools.items) |*tool| {
            self.allocator.free(tool.tool.name);
            if (tool.tool.description) |desc| {
                self.allocator.free(desc);
            }
        }
        self.tools.deinit(self.allocator);

        // Clean up program metadata
        for (self.program_metas.items) |*meta| {
            meta.deinit(self.allocator);
        }
        self.program_metas.deinit(self.allocator);

        // Clean up contract metadata
        for (self.contract_metas.items) |*meta| {
            meta.deinit(self.allocator);
        }
        self.contract_metas.deinit(self.allocator);

        // Clean up Solana provider
        if (self.solana_provider) |provider| {
            provider.deinit();
        }

        // Clean up EVM providers
        var it = self.evm_providers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.evm_providers.deinit();
    }

    /// Load a Solana program and generate tools from its IDL
    pub fn loadProgram(
        self: *DynamicToolRegistry,
        program_id: []const u8,
        rpc_url: []const u8,
        io: *const std.Io,
    ) !void {
        std.log.info("Loading program {s} from IDL...", .{program_id});

        // Initialize Solana provider if not already done
        if (self.solana_provider == null) {
            const provider = try SolanaProvider.init(self.allocator, rpc_url, io);
            self.solana_provider = provider;
        }

        const provider = self.solana_provider.?;

        // Resolve IDL (tries local registry, then Solana FM API)
        const meta = try provider.resolver.resolve(self.allocator, program_id);

        std.log.info("IDL loaded: {s}, {} instructions", .{
            meta.name orelse "unknown",
            meta.functions.len,
        });

        // Store the metadata so it doesn't get deallocated
        try self.program_metas.append(self.allocator, meta);
        const stored_meta = &self.program_metas.items[self.program_metas.items.len - 1];

        // Generate MCP tools from metadata
        var chain_prov = provider.asChainProvider();
        const generated_tools = try chain_prov.generateTools(self.allocator, stored_meta);

        // Store tools with metadata for later use
        for (generated_tools, 0..) |tool, i| {
            const func_name = stored_meta.functions[i].name;

            std.log.info("Generated tool: {s} for function: {s}", .{ tool.name, func_name });

            try self.tools.append(self.allocator, .{
                .tool = tool,
                .meta = stored_meta,
                .function_name = func_name,
                .chain_type = .solana,
            });
        }

        std.log.info("Total dynamic tools: {}", .{self.tools.items.len});
    }

    /// Load Jupiter v6 program and generate tools from its IDL
    pub fn loadJupiter(self: *DynamicToolRegistry, rpc_url: []const u8, io: *const std.Io) !void {
        const jupiter_program_id = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";
        try self.loadProgram(jupiter_program_id, rpc_url, io);
    }

    /// Load multiple Solana programs from configuration file
    pub fn loadSolanaPrograms(self: *DynamicToolRegistry, rpc_url: []const u8, io: *const std.Io) !void {
        std.log.info("Loading Solana programs from configuration...", .{});

        // Read programs configuration
        const config_path = "idl_registry/programs.json";
        const config_file = std.Io.Dir.cwd().openFile(io.*, config_path, .{}) catch |err| {
            std.log.warn("Failed to open {s}: {}, falling back to Jupiter only", .{ config_path, err });
            return self.loadJupiter(rpc_url, io);
        };
        defer config_file.close(io.*);

        // Get file size
        const stat = config_file.stat(io.*) catch |err| {
            std.log.warn("Failed to stat {s}: {}, falling back to Jupiter only", .{ config_path, err });
            return self.loadJupiter(rpc_url, io);
        };

        const max_size = 1024 * 1024; // 1MB max for config
        if (stat.size > max_size) {
            std.log.warn("Config file too large: {} bytes, falling back to Jupiter only", .{stat.size});
            return self.loadJupiter(rpc_url, io);
        }

        // Read file content
        const config_content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(config_content);

        const bytes_read = config_file.readPositionalAll(io.*, config_content, 0) catch |err| {
            std.log.warn("Failed to read {s}: {}, falling back to Jupiter only", .{ config_path, err });
            return self.loadJupiter(rpc_url, io);
        };

        if (bytes_read != stat.size) {
            std.log.warn("Incomplete read of {s}, falling back to Jupiter only", .{config_path});
            return self.loadJupiter(rpc_url, io);
        }

        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            config_content,
            .{},
        ) catch |err| {
            std.log.warn("Failed to parse {s}: {}, falling back to Jupiter only", .{ config_path, err });
            return self.loadJupiter(rpc_url, io);
        };
        defer parsed.deinit();

        const config = parsed.value;

        // Get programs array
        const programs_array = config.object.get("solana_programs") orelse {
            std.log.warn("No 'solana_programs' field in config, falling back to Jupiter only", .{});
            return self.loadJupiter(rpc_url, io);
        };

        var loaded_count: usize = 0;
        var failed_count: usize = 0;
        var skipped_count: usize = 0;

        for (programs_array.array.items) |prog_value| {
            const prog = prog_value.object;

            // Check if enabled
            const enabled = if (prog.get("enabled")) |e| e.bool else false;
            if (!enabled) {
                const display_name = if (prog.get("display_name")) |n| n.string else "unknown";
                std.log.info("Skipping disabled program: {s}", .{display_name});
                skipped_count += 1;
                continue;
            }

            const program_id = prog.get("id").?.string;
            const display_name = if (prog.get("display_name")) |n| n.string else program_id;

            std.log.info("Attempting to load {s}...", .{display_name});
            self.loadProgram(program_id, rpc_url, io) catch |err| {
                std.log.warn("Failed to load {s}: {}", .{ display_name, err });
                failed_count += 1;
                continue;
            };
            loaded_count += 1;
        }

        std.log.info("Programs: {} loaded, {} failed, {} skipped", .{ loaded_count, failed_count, skipped_count });
    }

    /// Load EVM contracts from configuration file
    pub fn loadEvmContracts(self: *DynamicToolRegistry, io: *const std.Io) !void {
        std.log.info("Loading EVM contracts from configuration...", .{});

        // Read contracts configuration
        const config_path = "abi_registry/contracts.json";
        const config_file = std.Io.Dir.cwd().openFile(io.*, config_path, .{}) catch |err| {
            std.log.warn("Failed to open {s}: {}, skipping EVM contracts", .{ config_path, err });
            return;
        };
        defer config_file.close(io.*);

        // Get file size
        const stat = config_file.stat(io.*) catch |err| {
            std.log.warn("Failed to stat {s}: {}, skipping EVM contracts", .{ config_path, err });
            return;
        };

        const max_size = 1024 * 1024; // 1MB max for config
        if (stat.size > max_size) {
            std.log.warn("Config file too large: {} bytes, skipping EVM contracts", .{stat.size});
            return;
        }

        // Read file content
        const config_content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(config_content);

        const bytes_read = config_file.readPositionalAll(io.*, config_content, 0) catch |err| {
            std.log.warn("Failed to read {s}: {}, skipping EVM contracts", .{ config_path, err });
            return;
        };

        if (bytes_read != stat.size) {
            std.log.warn("Incomplete read of {s}, skipping EVM contracts", .{config_path});
            return;
        }

        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            config_content,
            .{},
        ) catch |err| {
            std.log.warn("Failed to parse {s}: {}, skipping EVM contracts", .{ config_path, err });
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Get evm_contracts array
        const contracts_array = root.get("evm_contracts") orelse {
            std.log.warn("No 'evm_contracts' field in config, skipping EVM contracts", .{});
            return;
        };

        var loaded_count: usize = 0;
        const failed_count: usize = 0;
        var skipped_count: usize = 0;

        for (contracts_array.array.items) |contract_value| {
            const contract = contract_value.object;

            // Check if enabled
            const enabled = if (contract.get("enabled")) |e| e.bool else false;
            if (!enabled) {
                const display_name = if (contract.get("display_name")) |n| n.string else "unknown";
                std.log.info("Skipping disabled contract: {s}", .{display_name});
                skipped_count += 1;
                continue;
            }

            const chain = contract.get("chain").?.string;
            const chain_id = @as(u64, @intCast(contract.get("chain_id").?.integer));
            const address = contract.get("address").?.string;
            const name = contract.get("name").?.string;
            const display_name = if (contract.get("display_name")) |n| n.string else name;
            const category = if (contract.get("category")) |c| c.string else "unknown";
            const description = if (contract.get("description")) |d| d.string else "";

            std.log.info("Attempting to load {s} on {s}...", .{ display_name, chain });

            // Get or create EVM provider for this chain (will be used later for transaction building)
            _ = try self.getOrCreateEvmProvider(chain);

            // Build ABI file path: abi_registry/{chain}/{name}.json
            var abi_path_buf: [256]u8 = undefined;
            const abi_path = try std.fmt.bufPrint(&abi_path_buf, "abi_registry/{s}/{s}.json", .{ chain, name });

            // Load ABI from file
            const abi = abi_resolver.loadAbi(
                self.allocator,
                io,
                abi_path,
            ) catch |err| {
                std.log.warn("Failed to load ABI for {s}: {}", .{ name, err });
                continue;
            };

            // Create contract metadata
            const contract_meta = abi_resolver.ContractMetadata{
                .chain = chain,
                .chain_id = chain_id,
                .address = address,
                .name = name,
                .display_name = display_name,
                .category = category,
                .enabled = true,
                .description = description,
            };

            // Generate MCP tools from ABI
            const generated_tools = tool_generator.generateTools(
                self.allocator,
                &contract_meta,
                &abi,
            ) catch |err| {
                std.log.warn("Failed to generate tools for {s}: {}", .{ name, err });
                continue;
            };

            std.log.info("Generated {} tools for {s}", .{ generated_tools.len, display_name });

            // Store tools with metadata
            // Note: For EVM contracts, we don't have a traditional ContractMeta like Solana
            // EVM tools are self-contained and don't need the ContractMeta reference
            for (generated_tools) |tool| {
                std.log.debug("  - {s}", .{tool.name});

                try self.tools.append(self.allocator, .{
                    .tool = tool,
                    .meta = null, // EVM tools don't use ContractMeta
                    .function_name = "", // Function name is encoded in the tool name
                    .chain_type = .evm,
                });
            }

            loaded_count += 1;
        }

        std.log.info("EVM contracts: {} loaded, {} failed, {} skipped", .{ loaded_count, failed_count, skipped_count });
        std.log.info("Total dynamic tools: {}", .{self.tools.items.len});
    }

    /// Get or create EVM provider for a chain
    fn getOrCreateEvmProvider(self: *DynamicToolRegistry, chain_name: []const u8) !*EvmProvider {
        // Check if provider already exists
        if (self.evm_providers.get(chain_name)) |provider| {
            return provider;
        }

        // Create new provider
        std.log.info("Creating EVM provider for chain: {s}", .{chain_name});
        const provider = try EvmProvider.initFromChainName(self.allocator, chain_name);

        // Store provider
        try self.evm_providers.put(chain_name, provider);

        return provider;
    }

    /// Register all dynamic tools with the MCP server
    pub fn registerAll(self: *DynamicToolRegistry, server: *mcp.Server) !void {
        std.log.info("Registering {} dynamic tools with MCP server...", .{self.tools.items.len});

        // Set global registry for handlers to access
        global_registry = self;

        for (self.tools.items) |dyn_tool| {
            // Create tool with real handler instead of placeholder
            var tool_with_handler = dyn_tool.tool;
            tool_with_handler.handler = dynamicToolHandler;

            try server.addTool(tool_with_handler);
            std.log.debug("Registered: {s} with real handler", .{dyn_tool.tool.name});
        }

        std.log.info("Dynamic tool registration complete", .{});
    }

    /// Get the number of loaded dynamic tools
    pub fn toolCount(self: *const DynamicToolRegistry) usize {
        return self.tools.items.len;
    }

    /// Find a dynamic tool by name
    pub fn findTool(self: *const DynamicToolRegistry, name: []const u8) ?*const DynamicTool {
        for (self.tools.items) |*tool| {
            if (std.mem.eql(u8, tool.tool.name, name)) {
                return tool;
            }
        }
        return null;
    }
};

/// Real handler function for dynamic tools
/// This is called by the MCP server when a dynamic tool is invoked.
/// It extracts the tool name (injected by the server) and routes to handleDynamicTool.
fn dynamicToolHandler(
    allocator: std.mem.Allocator,
    arguments: ?std.json.Value,
) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Get the global registry
    const registry = global_registry orelse {
        std.log.err("Dynamic tool handler called but global registry not set", .{});
        return mcp.tools.ToolError.ExecutionFailed;
    };

    // Extract the injected tool name
    const tool_name = mcp.tools.getString(arguments, "_tool_name") orelse {
        std.log.err("Dynamic tool handler called without _tool_name in arguments", .{});
        return mcp.tools.ToolError.InvalidArguments;
    };

    std.log.info("Dynamic tool handler routing to: {s}", .{tool_name});

    // Route to the real implementation
    return handler_mod.handleDynamicToolWithName(
        allocator,
        registry,
        tool_name,
        arguments,
    );
}

// Tests
test "DynamicToolRegistry init and deinit" {
    const allocator = std.testing.allocator;

    var registry = DynamicToolRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.toolCount());
}
