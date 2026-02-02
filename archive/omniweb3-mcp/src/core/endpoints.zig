//! Centralized RPC endpoint configuration.
//!
//! All external service endpoints should be defined here for easy maintenance.
//! When APIs are updated or deprecated, only this file needs to be modified.

const std = @import("std");

// =============================================================================
// Solana RPC Endpoints
// =============================================================================

pub const solana = struct {
    pub const mainnet = "https://api.mainnet-beta.solana.com";
    pub const devnet = "https://api.devnet.solana.com";
    pub const testnet = "https://api.testnet.solana.com";
    pub const localhost = "http://localhost:8899";

    /// Resolve Solana RPC endpoint by network name.
    /// Returns devnet as default for unknown networks.
    pub fn resolve(network: []const u8) []const u8 {
        if (std.mem.eql(u8, network, "mainnet")) return mainnet;
        if (std.mem.eql(u8, network, "testnet")) return testnet;
        if (std.mem.eql(u8, network, "localhost")) return localhost;
        return devnet;
    }
};

// =============================================================================
// Jupiter API Endpoints
// Docs: https://dev.jup.ag/api-reference
// =============================================================================

pub const jupiter = struct {
    /// Base URL for Jupiter API
    pub const base = "https://api.jup.ag";

    // =========================================================================
    // Metis Swap API
    // =========================================================================

    /// GET /swap/v1/quote - Quote endpoint
    pub const quote = base ++ "/swap/v1/quote";

    /// POST /swap/v1/swap - Swap transaction
    pub const swap = base ++ "/swap/v1/swap";

    /// GET /swap/v1/program-id-to-label - DEX program labels
    pub const program_labels = base ++ "/swap/v1/program-id-to-label";

    // =========================================================================
    // Price API V3
    // =========================================================================

    /// GET /price/v3 - Token prices
    pub const price = base ++ "/price/v3";

    // =========================================================================
    // Ultra Swap API
    // =========================================================================

    /// POST /ultra/v1/order - Order endpoint
    pub const ultra_order = base ++ "/ultra/v1/order";

    /// POST /ultra/v1/execute - Execute endpoint
    pub const ultra_execute = base ++ "/ultra/v1/execute";

    /// GET /ultra/v1/balances - Token balances
    pub const ultra_balances = base ++ "/ultra/v1/balances";

    /// GET /ultra/v1/holdings - Detailed holdings
    pub const ultra_holdings = base ++ "/ultra/v1/holdings";

    /// GET /ultra/v1/shield - Token warnings
    pub const ultra_shield = base ++ "/ultra/v1/shield";

    /// GET /ultra/v1/search - Token search
    pub const ultra_search = base ++ "/ultra/v1/search";

    /// GET /ultra/v1/routers - Available routers
    pub const ultra_routers = base ++ "/ultra/v1/routers";

    // =========================================================================
    // Tokens API V2
    // =========================================================================

    /// GET /tokens/v2/search - Search tokens
    pub const tokens_search = base ++ "/tokens/v2/search";

    /// GET /tokens/v2/tag/{tag} - Get tokens by tag
    pub const tokens_tag = base ++ "/tokens/v2/tag";

    /// GET /tokens/v2/category/{category}/{interval} - Get tokens by category
    pub const tokens_category = base ++ "/tokens/v2/category";

    /// GET /tokens/v2/recent - Recently created tokens
    pub const tokens_recent = base ++ "/tokens/v2/recent";

    // =========================================================================
    // Portfolio API
    // =========================================================================

    /// GET /portfolio/v1/positions - User positions
    pub const portfolio_positions = base ++ "/portfolio/v1/positions";

    /// GET /portfolio/v1/platforms - Available platforms
    pub const portfolio_platforms = base ++ "/portfolio/v1/platforms";

    /// GET /portfolio/v1/staked-jup - Staked JUP info
    pub const portfolio_staked_jup = base ++ "/portfolio/v1/staked-jup";

    // =========================================================================
    // Trigger API (Limit Orders)
    // =========================================================================

    /// GET /trigger/v1/getTriggerOrders - Get trigger orders
    pub const trigger_orders = base ++ "/trigger/v1/getTriggerOrders";

    // =========================================================================
    // Recurring API (DCA)
    // =========================================================================

    /// GET /recurring/v1/getRecurringOrders - Get recurring orders
    pub const recurring_orders = base ++ "/recurring/v1/getRecurringOrders";

    // =========================================================================
    // Lend API (Earn)
    // =========================================================================

    /// GET /lend/v1/earn/positions - Lending positions
    pub const lend_positions = base ++ "/lend/v1/earn/positions";

    /// GET /lend/v1/earn/earnings - Lending earnings
    pub const lend_earnings = base ++ "/lend/v1/earn/earnings";

    /// GET /lend/v1/earn/tokens - Available lending tokens
    pub const lend_tokens = base ++ "/lend/v1/earn/tokens";

    /// POST /lend/v1/earn/mint - Mint lending shares
    pub const lend_mint = base ++ "/lend/v1/earn/mint";

    /// POST /lend/v1/earn/redeem - Redeem lending shares
    pub const lend_redeem = base ++ "/lend/v1/earn/redeem";

    // =========================================================================
    // Send API
    // =========================================================================

    /// POST /send/v1/craft-send - Create send transaction
    pub const send_craft = base ++ "/send/v1/craft-send";

    /// POST /send/v1/craft-clawback - Create clawback transaction
    pub const send_clawback = base ++ "/send/v1/craft-clawback";

    /// GET /send/v1/pending-invites - Get pending invites
    pub const send_pending = base ++ "/send/v1/pending-invites";

    /// GET /send/v1/invite-history - Get invite history
    pub const send_history = base ++ "/send/v1/invite-history";

    // =========================================================================
    // Studio API (Token Creation)
    // =========================================================================

    /// GET /studio/v1/dbc-fee - Get unclaimed DBC fees
    pub const studio_dbc_fee = base ++ "/studio/v1/dbc-fee";

    /// POST /studio/v1/dbc-fee-create-tx - Create fee claim transaction
    pub const studio_dbc_fee_claim = base ++ "/studio/v1/dbc-fee-create-tx";

    /// GET /studio/v1/dbc-pool-addresses-by-mint - Get pool addresses
    pub const studio_dbc_pools = base ++ "/studio/v1/dbc-pool-addresses-by-mint";

    /// POST /studio/v1/dbc-pool-create-tx - Create pool transaction
    pub const studio_dbc_create = base ++ "/studio/v1/dbc-pool-create-tx";

    /// POST /studio/v1/dbc-pool-submit - Submit pool creation
    pub const studio_dbc_submit = base ++ "/studio/v1/dbc-pool-submit";

    // =========================================================================
    // Tokens V2 Content API
    // =========================================================================

    /// POST /tokens/v2/content - Get content for mints
    pub const tokens_content = base ++ "/tokens/v2/content";

    /// GET /tokens/v2/content/cooking - Get trending token content
    pub const tokens_content_cooking = base ++ "/tokens/v2/content/cooking";

    /// GET /tokens/v2/content/feed/{mint} - Get paginated content feed
    pub const tokens_content_feed = base ++ "/tokens/v2/content/feed";

    // =========================================================================
    // Trigger API - Batch Operations
    // =========================================================================

    /// POST /trigger/v1/cancelOrders - Batch cancel orders
    pub const trigger_cancel_batch = base ++ "/trigger/v1/cancelOrders";
};

