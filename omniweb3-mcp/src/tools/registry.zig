const std = @import("std");
const mcp = @import("mcp");
const ping = @import("ping.zig");
const balance = @import("balance.zig");
const transfer = @import("transfer.zig");

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
        .description = "Transfer SOL on Solana. Parameters: secret_key (base58 64-byte keypair), to_address (base58), amount (lamports), network='devnet'|'mainnet'|'testnet'",
        .handler = transfer.handle,
    });
}
