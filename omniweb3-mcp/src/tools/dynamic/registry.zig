//! Dynamic Tool Registry
//!
//! Manages dynamically generated MCP tools from blockchain program metadata (IDL/ABI).
//! Unlike static tools which are manually coded, dynamic tools are generated at runtime
//! from contract interfaces.
//!
//! Current support:
//! - Solana/Anchor programs (via IDL)
//! - Future: EVM contracts (via ABI), Cosmos (Protobuf), etc.

const std = @import("std");
const mcp = @import("mcp");
const SolanaProvider = @import("../../providers/solana/provider.zig").SolanaProvider;
const chain_provider = @import("../../core/chain_provider.zig");
const handler_mod = @import("./handler.zig");

const ContractMeta = chain_provider.ContractMeta;
const FunctionCall = chain_provider.FunctionCall;

/// Global registry pointer for dynamic tool handlers
var global_registry: ?*DynamicToolRegistry = null;

/// Dynamic tool registry that holds all auto-generated tools
pub const DynamicToolRegistry = struct {
    allocator: std.mem.Allocator,
    solana_provider: ?*SolanaProvider,
    tools: std.ArrayList(DynamicTool),
    program_metas: std.ArrayList(ContractMeta), // Store all loaded program metadata

    /// A dynamically generated tool with its metadata
    pub const DynamicTool = struct {
        tool: mcp.tools.Tool,
        meta: *const ContractMeta,
        function_name: []const u8,
        chain_type: chain_provider.ChainType,
    };

    pub fn init(allocator: std.mem.Allocator) DynamicToolRegistry {
        return .{
            .allocator = allocator,
            .solana_provider = null,
            .tools = .empty,
            .program_metas = .empty,
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

        // Clean up provider
        if (self.solana_provider) |provider| {
            provider.deinit();
        }
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

    /// Load multiple popular Solana programs
    pub fn loadSolanaPrograms(self: *DynamicToolRegistry, rpc_url: []const u8, io: *const std.Io) !void {
        std.log.info("Loading popular Solana programs...", .{});

        const programs = [_]struct { id: []const u8, name: []const u8 }{
            // Jupiter v6 (DEX Aggregator)
            .{ .id = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4", .name = "Jupiter v6" },

            // Metaplex Token Metadata (NFT Standard)
            .{ .id = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s", .name = "Metaplex Token Metadata" },

            // Raydium AMM v4 (DEX)
            .{ .id = "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8", .name = "Raydium AMM v4" },

            // Orca Whirlpool (DEX)
            .{ .id = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc", .name = "Orca Whirlpool" },

            // Marinade Finance (Liquid Staking)
            .{ .id = "MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD", .name = "Marinade Finance" },
        };

        var loaded_count: usize = 0;
        var failed_count: usize = 0;

        for (programs) |prog| {
            std.log.info("Attempting to load {s}...", .{prog.name});
            self.loadProgram(prog.id, rpc_url, io) catch |err| {
                std.log.warn("Failed to load {s}: {}", .{ prog.name, err });
                failed_count += 1;
                continue;
            };
            loaded_count += 1;
        }

        std.log.info("Loaded {} programs successfully, {} failed", .{ loaded_count, failed_count });
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