// =============================================================================
// EVM RPC Endpoints (for future use)
// =============================================================================

pub const evm = struct {
    pub const ethereum = struct {
        pub const mainnet = "https://eth.llamarpc.com";
        pub const sepolia = "https://rpc.sepolia.org";
        pub const localhost = "http://localhost:8545";
    };

    pub const bsc = struct {
        pub const mainnet = "https://bsc-dataseed.binance.org";
        pub const testnet = "https://data-seed-prebsc-1-s1.binance.org:8545";
    };

    pub const avalanche = struct {
        pub const mainnet = "https://api.avax.network/ext/bc/C/rpc";
        pub const fuji = "https://api.avax-test.network/ext/bc/C/rpc";
    };

    pub const polygon = struct {
        pub const mainnet = "https://polygon-rpc.com";
        pub const mumbai = "https://rpc-mumbai.maticvigil.com";
    };

    pub const arbitrum = struct {
        pub const mainnet = "https://arb1.arbitrum.io/rpc";
        pub const sepolia = "https://sepolia-rollup.arbitrum.io/rpc";
    };

    pub const optimism = struct {
        pub const mainnet = "https://mainnet.optimism.io";
        pub const sepolia = "https://sepolia.optimism.io";
    };

    pub const base = struct {
        pub const mainnet = "https://mainnet.base.org";
        pub const sepolia = "https://sepolia.base.org";
    };
};

