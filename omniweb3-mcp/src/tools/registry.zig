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
const get_chain_id = @import("get_chain_id.zig");
const get_fee_history = @import("get_fee_history.zig");
const get_logs = @import("get_logs.zig");
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

    // block info (Solana/EVM)
    try server.addTool(.{
        .name = "get_block",
        .description = "Get block info. Parameters: chain, block_number (evm) or slot (solana), block_hash (evm), tag (evm), include_transactions, network (optional), endpoint (optional)",
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

    // get chain id (EVM only)
    try server.addTool(.{
        .name = "get_chain_id",
        .description = "Get EVM chain id. Parameters: chain, network (optional), endpoint (optional)",
        .handler = get_chain_id.handle,
    });

    // get fee history (EVM only)
    try server.addTool(.{
        .name = "get_fee_history",
        .description = "Get EVM fee history. Parameters: chain, block_count, newest_block (optional), reward_percentiles (optional), network (optional), endpoint (optional)",
        .handler = get_fee_history.handle,
    });

    // get logs (EVM only)
    try server.addTool(.{
        .name = "get_logs",
        .description = "Get EVM logs. Parameters: chain, address/from_block/to_block/block_hash/topics/tag (optional), network (optional), endpoint (optional)",
        .handler = get_logs.handle,
    });

    // token balance (Solana/EVM)
    try server.addTool(.{
        .name = "token_balance",
        .description = "Token balance. Parameters: chain, token_account (solana) or owner+mint (solana) or token_address+owner (evm), network (optional), endpoint (optional)",
        .handler = token_balance.handle,
    });

    // token balances (Solana only)
    try server.addTool(.{
        .name = "token_balances",
        .description = "Solana token balances by owner. Parameters: chain=solana, owner (optional), mint (optional), network (optional), endpoint (optional)",
        .handler = token_balances.handle,
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

    // parse transaction (Solana only)
    try server.addTool(.{
        .name = "parse_transaction",
        .description = "Parse Solana transaction details. Parameters: chain=solana, signature, network (optional), endpoint (optional)",
        .handler = parse_transaction.handle,
    });

    // request airdrop (Solana only)
    try server.addTool(.{
        .name = "request_airdrop",
        .description = "Request SOL airdrop (devnet/testnet). Parameters: chain=solana, amount (lamports), address (optional), network (optional), endpoint (optional)",
        .handler = request_airdrop.handle,
    });

    // get TPS (Solana only)
    try server.addTool(.{
        .name = "get_tps",
        .description = "Get Solana TPS from recent performance samples. Parameters: chain=solana, limit (optional), network (optional), endpoint (optional)",
        .handler = tps.handle,
    });

    // get slot (Solana only)
    try server.addTool(.{
        .name = "get_slot",
        .description = "Get Solana current slot. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = slot.handle,
    });

    // get block height (Solana only)
    try server.addTool(.{
        .name = "get_block_height",
        .description = "Get Solana current block height. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = block_height.handle,
    });

    // get epoch info (Solana only)
    try server.addTool(.{
        .name = "get_epoch_info",
        .description = "Get Solana epoch info. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = epoch_info.handle,
    });

    // get version (Solana only)
    try server.addTool(.{
        .name = "get_version",
        .description = "Get Solana version info. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = version.handle,
    });

    // get supply (Solana only)
    try server.addTool(.{
        .name = "get_supply",
        .description = "Get Solana supply info. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = supply.handle,
    });

    // get token supply (Solana only)
    try server.addTool(.{
        .name = "get_token_supply",
        .description = "Get SPL token supply. Parameters: chain=solana, mint, network (optional), endpoint (optional)",
        .handler = token_supply.handle,
    });

    // get token largest accounts (Solana only)
    try server.addTool(.{
        .name = "get_token_largest_accounts",
        .description = "Get SPL token largest accounts. Parameters: chain=solana, mint, network (optional), endpoint (optional)",
        .handler = token_largest_accounts.handle,
    });

    // get signatures for address (Solana only)
    try server.addTool(.{
        .name = "get_signatures_for_address",
        .description = "Get signatures for address. Parameters: chain=solana, address, limit/before/until (optional), network (optional), endpoint (optional)",
        .handler = signatures_for_address.handle,
    });

    // get block time (Solana only)
    try server.addTool(.{
        .name = "get_block_time",
        .description = "Get Solana block time. Parameters: chain=solana, slot, network (optional), endpoint (optional)",
        .handler = block_time.handle,
    });

    // get wallet address (Solana only)
    try server.addTool(.{
        .name = "get_wallet_address",
        .description = "Get Solana wallet address from keypair. Parameters: chain=solana, keypair_path (optional)",
        .handler = get_wallet_address.handle,
    });

    // close empty token accounts (Solana only)
    try server.addTool(.{
        .name = "close_empty_token_accounts",
        .description = "Close empty SPL token accounts. Parameters: chain=solana, keypair_path (optional), network (optional), endpoint (optional)",
        .handler = close_empty_token_accounts.handle,
    });

    // get latest blockhash (Solana only)
    try server.addTool(.{
        .name = "get_latest_blockhash",
        .description = "Get latest Solana blockhash. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = get_latest_blockhash.handle,
    });

    // get minimum balance for rent exemption (Solana only)
    try server.addTool(.{
        .name = "get_minimum_balance_for_rent_exemption",
        .description = "Get minimum balance for rent exemption. Parameters: chain=solana, data_len, network (optional), endpoint (optional)",
        .handler = get_minimum_balance_for_rent_exemption.handle,
    });

    // get fee for message (Solana only)
    try server.addTool(.{
        .name = "get_fee_for_message",
        .description = "Get fee for a base64 transaction message. Parameters: chain=solana, message, network (optional), endpoint (optional)",
        .handler = get_fee_for_message.handle,
    });

    // get program accounts (Solana only)
    try server.addTool(.{
        .name = "get_program_accounts",
        .description = "Get program accounts. Parameters: chain=solana, program_id, network (optional), endpoint (optional)",
        .handler = get_program_accounts.handle,
    });

    // get vote accounts (Solana only)
    try server.addTool(.{
        .name = "get_vote_accounts",
        .description = "Get vote accounts. Parameters: chain=solana, network (optional), endpoint (optional)",
        .handler = get_vote_accounts.handle,
    });
}

