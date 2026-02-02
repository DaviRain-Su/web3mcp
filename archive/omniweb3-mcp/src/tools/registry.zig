//! Main tools registry.
//!
//! This module serves as the central hub for registering all MCP tools.
//! Tools are organized into sub-registries by category:
//!
//! - **common**: Utility tools (ping, health checks)
//! - **unified**: Cross-chain tools (balance, transfer, blocks, transactions)
//! - **evm**: EVM-specific tools (gas, nonce, receipts, logs)
//! - **solana**: Solana-specific tools (slots, epochs, tokens, DeFi)
//! - **dynamic**: Dynamically generated tools from IDL/ABI (NEW in Phase 1)
//!
//! To add new tools:
//! 1. Create the tool handler in the appropriate subdirectory
//! 2. Add the tool definition to the corresponding sub-registry
//! 3. The tool will be automatically registered via registerAll()

const std = @import("std");
const mcp = @import("mcp");

// Sub-registries organized by chain/category
pub const common = @import("common/registry.zig");
pub const unified = @import("unified/registry.zig");
pub const evm = @import("evm/registry.zig");
pub const solana = @import("solana/registry.zig");

// Auth & wallet infrastructure
pub const privy = @import("auth/privy/registry.zig");

// Dynamic tools (Phase 1)
pub const dynamic = @import("dynamic/registry.zig");

/// Register all static tools with the MCP server.
///
/// This function delegates to each sub-registry to register their tools.
/// The order of registration determines the order tools appear in listings.
pub fn registerAll(server: *mcp.Server) !void {
    std.log.info("Registering static tools...", .{});

    // Common utilities (ping, health checks)
    try common.registerAll(server);

    // Unified cross-chain tools (balance, transfer, etc.)
    try unified.registerAll(server);

    // EVM-specific tools
    try evm.registerAll(server);

    // Solana-specific tools
    try solana.registerAll(server);

    // Privy auth & wallet tools
    try privy.registerAll(server);

    std.log.info("Static tool registration complete: {} tools", .{toolCount()});
}

/// Register all tools including dynamic tools with the MCP server.
///
/// This is the new entry point for hybrid architecture that supports both
/// static (manually coded) and dynamic (auto-generated from IDL/ABI) tools.
///
/// The dynamic_registry_opaque parameter is passed as *anyopaque to maintain
/// compatibility with the generic HTTP server setup.
pub fn registerAllWithDynamic(
    server: *mcp.Server,
    dynamic_registry_opaque: ?*anyopaque,
) !void {
    // First register all static tools
    try registerAll(server);

    // Then register dynamic tools if available
    if (dynamic_registry_opaque) |opaque_ptr| {
        // Cast from anyopaque back to DynamicToolRegistry
        const dyn_reg: *dynamic.DynamicToolRegistry = @ptrCast(@alignCast(opaque_ptr));

        std.log.info("Registering dynamic tools...", .{});
        try dyn_reg.registerAll(server);

        const total = toolCount() + dyn_reg.toolCount();
        std.log.info("=== Hybrid Tool Registry ===", .{});
        std.log.info("Static tools:  {}", .{toolCount()});
        std.log.info("Dynamic tools: {}", .{dyn_reg.toolCount()});
        std.log.info("Total tools:   {}", .{total});
        std.log.info("============================", .{});
    }
}

/// Get total count of registered tools across all registries.
pub fn toolCount() usize {
    return common.tools.len + unified.tools.len + evm.tools.len + solana.tools.len + privy.tools.len;
}

/// Get total count including dynamic tools
pub fn totalToolCount(dynamic_registry: ?*const dynamic.DynamicToolRegistry) usize {
    var total = toolCount();
    if (dynamic_registry) |dyn_reg| {
        total += dyn_reg.toolCount();
    }
    return total;
}

test "tool count" {
    const count = toolCount();
    // Ensure we have a reasonable number of tools registered
    try std.testing.expect(count > 20);
}
