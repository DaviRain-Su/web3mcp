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

// DeFi integrations - Jupiter
const get_jupiter_quote = @import("defi/jupiter/get_quote.zig");
const get_jupiter_price = @import("defi/jupiter/get_price.zig");
const search_jupiter_tokens = @import("defi/jupiter/search_tokens.zig");
const get_jupiter_tokens_by_tag = @import("defi/jupiter/get_tokens_by_tag.zig");
const get_jupiter_recent_tokens = @import("defi/jupiter/get_recent_tokens.zig");
const get_jupiter_balances = @import("defi/jupiter/get_balances.zig");
const get_jupiter_holdings = @import("defi/jupiter/get_holdings.zig");
const get_jupiter_shield = @import("defi/jupiter/get_shield.zig");
const get_jupiter_positions = @import("defi/jupiter/get_positions.zig");
const get_jupiter_platforms = @import("defi/jupiter/get_platforms.zig");
const get_jupiter_trigger_orders = @import("defi/jupiter/get_trigger_orders.zig");
const get_jupiter_recurring_orders = @import("defi/jupiter/get_recurring_orders.zig");
const get_jupiter_lend_tokens = @import("defi/jupiter/get_lend_tokens.zig");
const get_jupiter_lend_positions = @import("defi/jupiter/get_lend_positions.zig");
const get_jupiter_program_labels = @import("defi/jupiter/get_program_labels.zig");

// Jupiter - Additional readonly APIs
const get_jupiter_tokens_by_category = @import("defi/jupiter/get_tokens_by_category.zig");
const jupiter_ultra_search = @import("defi/jupiter/ultra_search.zig");
const get_jupiter_routers = @import("defi/jupiter/get_routers.zig");
const get_jupiter_staked_jup = @import("defi/jupiter/get_staked_jup.zig");
const get_jupiter_lend_earnings = @import("defi/jupiter/get_lend_earnings.zig");