// =============================================================================
// dFlow Swap API Endpoints
// Docs: https://pond.dflow.net/swap-api-reference/introduction
// =============================================================================

pub const dflow = struct {
    /// Base URL for dFlow Swap API
    pub const base = "https://quote-api.dflow.net";

    /// Base URL for dFlow Prediction Market Metadata API
    pub const prediction_base = "https://prediction-market-metadata-api.dflow.net";

    // =========================================================================
    // Order API
    // =========================================================================

    /// GET /order - Get order with quote and optional transaction
    pub const order = base ++ "/order";

    /// GET /order-status - Check order status by signature
    pub const order_status = base ++ "/order-status";

    // =========================================================================
    // Imperative Swap API (precise route control)
    // =========================================================================

    /// GET /quote - Get swap quote
    pub const quote = base ++ "/quote";

    /// POST /swap - Create swap transaction from quote
    pub const swap = base ++ "/swap";

    /// POST /swap-instructions - Get swap instructions (not full transaction)
    pub const swap_instructions = base ++ "/swap-instructions";

    // =========================================================================
    // Declarative Swap API (intent-based, deferred routing)
    // =========================================================================

    /// GET /intent - Get intent quote
    pub const intent = base ++ "/intent";

    /// POST /submit-intent - Submit signed intent transaction
    pub const submit_intent = base ++ "/submit-intent";

    // =========================================================================
    // Token APIs
    // =========================================================================

    /// GET /tokens - List supported tokens
    pub const tokens = base ++ "/tokens";

    /// GET /tokens-with-decimals - List tokens with decimal precision
    pub const tokens_with_decimals = base ++ "/tokens-with-decimals";

    // =========================================================================
    // Venue APIs
    // =========================================================================

    /// GET /venues - List supported DEX venues
    pub const venues = base ++ "/venues";

    // =========================================================================
    // Prediction Market Swap API
    // =========================================================================

    /// POST /prediction-market-init - Initialize prediction market
    pub const prediction_market_init = base ++ "/prediction-market-init";

    // =========================================================================
    // Prediction Market Metadata API - Events
    // =========================================================================

    /// GET /events - Get paginated list of events
    pub const pm_events = prediction_base ++ "/events";

    /// GET /events/{ticker} - Get single event by ticker
    pub const pm_event = prediction_base ++ "/events";

    /// GET /events/{ticker}/candlesticks - Get event candlesticks
    pub const pm_event_candlesticks = prediction_base ++ "/events";

    /// GET /events/{ticker}/forecast-percentile-history - Get forecast history
    pub const pm_event_forecast = prediction_base ++ "/events";

    /// GET /events/forecast-percentile-history-by-mint - Get forecast by mint
    pub const pm_event_forecast_by_mint = prediction_base ++ "/events/forecast-percentile-history-by-mint";

    // =========================================================================
    // Prediction Market Metadata API - Markets
    // =========================================================================

    /// GET /markets - Get paginated list of markets
    pub const pm_markets = prediction_base ++ "/markets";

    /// GET /markets/{ticker} - Get single market by ticker
    pub const pm_market = prediction_base ++ "/markets";

    /// GET /markets/by-mint/{mint} - Get market by mint address
    pub const pm_market_by_mint = prediction_base ++ "/markets/by-mint";

    /// GET /markets/{ticker}/candlesticks - Get market candlesticks
    pub const pm_market_candlesticks = prediction_base ++ "/markets";

    /// GET /markets/candlesticks-by-mint/{mint} - Get candlesticks by mint
    pub const pm_market_candlesticks_by_mint = prediction_base ++ "/markets/candlesticks-by-mint";

    /// POST /markets/batch - Get multiple markets by tickers/mints
    pub const pm_markets_batch = prediction_base ++ "/markets/batch";

    /// GET /markets/outcome-mints - Get all outcome mints
    pub const pm_outcome_mints = prediction_base ++ "/markets/outcome-mints";

    /// POST /markets/filter-outcome-mints - Filter addresses to outcome mints
    pub const pm_filter_outcome_mints = prediction_base ++ "/markets/filter-outcome-mints";

    // =========================================================================
    // Prediction Market Metadata API - Orderbook
    // =========================================================================

    /// GET /orderbook/{ticker} - Get orderbook by ticker
    pub const pm_orderbook = prediction_base ++ "/orderbook";

    /// GET /orderbook/by-mint/{mint} - Get orderbook by mint
    pub const pm_orderbook_by_mint = prediction_base ++ "/orderbook/by-mint";

    // =========================================================================
    // Prediction Market Metadata API - Trades
    // =========================================================================

    /// GET /trades - Get paginated trades
    pub const pm_trades = prediction_base ++ "/trades";

    /// GET /trades/by-mint/{mint} - Get trades by mint
    pub const pm_trades_by_mint = prediction_base ++ "/trades/by-mint";

    // =========================================================================
    // Prediction Market Metadata API - Live Data
    // =========================================================================

    /// GET /live-data - Get live data for milestones
    pub const pm_live_data = prediction_base ++ "/live-data";

    /// GET /live-data/by-event/{ticker} - Get live data by event
    pub const pm_live_data_by_event = prediction_base ++ "/live-data/by-event";

    /// GET /live-data/by-mint/{mint} - Get live data by mint
    pub const pm_live_data_by_mint = prediction_base ++ "/live-data/by-mint";

    // =========================================================================
    // Prediction Market Metadata API - Series
    // =========================================================================

    /// GET /series - Get all series templates
    pub const pm_series = prediction_base ++ "/series";

    /// GET /series/{ticker} - Get series by ticker
    pub const pm_series_by_ticker = prediction_base ++ "/series";

    // =========================================================================
    // Prediction Market Metadata API - Search, Tags, Sports
    // =========================================================================

    /// GET /search - Search events with nested markets
    pub const pm_search = prediction_base ++ "/search";

    /// GET /tags/by-categories - Get tags by categories
    pub const pm_tags = prediction_base ++ "/tags/by-categories";

    /// GET /sports/filters - Get filters by sports
    pub const pm_sports_filters = prediction_base ++ "/sports/filters";
};

// =============================================================================
// Meteora API Endpoints
// Docs: https://docs.meteora.ag/api-reference
// =============================================================================

pub const meteora = struct {
    /// Base URL for Meteora DLMM API
    pub const dlmm_base = "https://dlmm-api.meteora.ag";

    /// Base URL for Meteora DAMM API
    pub const damm_base = "https://amm-v2.meteora.ag";

    // =========================================================================
    // DLMM (Dynamic Liquidity Market Maker) API
    // =========================================================================

    /// GET /pair/all - Get all DLMM pairs
    pub const dlmm_pairs_all = dlmm_base ++ "/pair/all";

    /// GET /pair/{address} - Get specific DLMM pair info
    pub const dlmm_pair = dlmm_base ++ "/pair";

    /// GET /pair/all_by_groups - Get pairs grouped by base token
    pub const dlmm_pairs_by_groups = dlmm_base ++ "/pair/all_by_groups";

    // =========================================================================
    // DAMM (Dynamic AMM) API
    // =========================================================================

    /// GET /pool/list - Get all DAMM pools
    pub const damm_pools = damm_base ++ "/pool/list";

    /// GET /pool/{address} - Get specific DAMM pool info
    pub const damm_pool = damm_base ++ "/pool";
};
