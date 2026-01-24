//! Main tools registry.
//!
//! This module serves as the central hub for registering all MCP tools.
//! Tools are organized into sub-registries by category:
//!
//! - **common**: Utility tools (ping, health checks)
//! - **unified**: Cross-chain tools (balance, transfer, blocks, transactions)
//! - **evm**: EVM-specific tools (gas, nonce, receipts, logs)
//! - **solana**: Solana-specific tools (slots, epochs, tokens, DeFi)
//!
//! To add new tools:
//! 1. Create the tool handler in the appropriate subdirectory
//! 2. Add the tool definition to the corresponding sub-registry
//! 3. The tool will be automatically registered via registerAll()

const mcp = @import("mcp");

// Sub-registries organized by chain/category
pub const common = @import("common/registry.zig");
pub const unified = @import("unified/registry.zig");
pub const evm = @import("evm/registry.zig");
pub const solana = @import("solana/registry.zig");

// Auth & wallet infrastructure
pub const privy = @import("auth/privy/registry.zig");

/// Register all tools with the MCP server.
///
/// This function delegates to each sub-registry to register their tools.
/// The order of registration determines the order tools appear in listings.
pub fn registerAll(server: *mcp.Server) !void {
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
}

/// Get total count of registered tools across all registries.
pub fn toolCount() usize {
    return common.tools.len + unified.tools.len + evm.tools.len + solana.tools.len + privy.tools.len;
}

test "tool count" {
    const std = @import("std");
    const count = toolCount();
    // Ensure we have a reasonable number of tools registered
    try std.testing.expect(count > 20);
}
