//! Privy Tools Registry
//!
//! Registers all Privy authentication and wallet tools.
//!
//! User Management (5 tools):
//! - privy_create_user: Create user with email/phone/wallet
//! - privy_get_user: Get user by ID
//! - privy_get_user_by_email: Lookup by email
//! - privy_get_user_by_wallet: Lookup by wallet address
//! - privy_list_users: List all users with pagination
//!
//! Wallet Management (7 tools):
//! - privy_create_wallet: Create embedded wallet
//! - privy_get_wallet: Get wallet info
//! - privy_list_wallets: List wallets with filtering
//! - privy_get_wallet_balance: Get native token balance
//! - privy_sign_message: Sign messages
//! - privy_sign_transaction: Sign without sending
//! - privy_sign_and_send_transaction: Sign and broadcast

const mcp = @import("mcp");

// User management tools
const user_create = @import("users/create.zig");
const user_get = @import("users/get.zig");
const user_get_by_email = @import("users/get_by_email.zig");
const user_get_by_wallet = @import("users/get_by_wallet.zig");
const user_list = @import("users/list.zig");

// Wallet management tools
const wallet_create = @import("wallets/create.zig");
const wallet_get = @import("wallets/get.zig");
const wallet_list = @import("wallets/list.zig");
const wallet_get_balance = @import("wallets/get_balance.zig");
const wallet_sign_message = @import("wallets/sign_message.zig");
const wallet_sign_transaction = @import("wallets/sign_transaction.zig");
const wallet_sign_and_send = @import("wallets/sign_and_send.zig");

/// All Privy tool definitions
pub const tools = [_]mcp.tools.Tool{
    // =========================================================================
    // User Management Tools
    // =========================================================================
    .{
        .name = "privy_create_user",
        .description = "Create a new Privy user. Parameters: email (optional), phone (optional, E.164 format), wallet_address (optional), create_solana_wallet (optional, default: false), create_ethereum_wallet (optional, default: false). Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = user_create.handle,
    },
    .{
        .name = "privy_get_user",
        .description = "Get Privy user info by ID. Parameters: user_id (format: did:privy:xxx). Returns linked accounts, wallets, and metadata. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = user_get.handle,
    },
    .{
        .name = "privy_get_user_by_email",
        .description = "Look up a Privy user by email. Parameters: email. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = user_get_by_email.handle,
    },
    .{
        .name = "privy_get_user_by_wallet",
        .description = "Look up a Privy user by wallet address. Parameters: wallet_address. Works with embedded or linked external wallets. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = user_get_by_wallet.handle,
    },
    .{
        .name = "privy_list_users",
        .description = "List all users in your Privy app. Parameters: cursor (optional), limit (optional, default: 100, max: 100). Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = user_list.handle,
    },

    // =========================================================================
    // Wallet Management Tools
    // =========================================================================
    .{
        .name = "privy_create_wallet",
        .description = "Create a Privy embedded wallet. Parameters: chain_type (ethereum, solana, sui, aptos, cosmos, stellar, tron, near, ton, starknet, spark, bitcoin-segwit), user_id (optional, format: did:privy:xxx). Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_create.handle,
    },
    .{
        .name = "privy_get_wallet",
        .description = "Get Privy wallet info by ID. Parameters: wallet_id. Returns address, chain type, and policies. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_get.handle,
    },
    .{
        .name = "privy_list_wallets",
        .description = "List all wallets in your Privy app. Parameters: chain_type (optional, filter by chain), cursor (optional), limit (optional, default: 100). Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_list.handle,
    },
    .{
        .name = "privy_get_wallet_balance",
        .description = "Get native token balance of a Privy wallet. Parameters: wallet_id. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_get_balance.handle,
    },
    .{
        .name = "privy_sign_message",
        .description = "Sign a message using a Privy wallet. Parameters: wallet_id, message, chain_type (solana or ethereum), network (optional: mainnet, devnet, testnet; default: devnet). Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_sign_message.handle,
    },
    .{
        .name = "privy_sign_transaction",
        .description = "Sign a transaction without sending. Parameters: wallet_id, transaction (base64 encoded), chain_type (solana or ethereum), network (optional: mainnet, devnet, testnet; default: devnet). Returns signed transaction. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_sign_transaction.handle,
    },
    .{
        .name = "privy_sign_and_send_transaction",
        .description = "Sign and send a transaction. Parameters: wallet_id, transaction (base64 encoded), chain_type (solana or ethereum), network (optional: mainnet, devnet, testnet; default: devnet), sponsor (optional: enable gas sponsorship, default: false). Returns transaction hash. Requires PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        .handler = wallet_sign_and_send.handle,
    },
};

/// Register all Privy tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
