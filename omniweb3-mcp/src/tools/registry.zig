const std = @import("std");
const mcp = @import("mcp");
const ping = @import("ping.zig");
const balance = @import("balance.zig");
const transfer = @import("transfer.zig");
const block_number = @import("block_number.zig");
const block = @import("block.zig");
const transaction = @import("transaction.zig");
const receipt = @import("receipt.zig");
const nonce = @import("nonce.zig");
const gas_price = @import("gas_price.zig");
const estimate_gas = @import("estimate_gas.zig");
const call = @import("call.zig");
const token_balance = @import("token_balance.zig");
const token_accounts = @import("token_accounts.zig");
const account_info = @import("account_info.zig");
const signature_status = @import("signature_status.zig");

/// Register all tools with the MCP server
pub fn registerAll(server: *mcp.Server) !void {
    // ping tool - health check
    try server.addTool(.{
        .name = "ping",
        .description = "Health check - returns pong",
        .handler = ping.handle,
    });

    // unified balance
    try server.addTool(.{
        .name = "get_balance",
        .description = "Get balance across Solana/EVM. Parameters: chain, address, network (optional), endpoint (optional)",
        .handler = balance.handle,
    });

    // unified transfer
    try server.addTool(.{
        .name = "transfer",
        .description = "Transfer native tokens across Solana/EVM. Parameters: chain, to_address, amount, network (optional), endpoint (optional), keypair_path (Solana), private_key (EVM), tx_type (EVM), confirmations (EVM)",
        .handler = transfer.handle,
    });

    // unified block number
    try server.addTool(.{
        .name = "get_block_number",
        .description = "Get latest block height/number. Parameters: chain, network (optional), endpoint (optional)",
        .handler = block_number.handle,
    });

    // block info (EVM only)
    try server.addTool(.{
        .name = "get_block",
        .description = "Get EVM block info. Parameters: chain, block_number|block_hash, tag, include_transactions, network (optional), endpoint (optional)",
        .handler = block.handle,
    });

    // transaction info (Solana/EVM)
    try server.addTool(.{
        .name = "get_transaction",
        .description = "Get transaction info. Parameters: chain, signature (solana) or tx_hash (evm), network (optional), endpoint (optional)",
        .handler = transaction.handle,
    });

    // receipt (EVM only)
    try server.addTool(.{
        .name = "get_receipt",
        .description = "Get EVM transaction receipt. Parameters: chain, tx_hash, network (optional), endpoint (optional)",
        .handler = receipt.handle,
    });

    // nonce (EVM only)
    try server.addTool(.{
        .name = "get_nonce",
        .description = "Get EVM address nonce. Parameters: chain, address, tag (optional), network (optional), endpoint (optional)",
        .handler = nonce.handle,
    });

    // gas price (EVM only)
    try server.addTool(.{
        .name = "get_gas_price",
        .description = "Get EVM gas price. Parameters: chain, network (optional), endpoint (optional)",
        .handler = gas_price.handle,
    });

    // estimate gas (EVM only)
    try server.addTool(.{
        .name = "estimate_gas",
        .description = "Estimate EVM gas. Parameters: chain, to_address, from_address (optional), value (optional), data (optional), network (optional), endpoint (optional)",
        .handler = estimate_gas.handle,
    });

    // call (EVM only)
    try server.addTool(.{
        .name = "call",
        .description = "EVM eth_call. Parameters: chain, to_address, data, from_address (optional), value (optional), tag (optional), network (optional), endpoint (optional)",
        .handler = call.handle,
    });

    // token balance (Solana/EVM)
    try server.addTool(.{
        .name = "token_balance",
        .description = "Token balance. Parameters: chain, token_account (solana) or token_address+owner (evm), network (optional), endpoint (optional)",
        .handler = token_balance.handle,
    });

    // token accounts (Solana only)
    try server.addTool(.{
        .name = "token_accounts",
        .description = "Solana token accounts by owner. Parameters: chain=solana, owner, mint (optional), network (optional), endpoint (optional)",
        .handler = token_accounts.handle,
    });

    // account info (Solana only)
    try server.addTool(.{
        .name = "account_info",
        .description = "Solana account info. Parameters: chain=solana, address, network (optional), endpoint (optional)",
        .handler = account_info.handle,
    });

    // signature status (Solana only)
    try server.addTool(.{
        .name = "signature_status",
        .description = "Solana signature status. Parameters: chain=solana, signature, network (optional), endpoint (optional)",
        .handler = signature_status.handle,
    });
}
