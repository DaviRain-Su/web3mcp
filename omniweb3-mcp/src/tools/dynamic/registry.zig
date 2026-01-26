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
        };
    }

    pub fn deinit(self: *DynamicToolRegistry) void {
        // Clean up tools
        for (self.tools.items) |*tool| {
            self.allocator.free(tool.tool.name);
            if (tool.tool.description) |desc| {
                self.allocator.free(desc);
            }
            // Note: tool.meta is managed by provider
        }
        self.tools.deinit(self.allocator);

        // Clean up provider
        if (self.solana_provider) |provider| {
            provider.deinit();
        }
    }

    /// Load Jupiter v6 program and generate tools from its IDL
    pub fn loadJupiter(self: *DynamicToolRegistry, rpc_url: []const u8, io: *const std.Io) !void {
        std.log.info("Loading Jupiter v6 program from IDL...", .{});

        // Initialize Solana provider if not already done
        if (self.solana_provider == null) {
            const provider = try SolanaProvider.init(self.allocator, rpc_url, io);
            self.solana_provider = provider;
        }

        const provider = self.solana_provider.?;
        const jupiter_program_id = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";

        // Resolve IDL (tries local registry, then Solana FM API)
        const meta = try provider.resolver.resolve(self.allocator, jupiter_program_id);

        std.log.info("Jupiter v6 IDL loaded: {s}, {} instructions", .{
            meta.name orelse "unknown",
            meta.functions.len,
        });

        // Generate MCP tools from metadata
        var chain_prov = provider.asChainProvider();
        const generated_tools = try chain_prov.generateTools(self.allocator, &meta);

        // Store tools with metadata for later use
        for (generated_tools, 0..) |tool, i| {
            const func_name = meta.functions[i].name;

            std.log.info("Generated tool: {s} for function: {s}", .{tool.name, func_name});

            try self.tools.append(self.allocator, .{
                .tool = tool,
                .meta = &meta,
                .function_name = func_name,
                .chain_type = .solana,
            });
        }

        std.log.info("Total dynamic tools loaded: {}", .{self.tools.items.len});
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
