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
const sign_and_send = @import("sign_and_send.zig");
const wallet_status = @import("wallet_status.zig");

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
    .{
        .name = "sign_and_send",
        .description = "Sign and send transaction using local or Privy wallet. Parameters: chain (solana/ethereum), transaction (base64), wallet_type (local/privy), wallet_id (for privy), keypair_path (for local), network (optional), sponsor (optional, privy only)",
        .handler = sign_and_send.handle,
    },
    .{
        .name = "wallet_status",
        .description = "Get available wallet configurations. Parameters: chain (optional, filter by solana/ethereum). Shows local and Privy wallet availability.",
        .handler = wallet_status.handle,
    },
};

/// Register all unified tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
