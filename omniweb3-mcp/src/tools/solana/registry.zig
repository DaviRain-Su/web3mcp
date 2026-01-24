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

// =============================================================================
// DeFi integrations - Jupiter (organized by API category)
// =============================================================================

// Jupiter Swap API (Metis)
const get_jupiter_quote = @import("defi/jupiter/swap/get_quote.zig");
const jupiter_swap = @import("defi/jupiter/swap/swap.zig");
const get_jupiter_program_labels = @import("defi/jupiter/swap/get_program_labels.zig");

// Jupiter Price API
const get_jupiter_price = @import("defi/jupiter/price/get_price.zig");

// Jupiter Ultra API
const jupiter_ultra_order = @import("defi/jupiter/ultra/ultra_order.zig");
const jupiter_ultra_execute = @import("defi/jupiter/ultra/ultra_execute.zig");
const get_jupiter_balances = @import("defi/jupiter/ultra/get_balances.zig");
const get_jupiter_holdings = @import("defi/jupiter/ultra/get_holdings.zig");
const get_jupiter_shield = @import("defi/jupiter/ultra/get_shield.zig");
const jupiter_ultra_search = @import("defi/jupiter/ultra/ultra_search.zig");
const get_jupiter_routers = @import("defi/jupiter/ultra/get_routers.zig");

// Jupiter Trigger API (Limit Orders)
const jupiter_create_trigger_order = @import("defi/jupiter/trigger/create_trigger_order.zig");
const jupiter_cancel_trigger_order = @import("defi/jupiter/trigger/cancel_trigger_order.zig");
const jupiter_cancel_trigger_orders = @import("defi/jupiter/trigger/cancel_trigger_orders.zig");
const jupiter_execute_trigger = @import("defi/jupiter/trigger/execute_trigger.zig");
const get_jupiter_trigger_orders = @import("defi/jupiter/trigger/get_trigger_orders.zig");

// Jupiter Recurring API (DCA)
const jupiter_create_recurring_order = @import("defi/jupiter/recurring/create_recurring_order.zig");
const jupiter_cancel_recurring_order = @import("defi/jupiter/recurring/cancel_recurring_order.zig");
const jupiter_execute_recurring = @import("defi/jupiter/recurring/execute_recurring.zig");
const get_jupiter_recurring_orders = @import("defi/jupiter/recurring/get_recurring_orders.zig");

// Jupiter Lend API (Earn)
const jupiter_lend_deposit = @import("defi/jupiter/lend/lend_deposit.zig");
const jupiter_lend_withdraw = @import("defi/jupiter/lend/lend_withdraw.zig");
const jupiter_lend_mint = @import("defi/jupiter/lend/lend_mint.zig");
const jupiter_lend_redeem = @import("defi/jupiter/lend/lend_redeem.zig");
const get_jupiter_lend_tokens = @import("defi/jupiter/lend/get_lend_tokens.zig");
const get_jupiter_lend_positions = @import("defi/jupiter/lend/get_lend_positions.zig");
const get_jupiter_lend_earnings = @import("defi/jupiter/lend/get_lend_earnings.zig");

// Jupiter Send API
const jupiter_craft_send = @import("defi/jupiter/send/craft_send.zig");
const jupiter_craft_clawback = @import("defi/jupiter/send/craft_clawback.zig");
const jupiter_pending_invites = @import("defi/jupiter/send/get_pending_invites.zig");
const jupiter_invite_history = @import("defi/jupiter/send/get_invite_history.zig");

// Jupiter Studio API (Token Creation)
const jupiter_get_dbc_fee = @import("defi/jupiter/studio/get_dbc_fee.zig");
const jupiter_claim_dbc_fee = @import("defi/jupiter/studio/claim_dbc_fee.zig");
const jupiter_get_dbc_pools = @import("defi/jupiter/studio/get_dbc_pools.zig");
const jupiter_create_dbc_pool = @import("defi/jupiter/studio/create_dbc_pool.zig");
const jupiter_submit_dbc_pool = @import("defi/jupiter/studio/submit_dbc_pool.zig");

