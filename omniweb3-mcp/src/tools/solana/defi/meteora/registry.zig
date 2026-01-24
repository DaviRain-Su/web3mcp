//! Meteora Protocol Tools Registry
//!
//! Registers all Meteora DeFi tools:
//! - DLMM (Dynamic Liquidity Market Maker)
//! - DAMM v2 (CP-AMM)
//! - DAMM v1 (Legacy Dynamic AMM)
//! - Dynamic Bonding Curve
//! - Vault
//! - Alpha Vault
//! - Stake-for-Fee (M3M3)

const mcp = @import("mcp");

// =============================================================================
// DLMM Tools - Concentrated Liquidity with Dynamic Fees
// =============================================================================

const dlmm_get_pool = @import("dlmm/get_pool.zig");
const dlmm_get_active_bin = @import("dlmm/get_active_bin.zig");
const dlmm_get_bins = @import("dlmm/get_bins.zig");
const dlmm_get_positions = @import("dlmm/get_positions.zig");
const dlmm_swap_quote = @import("dlmm/swap_quote.zig");
const dlmm_swap = @import("dlmm/swap.zig");
const dlmm_add_liquidity = @import("dlmm/add_liquidity.zig");
const dlmm_remove_liquidity = @import("dlmm/remove_liquidity.zig");
const dlmm_claim_fees = @import("dlmm/claim_fees.zig");
const dlmm_claim_rewards = @import("dlmm/claim_rewards.zig");

// =============================================================================
// DAMM v2 Tools - Next-gen Constant Product AMM
// =============================================================================

const damm_v2_get_pool = @import("damm_v2/get_pool.zig");
const damm_v2_get_position = @import("damm_v2/get_position.zig");
const damm_v2_swap_quote = @import("damm_v2/swap_quote.zig");
const damm_v2_swap = @import("damm_v2/swap.zig");
const damm_v2_add_liquidity = @import("damm_v2/add_liquidity.zig");
const damm_v2_remove_liquidity = @import("damm_v2/remove_liquidity.zig");
const damm_v2_claim_fee = @import("damm_v2/claim_fee.zig");
const damm_v2_create_pool = @import("damm_v2/create_pool.zig");

// =============================================================================
// DAMM v1 Tools - Legacy Dynamic AMM
// =============================================================================

const damm_v1_get_pool = @import("damm_v1/get_pool.zig");
const damm_v1_swap_quote = @import("damm_v1/swap_quote.zig");
const damm_v1_swap = @import("damm_v1/swap.zig");
const damm_v1_deposit = @import("damm_v1/deposit.zig");
const damm_v1_withdraw = @import("damm_v1/withdraw.zig");

// =============================================================================
// Dynamic Bonding Curve Tools - Token Launches
// =============================================================================

const dbc_get_pool = @import("bonding_curve/get_pool.zig");
const dbc_get_quote = @import("bonding_curve/get_quote.zig");
const dbc_buy = @import("bonding_curve/buy.zig");
const dbc_sell = @import("bonding_curve/sell.zig");
const dbc_create_pool = @import("bonding_curve/create_pool.zig");
const dbc_check_graduation = @import("bonding_curve/check_graduation.zig");
const dbc_migrate = @import("bonding_curve/migrate.zig");

// =============================================================================
// Vault Tools - Yield Optimization
// =============================================================================

const vault_get_info = @import("vault/get_info.zig");
const vault_deposit = @import("vault/deposit.zig");
const vault_withdraw = @import("vault/withdraw.zig");
const vault_get_user_balance = @import("vault/get_user_balance.zig");

// =============================================================================
// Alpha Vault Tools - Anti-Bot Protection
// =============================================================================

const alpha_vault_get_info = @import("alpha_vault/get_info.zig");
const alpha_vault_deposit = @import("alpha_vault/deposit.zig");
const alpha_vault_withdraw = @import("alpha_vault/withdraw.zig");
const alpha_vault_claim = @import("alpha_vault/claim.zig");

