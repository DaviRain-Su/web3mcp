//! Solana chain tools registry.
//!
//! Registers tools specific to Solana blockchain.
//! Includes RPC tools, token operations, and DeFi integrations.

const mcp = @import("mcp");

// Core Solana RPC tools
const token_balances = @import("token_balances.zig");
const token_accounts = @import("token_accounts.zig");
const account_info = @import("account_info.zig");
const signature_status = @import("signature_status.zig");
const request_airdrop = @import("request_airdrop.zig");
const tps = @import("tps.zig");
const slot = @import("slot.zig");
const block_height = @import("block_height.zig");
const parse_transaction = @import("parse_transaction.zig");
const epoch_info = @import("epoch_info.zig");
const version = @import("version.zig");
const supply = @import("supply.zig");
const token_supply = @import("token_supply.zig");
const token_largest_accounts = @import("token_largest_accounts.zig");
const signatures_for_address = @import("signatures_for_address.zig");
const block_time = @import("block_time.zig");
const get_wallet_address = @import("get_wallet_address.zig");
const close_empty_token_accounts = @import("close_empty_token_accounts.zig");
const get_latest_blockhash = @import("get_latest_blockhash.zig");
const get_minimum_balance_for_rent_exemption = @import("get_minimum_balance_for_rent_exemption.zig");
const get_fee_for_message = @import("get_fee_for_message.zig");
const get_program_accounts = @import("get_program_accounts.zig");
const get_vote_accounts = @import("get_vote_accounts.zig");

// DeFi integrations
const get_jupiter_quote = @import("defi/jupiter/get_quote.zig");
const get_jupiter_price = @import("defi/jupiter/get_price.zig");

/// Tool definitions for Solana-specific operations.
pub const tools = [_]mcp.tools.Tool{
    // Token operations
    .{
        .name = "token_balances",
        .description = "Solana token balances by owner. Parameters: chain=solana, owner (optional), mint (optional), network (optional), endpoint (optional)",
        .handler = token_balances.handle,
    },
    .{
        .name = "token_accounts",
        .description = "Solana token accounts by owner. Parameters: chain=solana, owner, mint (optional), network (optional), endpoint (optional)",
        .handler = token_accounts.handle,
    },
    .{
        .name = "get_token_supply",
        .description = "Get SPL token supply. Parameters: chain=solana, mint, network (optional), endpoint (optional)",
        .handler = token_supply.handle,
    },
    .{
        .name = "get_token_largest_accounts",
        .description = "Get SPL token largest accounts. Parameters: chain=solana, mint, network (optional), endpoint (optional)",
        .handler = token_largest_accounts.handle,
    },
    .{
        .name = "close_empty_token_accounts",
        .description = "Close empty SPL token accounts. Parameters: chain=solana, keypair_path (optional), network (optional), endpoint (optional)",
        .handler = close_empty_token_accounts.handle,
    },

    // Account operations
    .{
        .name = "account_info",
        .description = "Solana account info. Parameters: chain=solana, address, network (optional), endpoint (optional)",
        .handler = account_info.handle,
    },
    .{
        .name = "get_wallet_address",
        .description = "Get Solana wallet address from keypair. Parameters: chain=solana, keypair_path (optional)",
        .handler = get_wallet_address.handle,
    },
    .{
        .name = "get_program_accounts",
        .description = "Get program accounts. Parameters: chain=solana, program_id, network (optional), endpoint (optional)",
        .handler = get_program_accounts.handle,
    },
    .{
        .name = "get_vote_accounts",
        .description = "Get vote accounts. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = get_vote_accounts.handle,
    },

    // Transaction operations
    .{
        .name = "signature_status",
        .description = "Solana signature status. Parameters: chain=solana, signature, network (optional), endpoint (optional)",
        .handler = signature_status.handle,
    },
    .{
        .name = "parse_transaction",
        .description = "Parse Solana transaction details. Parameters: chain=solana, signature, network (optional), endpoint (optional)",
        .handler = parse_transaction.handle,
    },
    .{
        .name = "get_signatures_for_address",
        .description = "Get signatures for address. Parameters: chain=solana, address, limit/before/until (optional), network (optional), endpoint (optional)",
        .handler = signatures_for_address.handle,
    },
    .{
        .name = "get_fee_for_message",
        .description = "Get fee for a base64 transaction message. Parameters: chain=solana, message, network (optional), endpoint (optional)",
        .handler = get_fee_for_message.handle,
    },

    // Block/Slot operations
    .{
        .name = "get_slot",
        .description = "Get Solana current slot. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = slot.handle,
    },
    .{
        .name = "get_block_height",
        .description = "Get Solana current block height. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = block_height.handle,
    },
    .{
        .name = "get_block_time",
        .description = "Get Solana block time. Parameters: chain=solana, slot, network (optional), endpoint (optional)",
        .handler = block_time.handle,
    },
    .{
        .name = "get_latest_blockhash",
        .description = "Get latest Solana blockhash. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = get_latest_blockhash.handle,
    },

    // Network info
    .{
        .name = "get_epoch_info",
        .description = "Get Solana epoch info. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = epoch_info.handle,
    },
    .{
        .name = "get_version",
        .description = "Get Solana version info. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = version.handle,
    },
    .{
        .name = "get_supply",
        .description = "Get Solana supply info. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = supply.handle,
    },
    .{
        .name = "get_tps",
        .description = "Get Solana TPS from recent performance samples. Parameters: chain=solana, limit (optional), network (optional), endpoint (optional)",
        .handler = tps.handle,
    },
    .{
        .name = "get_minimum_balance_for_rent_exemption",
        .description = "Get minimum balance for rent exemption. Parameters: chain=solana, data_len, network (optional), endpoint (optional)",
        .handler = get_minimum_balance_for_rent_exemption.handle,
    },

    // Devnet/Testnet utilities
    .{
        .name = "request_airdrop",
        .description = "Request SOL airdrop (devnet/testnet). Parameters: chain=solana, amount (lamports), address (optional), network (optional), endpoint (optional)",
        .handler = request_airdrop.handle,
    },

    // DeFi - Jupiter
    .{
        .name = "get_jupiter_quote",
        .description = "Get Jupiter swap quote. Parameters: chain=solana, input_mint, output_mint, amount, swap_mode (optional), slippage_bps (optional), endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_quote.handle,
    },
    .{
        .name = "get_jupiter_price",
        .description = "Get Jupiter token price. Parameters: chain=solana, mint, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_price.handle,
    },
};

/// Register all Solana tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