// Jupiter - Write APIs (transaction builders)
const jupiter_swap = @import("defi/jupiter/swap.zig");
const jupiter_ultra_order = @import("defi/jupiter/ultra_order.zig");
const jupiter_ultra_execute = @import("defi/jupiter/ultra_execute.zig");
const jupiter_create_trigger_order = @import("defi/jupiter/create_trigger_order.zig");
const jupiter_cancel_trigger_order = @import("defi/jupiter/cancel_trigger_order.zig");
const jupiter_execute_trigger = @import("defi/jupiter/execute_trigger.zig");
const jupiter_create_recurring_order = @import("defi/jupiter/create_recurring_order.zig");
const jupiter_cancel_recurring_order = @import("defi/jupiter/cancel_recurring_order.zig");
const jupiter_execute_recurring = @import("defi/jupiter/execute_recurring.zig");
const jupiter_lend_deposit = @import("defi/jupiter/lend_deposit.zig");
const jupiter_lend_withdraw = @import("defi/jupiter/lend_withdraw.zig");

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

    // DeFi - Jupiter Swap & Price
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

    // DeFi - Jupiter Tokens API
    .{
        .name = "search_jupiter_tokens",
        .description = "Search Jupiter tokens by symbol, name or mint. Parameters: query, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = search_jupiter_tokens.handle,
    },
    .{
        .name = "get_jupiter_tokens_by_tag",
        .description = "Get Jupiter tokens by tag (verified, community, lst, pump). Parameters: tag, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_tokens_by_tag.handle,
    },
    .{
        .name = "get_jupiter_recent_tokens",
        .description = "Get recently created tokens on Jupiter. Parameters: endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_recent_tokens.handle,
    },

    // DeFi - Jupiter Ultra API
    .{
        .name = "get_jupiter_balances",
        .description = "Get Jupiter Ultra token balances. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_balances.handle,
    },
    .{
        .name = "get_jupiter_holdings",
        .description = "Get Jupiter Ultra detailed token holdings. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_holdings.handle,
    },
    .{
        .name = "get_jupiter_shield",
        .description = "Get Jupiter token safety info and warnings. Parameters: mints (comma-separated), endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_shield.handle,
    },

    // DeFi - Jupiter Portfolio API
    .{
        .name = "get_jupiter_positions",
        .description = "Get Jupiter portfolio positions. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_positions.handle,
    },
    .{
        .name = "get_jupiter_platforms",
        .description = "Get Jupiter portfolio platforms. Parameters: endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_platforms.handle,
    },

    // DeFi - Jupiter Trigger (Limit Orders)
    .{
        .name = "get_jupiter_trigger_orders",
        .description = "Get Jupiter trigger (limit) orders. Parameters: account, status (active|history, optional), endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_trigger_orders.handle,
    },

    // DeFi - Jupiter Recurring (DCA)
    .{
        .name = "get_jupiter_recurring_orders",
        .description = "Get Jupiter recurring (DCA) orders. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_recurring_orders.handle,
    },

    // DeFi - Jupiter Lend (Earn)
    .{
        .name = "get_jupiter_lend_tokens",
        .description = "Get available Jupiter Lend tokens. Parameters: endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_lend_tokens.handle,
    },
    .{
        .name = "get_jupiter_lend_positions",
        .description = "Get Jupiter Lend positions. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_lend_positions.handle,
    },

    // DeFi - Jupiter Misc
    .{
        .name = "get_jupiter_program_labels",
        .description = "Get DEX program ID to label mapping. Parameters: endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_program_labels.handle,
    },
    .{
        .name = "get_jupiter_tokens_by_category",
        .description = "Get Jupiter tokens by category. Parameters: category (pump, moonshot), interval (5m, 1h, 6h, 24h), endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_tokens_by_category.handle,
    },
    .{
        .name = "jupiter_ultra_search",
        .description = "Search tokens via Jupiter Ultra API. Parameters: query, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = jupiter_ultra_search.handle,
    },
    .{
        .name = "get_jupiter_routers",
        .description = "Get available routers in Jupiter Ultra. Parameters: endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_routers.handle,
    },
    .{
        .name = "get_jupiter_staked_jup",
        .description = "Get staked JUP info. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_staked_jup.handle,
    },
    .{
        .name = "get_jupiter_lend_earnings",
        .description = "Get Jupiter Lend earnings. Parameters: account, endpoint (optional), api_key (optional), insecure (optional)",
        .handler = get_jupiter_lend_earnings.handle,
    },

    // DeFi - Jupiter Swap (Write)
    .{
        .name = "jupiter_swap",
        .description = "Build Jupiter swap transaction. Parameters: quote_response (JSON), user_public_key, wrap_unwrap_sol (optional), use_shared_accounts (optional), fee_account (optional), compute_unit_price_micro_lamports (optional), endpoint (optional), api_key (optional)",
        .handler = jupiter_swap.handle,
    },

    // DeFi - Jupiter Ultra (Write)
    .{
        .name = "jupiter_ultra_order",
        .description = "Create Jupiter Ultra swap order. Parameters: input_mint, output_mint, amount, taker, slippage_bps (optional), endpoint (optional), api_key (optional)",
        .handler = jupiter_ultra_order.handle,
    },
    .{
        .name = "jupiter_ultra_execute",
        .description = "Execute signed Jupiter Ultra transaction. Parameters: signed_transaction, request_id (optional), endpoint (optional), api_key (optional)",
        .handler = jupiter_ultra_execute.handle,
    },

    // DeFi - Jupiter Trigger (Write)
    .{
        .name = "jupiter_create_trigger_order",
        .description = "Create Jupiter trigger (limit) order. Parameters: input_mint, output_mint, maker, making_amount, taking_amount, expired_at (optional), endpoint (optional), api_key (optional)",
        .handler = jupiter_create_trigger_order.handle,
    },
    .{
        .name = "jupiter_cancel_trigger_order",
        .description = "Cancel Jupiter trigger order. Parameters: maker, order, endpoint (optional), api_key (optional)",
        .handler = jupiter_cancel_trigger_order.handle,
    },
    .{
        .name = "jupiter_execute_trigger",
        .description = "Execute signed Jupiter trigger transaction. Parameters: signed_transaction, endpoint (optional), api_key (optional)",
        .handler = jupiter_execute_trigger.handle,
    },

    // DeFi - Jupiter Recurring (Write)
    .{
        .name = "jupiter_create_recurring_order",
        .description = "Create Jupiter recurring (DCA) order. Parameters: user, input_mint, output_mint, in_amount, in_amount_per_cycle, cycle_frequency, min_out_amount_per_cycle (optional), max_out_amount_per_cycle (optional), start_at (optional), endpoint (optional), api_key (optional)",
        .handler = jupiter_create_recurring_order.handle,
    },
    .{
        .name = "jupiter_cancel_recurring_order",
        .description = "Cancel Jupiter recurring order. Parameters: user, order, endpoint (optional), api_key (optional)",
        .handler = jupiter_cancel_recurring_order.handle,
    },
    .{
        .name = "jupiter_execute_recurring",
        .description = "Execute signed Jupiter recurring transaction. Parameters: signed_transaction, endpoint (optional), api_key (optional)",
        .handler = jupiter_execute_recurring.handle,
    },

    // DeFi - Jupiter Lend (Write)
    .{
        .name = "jupiter_lend_deposit",
        .description = "Create Jupiter Lend deposit transaction. Parameters: user, mint, amount, endpoint (optional), api_key (optional)",
        .handler = jupiter_lend_deposit.handle,
    },
    .{
        .name = "jupiter_lend_withdraw",
        .description = "Create Jupiter Lend withdraw transaction. Parameters: user, mint, amount, endpoint (optional), api_key (optional)",
        .handler = jupiter_lend_withdraw.handle,
    },
};

/// Register all Solana tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
