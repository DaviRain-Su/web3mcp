//! Unified (cross-chain) tools registry.
//!
//! Registers tools that work across multiple chains (Solana + EVM).

const mcp = @import("mcp");
const balance = @import("balance.zig");
const transfer = @import("transfer.zig");
const block_number = @import("block_number.zig");
const block = @import("block.zig");
const transaction = @import("transaction.zig");
const token_balance = @import("token_balance.zig");

/// Tool definitions for unified/cross-chain operations.
pub const tools = [_]mcp.tools.Tool{
    .{
        .name = "get_balance",
        .description = "Get balance across Solana/EVM. Parameters: chain, address, network (optional), endpoint (optional)",
        .handler = balance.handle,
    },
    .{
        .name = "transfer",
        .description = "Transfer native tokens across Solana/EVM. Parameters: chain, to_address, amount, network (optional), endpoint (optional), keypair_path (Solana), private_key (EVM), tx_type (EVM), confirmations (EVM)",
        .handler = transfer.handle,
    },
    .{
        .name = "get_block_number",
        .description = "Get latest block height/number. Parameters: chain, network (optional), endpoint (optional)",
        .handler = block_number.handle,
    },
    .{
        .name = "get_block",
        .description = "Get block info. Parameters: chain, block_number (evm) or slot (solana), block_hash (evm), tag (evm), include_transactions, network (optional), endpoint (optional)",
        .handler = block.handle,
    },
    .{
        .name = "get_transaction",
        .description = "Get transaction info. Parameters: chain, signature (solana) or tx_hash (evm), network (optional), endpoint (optional)",
        .handler = transaction.handle,
    },
    .{
        .name = "token_balance",
        .description = "Token balance. Parameters: chain, token_account (solana) or owner+mint (solana) or token_address+owner (evm), network (optional), endpoint (optional)",
        .handler = token_balance.handle,
    },
};

/// Register all unified tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