// =============================================================================
// Stake-for-Fee (M3M3) Tools
// =============================================================================

const m3m3_get_pool = @import("stake_for_fee/get_pool.zig");
const m3m3_stake = @import("stake_for_fee/stake.zig");
const m3m3_unstake = @import("stake_for_fee/unstake.zig");
const m3m3_claim_fee = @import("stake_for_fee/claim_fee.zig");
const m3m3_get_user_balance = @import("stake_for_fee/get_user_balance.zig");

/// All Meteora tool definitions
pub const tools = [_]mcp.tools.Tool{
    // =========================================================================
    // DLMM - Concentrated Liquidity
    // =========================================================================
    .{
        .name = "meteora_dlmm_get_pool",
        .description = "Get Meteora DLMM pool info. Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = dlmm_get_pool.handle,
    },
    .{
        .name = "meteora_dlmm_get_active_bin",
        .description = "Get DLMM active bin (current price). Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = dlmm_get_active_bin.handle,
    },
    .{
        .name = "meteora_dlmm_get_bins",
        .description = "Get DLMM bins in range. Parameters: pool_address, min_bin_id (optional), max_bin_id (optional), network (optional), endpoint (optional)",
        .handler = dlmm_get_bins.handle,
    },
    .{
        .name = "meteora_dlmm_get_positions",
        .description = "Get user DLMM positions. Parameters: pool_address, owner, network (optional), endpoint (optional)",
        .handler = dlmm_get_positions.handle,
    },
    .{
        .name = "meteora_dlmm_swap_quote",
        .description = "Get DLMM swap quote. Parameters: pool_address, amount, swap_for_y (true=X->Y), slippage_bps (optional), network (optional), endpoint (optional)",
        .handler = dlmm_swap_quote.handle,
    },
    .{
        .name = "meteora_dlmm_swap",
        .description = "Create DLMM swap transaction. Parameters: pool_address, user, amount, swap_for_y, min_out_amount, network (optional), endpoint (optional)",
        .handler = dlmm_swap.handle,
    },
    .{
        .name = "meteora_dlmm_add_liquidity",
        .description = "Add liquidity to DLMM pool. Parameters: pool_address, user, amount_x, amount_y, strategy (SpotBalanced, etc), min_bin_id, max_bin_id, network (optional), endpoint (optional)",
        .handler = dlmm_add_liquidity.handle,
    },
    .{
        .name = "meteora_dlmm_remove_liquidity",
        .description = "Remove liquidity from DLMM position. Parameters: pool_address, user, position, bps (10000=100%), network (optional), endpoint (optional)",
        .handler = dlmm_remove_liquidity.handle,
    },
    .{
        .name = "meteora_dlmm_claim_fees",
        .description = "Claim DLMM swap fees. Parameters: pool_address, user, position, network (optional), endpoint (optional)",
        .handler = dlmm_claim_fees.handle,
    },
    .{
        .name = "meteora_dlmm_claim_rewards",
        .description = "Claim DLMM LM rewards. Parameters: pool_address, user, position, network (optional), endpoint (optional)",
        .handler = dlmm_claim_rewards.handle,
    },

    // =========================================================================
    // DAMM v2 - Constant Product AMM
    // =========================================================================
    .{
        .name = "meteora_damm_v2_get_pool",
        .description = "Get Meteora DAMM v2 pool info. Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = damm_v2_get_pool.handle,
    },
    .{
        .name = "meteora_damm_v2_get_position",
        .description = "Get user DAMM v2 position. Parameters: pool_address, owner, network (optional), endpoint (optional)",
        .handler = damm_v2_get_position.handle,
    },
    .{
        .name = "meteora_damm_v2_swap_quote",
        .description = "Get DAMM v2 swap quote. Parameters: pool_address, input_mint, amount, slippage_bps (optional), network (optional), endpoint (optional)",
        .handler = damm_v2_swap_quote.handle,
    },
    .{
        .name = "meteora_damm_v2_swap",
        .description = "Create DAMM v2 swap transaction. Parameters: pool_address, user, input_mint, amount, min_out_amount, network (optional), endpoint (optional)",
        .handler = damm_v2_swap.handle,
    },
    .{
        .name = "meteora_damm_v2_add_liquidity",
        .description = "Add liquidity to DAMM v2. Parameters: pool_address, user, amount_a, amount_b, min_lp_amount, network (optional), endpoint (optional)",
        .handler = damm_v2_add_liquidity.handle,
    },
    .{
        .name = "meteora_damm_v2_remove_liquidity",
        .description = "Remove liquidity from DAMM v2. Parameters: pool_address, user, position, lp_amount, min_a, min_b, network (optional), endpoint (optional)",
        .handler = damm_v2_remove_liquidity.handle,
    },
    .{
        .name = "meteora_damm_v2_claim_fee",
        .description = "Claim DAMM v2 position fees. Parameters: pool_address, user, position, network (optional), endpoint (optional)",
        .handler = damm_v2_claim_fee.handle,
    },
    .{
        .name = "meteora_damm_v2_create_pool",
        .description = "Create DAMM v2 pool. Parameters: user, token_a_mint, token_b_mint, token_a_amount, token_b_amount, config (optional), network (optional), endpoint (optional)",
        .handler = damm_v2_create_pool.handle,
    },

    // =========================================================================
    // DAMM v1 - Legacy AMM
    // =========================================================================
    .{
        .name = "meteora_damm_v1_get_pool",
        .description = "Get Meteora DAMM v1 pool info. Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = damm_v1_get_pool.handle,
    },
    .{
        .name = "meteora_damm_v1_swap_quote",
        .description = "Get DAMM v1 swap quote. Parameters: pool_address, input_mint, amount, slippage_bps (optional), network (optional), endpoint (optional)",
        .handler = damm_v1_swap_quote.handle,
    },
    .{
        .name = "meteora_damm_v1_swap",
        .description = "Create DAMM v1 swap transaction. Parameters: pool_address, user, input_mint, amount, min_out_amount, network (optional), endpoint (optional)",
        .handler = damm_v1_swap.handle,
    },
    .{
        .name = "meteora_damm_v1_deposit",
        .description = "Deposit liquidity to DAMM v1. Parameters: pool_address, user, amount_a, amount_b, min_lp_amount, network (optional), endpoint (optional)",
        .handler = damm_v1_deposit.handle,
    },
    .{
        .name = "meteora_damm_v1_withdraw",
        .description = "Withdraw liquidity from DAMM v1. Parameters: pool_address, user, lp_amount, min_a, min_b, network (optional), endpoint (optional)",
        .handler = damm_v1_withdraw.handle,
    },

    // =========================================================================
    // Dynamic Bonding Curve - Token Launches
    // =========================================================================
    .{
        .name = "meteora_dbc_get_pool",
        .description = "Get Dynamic Bonding Curve pool info. Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = dbc_get_pool.handle,
    },
    .{
        .name = "meteora_dbc_get_quote",
        .description = "Get DBC buy/sell quote. Parameters: pool_address, is_buy, amount (quote for buy, base for sell), network (optional), endpoint (optional)",
        .handler = dbc_get_quote.handle,
    },
    .{
        .name = "meteora_dbc_buy",
        .description = "Buy tokens on bonding curve. Parameters: pool_address, user, quote_amount, min_base_amount, network (optional), endpoint (optional)",
        .handler = dbc_buy.handle,
    },
    .{
        .name = "meteora_dbc_sell",
        .description = "Sell tokens on bonding curve. Parameters: pool_address, user, base_amount, min_quote_amount, network (optional), endpoint (optional)",
        .handler = dbc_sell.handle,
    },
    .{
        .name = "meteora_dbc_create_pool",
        .description = "Create DBC pool for token launch. Parameters: user, name, symbol, uri, base_amount, config (optional), network (optional), endpoint (optional)",
        .handler = dbc_create_pool.handle,
    },
    .{
        .name = "meteora_dbc_check_graduation",
        .description = "Check if DBC pool can graduate to AMM. Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = dbc_check_graduation.handle,
    },
    .{
        .name = "meteora_dbc_migrate",
        .description = "Migrate graduated DBC pool to DAMM. Parameters: pool_address, user, target (damm_v1 or damm_v2), network (optional), endpoint (optional)",
        .handler = dbc_migrate.handle,
    },

    // =========================================================================
    // Vault - Yield Optimization
    // =========================================================================
    .{
        .name = "meteora_vault_get_info",
        .description = "Get Meteora Vault info. Parameters: token_mint, network (optional), endpoint (optional)",
        .handler = vault_get_info.handle,
    },
    .{
        .name = "meteora_vault_deposit",
        .description = "Deposit to Meteora Vault. Parameters: token_mint, user, amount, network (optional), endpoint (optional)",
        .handler = vault_deposit.handle,
    },
    .{
        .name = "meteora_vault_withdraw",
        .description = "Withdraw from Meteora Vault. Parameters: token_mint, user, lp_amount, network (optional), endpoint (optional)",
        .handler = vault_withdraw.handle,
    },
    .{
        .name = "meteora_vault_get_user_balance",
        .description = "Get user balance in Meteora Vault. Parameters: token_mint, user, network (optional), endpoint (optional)",
        .handler = vault_get_user_balance.handle,
    },

    // =========================================================================
    // Alpha Vault - Anti-Bot Protection
    // =========================================================================
    .{
        .name = "meteora_alpha_vault_get_info",
        .description = "Get Alpha Vault info. Parameters: vault_address, network (optional), endpoint (optional)",
        .handler = alpha_vault_get_info.handle,
    },
    .{
        .name = "meteora_alpha_vault_deposit",
        .description = "Deposit to Alpha Vault. Parameters: vault_address, user, amount, network (optional), endpoint (optional)",
        .handler = alpha_vault_deposit.handle,
    },
    .{
        .name = "meteora_alpha_vault_withdraw",
        .description = "Withdraw from Alpha Vault. Parameters: vault_address, user, amount, network (optional), endpoint (optional)",
        .handler = alpha_vault_withdraw.handle,
    },
    .{
        .name = "meteora_alpha_vault_claim",
        .description = "Claim tokens from Alpha Vault. Parameters: vault_address, user, network (optional), endpoint (optional)",
        .handler = alpha_vault_claim.handle,
    },

    // =========================================================================
    // Stake-for-Fee (M3M3)
    // =========================================================================
    .{
        .name = "meteora_m3m3_get_pool",
        .description = "Get M3M3 Stake-for-Fee pool info. Parameters: pool_address, network (optional), endpoint (optional)",
        .handler = m3m3_get_pool.handle,
    },
    .{
        .name = "meteora_m3m3_stake",
        .description = "Stake tokens in M3M3. Parameters: pool_address, user, amount, network (optional), endpoint (optional)",
        .handler = m3m3_stake.handle,
    },
    .{
        .name = "meteora_m3m3_unstake",
        .description = "Initiate unstake from M3M3. Parameters: pool_address, user, amount, network (optional), endpoint (optional)",
        .handler = m3m3_unstake.handle,
    },
    .{
        .name = "meteora_m3m3_claim_fee",
        .description = "Claim fees from M3M3 staking. Parameters: pool_address, user, network (optional), endpoint (optional)",
        .handler = m3m3_claim_fee.handle,
    },
    .{
        .name = "meteora_m3m3_get_user_balance",
        .description = "Get user M3M3 staked balance and claimable fees. Parameters: pool_address, user, network (optional), endpoint (optional)",
        .handler = m3m3_get_user_balance.handle,
    },
};

/// Register all Meteora tools with the MCP server
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
