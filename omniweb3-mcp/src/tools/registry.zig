const std = @import("std");
const mcp = @import("mcp");
const ping = @import("ping.zig");
const balance = @import("balance.zig");
const transfer = @import("transfer.zig");
const solana_account_info = @import("solana_account_info.zig");
const solana_signature_status = @import("solana_signature_status.zig");
const solana_transaction = @import("solana_transaction.zig");
const solana_token_balance = @import("solana_token_balance.zig");
const solana_token_accounts = @import("solana_token_accounts.zig");

/// Register all tools with the MCP server
pub fn registerAll(server: *mcp.Server) !void {
    // ping tool - health check
    try server.addTool(.{
        .name = "ping",
        .description = "Health check - returns pong",
        .handler = ping.handle,
    });

    // get_balance tool - unified balance query
    try server.addTool(.{
        .name = "get_balance",
        .description = "Get balance across Solana/EVM. Parameters: chain='solana'|'ethereum'|'avalanche'|'bnb', address, network (optional), endpoint (optional)",
        .handler = balance.handle,
    });

    // transfer tool - unified transfer
    try server.addTool(.{
        .name = "transfer",
        .description = "Transfer native tokens across Solana/EVM. Parameters: chain, to_address, amount, network (optional), endpoint (optional), keypair_path (Solana), private_key (EVM), tx_type (EVM), confirmations (EVM)",
        .handler = transfer.handle,
    });

    // solana_account_info tool
    try server.addTool(.{
        .name = "solana_account_info",
        .description = "Get Solana account info. Parameters: address (base58), network (optional)",
        .handler = solana_account_info.handle,
    });

    // solana_signature_status tool
    try server.addTool(.{
        .name = "solana_signature_status",
        .description = "Get Solana transaction signature status. Parameters: signature (base58), network (optional)",
        .handler = solana_signature_status.handle,
    });

    // solana_transaction tool
    try server.addTool(.{
        .name = "solana_transaction",
        .description = "Get Solana transaction details. Parameters: signature (base58), network (optional)",
        .handler = solana_transaction.handle,
    });

    // solana_token_balance tool
    try server.addTool(.{
        .name = "solana_token_balance",
        .description = "Get SPL token account balance. Parameters: token_account (base58), network (optional)",
        .handler = solana_token_balance.handle,
    });

    // solana_token_accounts tool
    try server.addTool(.{
        .name = "solana_token_accounts",
        .description = "List SPL token accounts for owner. Parameters: owner (base58), mint (optional), network (optional)",
        .handler = solana_token_accounts.handle,
    });


}
