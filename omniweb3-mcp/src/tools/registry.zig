const std = @import("std");
const mcp = @import("mcp");
const ping = @import("ping.zig");
const balance = @import("balance.zig");
const transfer = @import("transfer.zig");
const evm_balance = @import("evm_balance.zig");
const evm_transfer = @import("evm_transfer.zig");

/// Register all tools with the MCP server
pub fn registerAll(server: *mcp.Server) !void {
    // ping tool - health check
    try server.addTool(.{
        .name = "ping",
        .description = "Health check - returns pong",
        .handler = ping.handle,
    });

    // get_balance tool - Solana balance query
    try server.addTool(.{
        .name = "get_balance",
        .description = "Get SOL balance for a Solana address. Parameters: chain='solana', address (base58), network='devnet'|'mainnet'|'testnet'",
        .handler = balance.handle,
    });

    // transfer tool - Solana SOL transfer
    try server.addTool(.{
        .name = "transfer",
        .description = "Transfer SOL on Solana. Parameters: to_address (base58), amount (lamports), network (optional), keypair_path (optional, uses $SOLANA_KEYPAIR or ~/.config/solana/id.json)",
        .handler = transfer.handle,
    });

    // get_evm_balance tool - EVM native balance query
    try server.addTool(.{
        .name = "get_evm_balance",
        .description = "Get native token balance for an EVM address. Parameters: chain='ethereum'|'avalanche'|'bnb', address (hex), network (optional), endpoint (optional)",
        .handler = evm_balance.handle,
    });

    // evm_transfer tool - EVM native token transfer
    try server.addTool(.{
        .name = "evm_transfer",
        .description = "Transfer native tokens on EVM chains. Parameters: to_address (hex), amount (wei), chain (optional), network (optional), endpoint (optional), private_key (optional), keypair_path (optional), tx_type (optional), confirmations (optional)",
        .handler = evm_transfer.handle,
    });
}