// Jupiter Tokens API V2
const search_jupiter_tokens = @import("defi/jupiter/tokens/search_tokens.zig");
const get_jupiter_tokens_by_tag = @import("defi/jupiter/tokens/get_tokens_by_tag.zig");
const get_jupiter_tokens_by_category = @import("defi/jupiter/tokens/get_tokens_by_category.zig");
const get_jupiter_recent_tokens = @import("defi/jupiter/tokens/get_recent_tokens.zig");
const jupiter_get_tokens_content = @import("defi/jupiter/tokens/get_tokens_content.zig");
const jupiter_get_tokens_cooking = @import("defi/jupiter/tokens/get_tokens_cooking.zig");
const jupiter_get_tokens_feed = @import("defi/jupiter/tokens/get_tokens_feed.zig");

// Jupiter Portfolio API
const get_jupiter_positions = @import("defi/jupiter/portfolio/get_positions.zig");
const get_jupiter_platforms = @import("defi/jupiter/portfolio/get_platforms.zig");
const get_jupiter_staked_jup = @import("defi/jupiter/portfolio/get_staked_jup.zig");

// =============================================================================
// DeFi integrations - dFlow Swap API
// Docs: https://pond.dflow.net/swap-api-reference/introduction
// =============================================================================

// dFlow Imperative Swap API (precise route control)
const get_dflow_quote = @import("defi/dflow/get_quote.zig");
const dflow_swap = @import("defi/dflow/swap.zig");
const dflow_swap_instructions = @import("defi/dflow/swap_instructions.zig");

// dFlow Declarative Swap API (intent-based, deferred routing)
const get_dflow_intent = @import("defi/dflow/get_intent.zig");
const submit_dflow_intent = @import("defi/dflow/submit_intent.zig");

// dFlow Order API
const get_dflow_order = @import("defi/dflow/get_order.zig");
const get_dflow_order_status = @import("defi/dflow/get_order_status.zig");

// dFlow Token API
const get_dflow_tokens = @import("defi/dflow/get_tokens.zig");
const get_dflow_tokens_with_decimals = @import("defi/dflow/get_tokens_with_decimals.zig");

// dFlow Venue API
const get_dflow_venues = @import("defi/dflow/get_venues.zig");

// dFlow Prediction Market Swap API
const dflow_prediction_market_init = @import("defi/dflow/prediction_market_init.zig");

