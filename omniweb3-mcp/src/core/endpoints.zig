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