// dFlow Prediction Market Metadata API
const dflow_pm_get_events = @import("defi/dflow/prediction/get_events.zig");
const dflow_pm_get_event = @import("defi/dflow/prediction/get_event.zig");
const dflow_pm_get_markets = @import("defi/dflow/prediction/get_markets.zig");
const dflow_pm_get_market = @import("defi/dflow/prediction/get_market.zig");
const dflow_pm_get_market_by_mint = @import("defi/dflow/prediction/get_market_by_mint.zig");
const dflow_pm_get_outcome_mints = @import("defi/dflow/prediction/get_outcome_mints.zig");
const dflow_pm_get_orderbook = @import("defi/dflow/prediction/get_orderbook.zig");
const dflow_pm_get_orderbook_by_mint = @import("defi/dflow/prediction/get_orderbook_by_mint.zig");
const dflow_pm_get_trades = @import("defi/dflow/prediction/get_trades.zig");
const dflow_pm_get_series = @import("defi/dflow/prediction/get_series.zig");
const dflow_pm_search_events = @import("defi/dflow/prediction/search_events.zig");
const dflow_pm_get_live_data = @import("defi/dflow/prediction/get_live_data.zig");

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
        .description = "Create Jupiter Lend deposit transaction. Parameters: user, mint, amount, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_lend_deposit.handle,
    },
    .{
        .name = "jupiter_lend_withdraw",
        .description = "Create Jupiter Lend withdraw transaction. Parameters: user, mint, amount, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_lend_withdraw.handle,
    },
    .{
        .name = "jupiter_lend_mint",
        .description = "Create Jupiter Lend mint shares transaction. Parameters: user, mint, amount, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_lend_mint.handle,
    },
    .{
        .name = "jupiter_lend_redeem",
        .description = "Create Jupiter Lend redeem shares transaction. Parameters: user, mint, amount, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_lend_redeem.handle,
    },

    // DeFi - Jupiter Trigger Batch (Write)
    .{
        .name = "jupiter_cancel_trigger_orders",
        .description = "Batch cancel Jupiter trigger orders. Parameters: maker, orders (array), endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_cancel_trigger_orders.handle,
    },

    // DeFi - Jupiter Send API
    .{
        .name = "jupiter_craft_send",
        .description = "Create Jupiter Send transaction. Parameters: sender, recipient, mint, amount, memo (optional), endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_craft_send.handle,
    },
    .{
        .name = "jupiter_craft_clawback",
        .description = "Create Jupiter Send clawback transaction. Parameters: sender, invite_id, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_craft_clawback.handle,
    },
    .{
        .name = "jupiter_pending_invites",
        .description = "Get Jupiter Send pending invites. Parameters: address, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_pending_invites.handle,
    },
    .{
        .name = "jupiter_invite_history",
        .description = "Get Jupiter Send invite history. Parameters: address, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_invite_history.handle,
    },

    // DeFi - Jupiter Studio API (Token Creation)
    .{
        .name = "jupiter_get_dbc_fee",
        .description = "Get unclaimed DBC pool trading fees. Parameters: pool, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_get_dbc_fee.handle,
    },
    .{
        .name = "jupiter_claim_dbc_fee",
        .description = "Create transaction to claim DBC pool fees. Parameters: pool, creator, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_claim_dbc_fee.handle,
    },
    .{
        .name = "jupiter_get_dbc_pools",
        .description = "Get DBC pool addresses for a token mint. Parameters: mint, endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_get_dbc_pools.handle,
    },
    .{
        .name = "jupiter_create_dbc_pool",
        .description = "Create DBC pool transaction. Parameters: creator, name, symbol, uri, decimals (optional), total_supply (optional), endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_create_dbc_pool.handle,
    },
    .{
        .name = "jupiter_submit_dbc_pool",
        .description = "Submit signed DBC pool creation. Parameters: signed_transaction, content_image (optional), header_image (optional), endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_submit_dbc_pool.handle,
    },

    // DeFi - Jupiter Tokens V2 Content API
    .{
        .name = "jupiter_get_tokens_content",
        .description = "Get content for multiple token mints (max 50). Parameters: mints (array), endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_get_tokens_content.handle,
    },
    .{
        .name = "jupiter_get_tokens_cooking",
        .description = "Get content for trending (cooking) tokens. Parameters: endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_get_tokens_cooking.handle,
    },
    .{
        .name = "jupiter_get_tokens_feed",
        .description = "Get paginated content feed for a token. Parameters: mint, page (optional), limit (optional), endpoint (optional). API key from JUPITER_API_KEY env var.",
        .handler = jupiter_get_tokens_feed.handle,
    },

    // =========================================================================
    // DeFi - dFlow Swap API
    // =========================================================================

    // dFlow Imperative Swap (precise route control)
    .{
        .name = "get_dflow_quote",
        .description = "Get dFlow swap quote. Parameters: input_mint, output_mint, amount, slippage_bps (optional), user_public_key (optional). API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_quote.handle,
    },
    .{
        .name = "dflow_swap",
        .description = "Create dFlow swap transaction from quote. Parameters: quote (from get_dflow_quote), user_public_key. API key from DFLOW_API_KEY env var.",
        .handler = dflow_swap.handle,
    },

    // dFlow Declarative Swap (intent-based, deferred routing)
    .{
        .name = "get_dflow_intent",
        .description = "Get dFlow intent quote for declarative swap. Parameters: input_mint, output_mint, amount, slippage_bps (optional), user_public_key. API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_intent.handle,
    },
    .{
        .name = "submit_dflow_intent",
        .description = "Submit signed dFlow intent transaction. Parameters: signed_transaction. API key from DFLOW_API_KEY env var.",
        .handler = submit_dflow_intent.handle,
    },

    // dFlow Order API
    .{
        .name = "get_dflow_order",
        .description = "Get dFlow order with quote and optional transaction. Parameters: input_mint, output_mint, amount, slippage_bps (optional), user_public_key (optional), include_tx (optional). API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_order.handle,
    },
    .{
        .name = "get_dflow_order_status",
        .description = "Get dFlow order status by signature. Parameters: signature. API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_order_status.handle,
    },

    // dFlow Token API
    .{
        .name = "get_dflow_tokens",
        .description = "Get list of supported tokens on dFlow. Parameters: none. API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_tokens.handle,
    },
    .{
        .name = "get_dflow_tokens_with_decimals",
        .description = "Get tokens with decimal precision on dFlow. Parameters: none. API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_tokens_with_decimals.handle,
    },

    // dFlow Venue API
    .{
        .name = "get_dflow_venues",
        .description = "Get list of supported DEX venues on dFlow. Parameters: none. API key from DFLOW_API_KEY env var.",
        .handler = get_dflow_venues.handle,
    },

    // dFlow Additional Swap API
    .{
        .name = "dflow_swap_instructions",
        .description = "Get dFlow swap instructions (not full tx). Parameters: quote, user_public_key. API key from DFLOW_API_KEY env var.",
        .handler = dflow_swap_instructions.handle,
    },
    .{
        .name = "dflow_prediction_market_init",
        .description = "Initialize dFlow prediction market position. Parameters: user_public_key, market_ticker, side (yes/no), amount, slippage_bps (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_prediction_market_init.handle,
    },

    // =========================================================================
    // DeFi - dFlow Prediction Market Metadata API
    // =========================================================================

    // Events
    .{
        .name = "dflow_pm_get_events",
        .description = "Get paginated prediction market events. Parameters: limit (optional), cursor (optional), include_markets (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_events.handle,
    },
    .{
        .name = "dflow_pm_get_event",
        .description = "Get single prediction market event by ticker. Parameters: ticker, include_markets (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_event.handle,
    },

    // Markets
    .{
        .name = "dflow_pm_get_markets",
        .description = "Get paginated prediction markets. Parameters: limit (optional), cursor (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_markets.handle,
    },
    .{
        .name = "dflow_pm_get_market",
        .description = "Get single prediction market by ticker. Parameters: ticker. API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_market.handle,
    },
    .{
        .name = "dflow_pm_get_market_by_mint",
        .description = "Get prediction market by mint address. Parameters: mint. API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_market_by_mint.handle,
    },
    .{
        .name = "dflow_pm_get_outcome_mints",
        .description = "Get all outcome mints from prediction markets. Parameters: min_close_ts (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_outcome_mints.handle,
    },

    // Orderbook
    .{
        .name = "dflow_pm_get_orderbook",
        .description = "Get prediction market orderbook by ticker. Parameters: ticker. API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_orderbook.handle,
    },
    .{
        .name = "dflow_pm_get_orderbook_by_mint",
        .description = "Get prediction market orderbook by mint. Parameters: mint. API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_orderbook_by_mint.handle,
    },

    // Trades
    .{
        .name = "dflow_pm_get_trades",
        .description = "Get prediction market trades. Parameters: ticker (optional), limit (optional), cursor (optional), min_ts (optional), max_ts (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_trades.handle,
    },

    // Series
    .{
        .name = "dflow_pm_get_series",
        .description = "Get all prediction market series templates. Parameters: none. API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_series.handle,
    },

    // Search
    .{
        .name = "dflow_pm_search_events",
        .description = "Search prediction market events. Parameters: query, limit (optional). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_search_events.handle,
    },

    // Live Data
    .{
        .name = "dflow_pm_get_live_data",
        .description = "Get live data for prediction market milestones. Parameters: milestones (comma-separated). API key from DFLOW_API_KEY env var.",
        .handler = dflow_pm_get_live_data.handle,
    },
};

/// Register all Solana tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
