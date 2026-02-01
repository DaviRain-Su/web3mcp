// Split from main.rs: request/response schemas for MCP tools

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct TransactionResponseOptionsRequest {
    #[schemars(description = "Include transaction input")]
    pub show_input: Option<bool>,
    #[schemars(description = "Include raw input bytes")]
    pub show_raw_input: Option<bool>,
    #[schemars(description = "Include effects")]
    pub show_effects: Option<bool>,
    #[schemars(description = "Include events")]
    pub show_events: Option<bool>,
    #[schemars(description = "Include object changes")]
    pub show_object_changes: Option<bool>,
    #[schemars(description = "Include balance changes")]
    pub show_balance_changes: Option<bool>,
    #[schemars(description = "Include raw effects")]
    pub show_raw_effects: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetBalanceRequest {
    #[schemars(description = "The Sui address to query (hex format starting with 0x)")]
    pub address: String,
    #[schemars(description = "Optional coin type (defaults to 0x2::sui::SUI)")]
    pub coin_type: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetAllBalancesRequest {
    #[schemars(description = "The Sui address to query (hex format starting with 0x)")]
    pub address: String,
}

// ---- EVM / Base (experimental multi-chain) ----

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmGetBalanceRequest {
    #[schemars(description = "EVM address (0x...) to query")]
    pub address: String,
    #[schemars(
        description = "Optional chain id (default: EVM_DEFAULT_CHAIN_ID or Base Sepolia 84532)"
    )]
    pub chain_id: Option<u64>,
    #[schemars(
        description = "Optional ERC20 token contract address. If omitted, returns native ETH balance."
    )]
    pub token_address: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmGetGasPriceRequest {
    #[schemars(
        description = "Optional chain id (default: EVM_DEFAULT_CHAIN_ID or Base Sepolia 84532)"
    )]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmEventTopic0Request {
    #[schemars(description = "Event signature string (e.g. Transfer(address,address,uint256))")]
    pub signature: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmListPendingConfirmationsRequest {
    #[schemars(description = "Optional EVM chain id filter")]
    pub chain_id: Option<u64>,
    #[schemars(description = "Optional status filter (pending|consumed|sent|failed)")]
    pub status: Option<String>,
    #[schemars(description = "Include tx_summary in each item (default true)")]
    pub include_tx_summary: Option<bool>,
    #[schemars(description = "Optional max results (default 20)")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmCleanupPendingConfirmationsRequest {
    #[schemars(description = "Optional chain id filter")]
    pub chain_id: Option<u64>,
    #[schemars(description = "If provided, delete failed entries older than this age (ms)")]
    pub delete_failed_older_than_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmGetPendingConfirmationRequest {
    #[schemars(description = "Confirmation id (e.g. evm_dryrun_...)")]
    pub id: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmRetryPendingConfirmationRequest {
    #[schemars(description = "Confirmation id (e.g. evm_dryrun_...)")]
    pub id: String,
    #[schemars(description = "tx_summary_hash from the pending record (0x...)")]
    pub tx_summary_hash: String,
    #[schemars(description = "Optional second-confirm token for large-value tx (token:...)")]
    pub confirm_token: Option<String>,
    #[schemars(description = "Optional chain id sanity check")]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmParseAmountRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Human amount (e.g. '1.5', '0.1')")]
    pub amount: String,
    #[schemars(description = "Unit symbol (e.g. 'eth', 'usdc', 'usdt')")]
    pub symbol: Option<String>,
    #[schemars(description = "Token address (0x...) - overrides symbol")]
    pub token_address: Option<String>,
    #[schemars(description = "Optional decimals override")]
    pub decimals: Option<u8>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmParseDeadlineRequest {
    #[schemars(description = "Duration string (e.g. '20m', '5min', '2h', '30s') or unix seconds")]
    pub input: String,
    #[schemars(
        description = "If true, interpret input as relative duration (default true when suffix present)"
    )]
    pub relative: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmParsePathRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Path input: 'WETH->USDC', '0xA,0xB', or JSON array string")]
    pub input: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmApplySlippageRequest {
    #[schemars(description = "Expected amount out in wei (decimal string)")]
    pub expected_amount_out_wei: String,
    #[schemars(description = "Slippage input (e.g. '1%', '50bps', '0.5%')")]
    pub slippage: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct Evm0xQuoteRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Taker address (defaults to sender in higher-level flows)")]
    pub taker_address: Option<String>,
    #[schemars(description = "Sell token symbol (e.g. 'eth','usdc','weth') or 0x address")]
    pub sell_token: String,
    #[schemars(description = "Buy token symbol or 0x address")]
    pub buy_token: String,
    #[schemars(
        description = "Sell amount (e.g. '0.1', '1.5 usdc', or wei decimal string if sell_amount_is_wei=true)"
    )]
    pub sell_amount: String,
    #[schemars(description = "If true, sell_amount is already in wei/base units (decimal string)")]
    pub sell_amount_is_wei: Option<bool>,
    #[schemars(description = "Slippage (e.g. '1%'). Default 1%")]
    pub slippage: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct Evm0xBuildSwapTxRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Sender/taker address")]
    pub sender: String,
    #[schemars(description = "Sell token symbol or 0x address")]
    pub sell_token: String,
    #[schemars(description = "Buy token symbol or 0x address")]
    pub buy_token: String,
    #[schemars(description = "Sell amount (human string or wei if sell_amount_is_wei=true)")]
    pub sell_amount: String,
    #[schemars(description = "If true, sell_amount is already in wei/base units")]
    pub sell_amount_is_wei: Option<bool>,
    #[schemars(description = "Slippage (e.g. '1%'). Default 1%")]
    pub slippage: Option<String>,
    #[schemars(
        description = "If true, suggested approve tx will be exact amount instead of infinite"
    )]
    pub exact_approve: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmGetTransactionRequest {
    #[schemars(description = "Transaction hash (0x...)")]
    pub tx_hash: String,
    #[schemars(
        description = "Optional chain id (default: EVM_DEFAULT_CHAIN_ID or Base Sepolia 84532)"
    )]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmGetTransactionReceiptRequest {
    #[schemars(description = "Transaction hash (0x...)")]
    pub tx_hash: String,
    #[schemars(
        description = "Optional chain id (default: EVM_DEFAULT_CHAIN_ID or Base Sepolia 84532)"
    )]
    pub chain_id: Option<u64>,

    #[schemars(description = "Include full receipt object in response (default: false)")]
    pub include_receipt: Option<bool>,

    #[schemars(description = "Max decoded logs to return (default: 50)")]
    pub decoded_logs_limit: Option<usize>,

    #[schemars(
        description = "Only decode logs emitted by these contract addresses (0x...). If omitted, decode all."
    )]
    pub only_addresses: Option<Vec<String>>,

    #[schemars(
        description = "Only decode logs whose topic0 matches one of these values (0x...). If omitted, decode all."
    )]
    pub only_topics0: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmDecodeTransactionReceiptRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(
        description = "Transaction receipt JSON (as returned by evm_get_transaction_receipt)"
    )]
    pub receipt_json: Value,

    #[schemars(description = "Max decoded logs to return (default: 50)")]
    pub decoded_logs_limit: Option<usize>,

    #[schemars(
        description = "Only decode logs emitted by these contract addresses (0x...). If omitted, decode all."
    )]
    pub only_addresses: Option<Vec<String>>,

    #[schemars(
        description = "Only decode logs whose topic0 matches one of these values (0x...). If omitted, decode all."
    )]
    pub only_topics0: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmBuildTransferNativeRequest {
    #[schemars(description = "Sender address (0x...)")]
    pub sender: String,
    #[schemars(description = "Recipient address (0x...)")]
    pub recipient: String,
    #[schemars(description = "Amount in wei (decimal string or 0x hex)")]
    pub amount_wei: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
    #[schemars(description = "Optional hex calldata (0x...) for advanced use")]
    pub data_hex: Option<String>,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
    #[schemars(description = "Require explicit confirmation for large transfers")]
    pub confirm_large_transfer: Option<bool>,
    #[schemars(description = "Large transfer threshold in wei (default 0.1 ETH)")]
    pub large_transfer_threshold_wei: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlRegisterRequest {
    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(
        description = "IDL name/version key (directory name). If omitted, will attempt to infer from IDL metadata.name, else 'default'."
    )]
    pub name: Option<String>,
    #[schemars(description = "IDL JSON content")]
    pub idl_json: String,
    #[schemars(description = "Overwrite if existing")]
    pub overwrite: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlRegisterFileRequest {
    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(
        description = "IDL name/version key (directory name). If omitted, will attempt to infer from file content metadata.name, else file stem."
    )]
    pub name: Option<String>,
    #[schemars(description = "Local file path to an IDL JSON")]
    pub path: String,
    #[schemars(description = "Overwrite if existing")]
    pub overwrite: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlListRequest {
    #[schemars(description = "Optional program id to filter")]
    pub program_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlGetRequest {
    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(description = "IDL name/version key")]
    pub name: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlPlanInstructionRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(description = "IDL name/version key")]
    pub name: String,
    #[schemars(description = "Instruction name")]
    pub instruction: String,
    #[schemars(description = "Optional args object (name->value)")]
    pub args: Option<serde_json::Value>,
    #[schemars(description = "Optional accounts object (name->pubkey) for missing detection")]
    pub accounts: Option<serde_json::Value>,
    #[schemars(description = "Optional: validate on-chain using RPC (default false)")]
    pub validate_on_chain: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlBuildInstructionRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(description = "IDL name/version key")]
    pub name: String,
    #[schemars(description = "Instruction name")]
    pub instruction: String,
    #[schemars(description = "Args object (name->value)")]
    pub args: serde_json::Value,
    #[schemars(description = "Accounts object (name->pubkey)")]
    pub accounts: serde_json::Value,
    #[schemars(description = "Optional: validate on-chain using RPC (default false)")]
    pub validate_on_chain: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlExecuteRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(description = "IDL name/version key")]
    pub name: String,
    #[schemars(description = "Instruction name")]
    pub instruction: String,
    #[schemars(description = "Args object (name->value)")]
    pub args: serde_json::Value,
    #[schemars(description = "Accounts object (name->pubkey)")]
    pub accounts: serde_json::Value,
    #[schemars(description = "Optional: validate on-chain using RPC (default false)")]
    pub validate_on_chain: Option<bool>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlSimulateInstructionRequest {
    #[schemars(
        description = "Simulation config (preferred). If present, overrides top-level network/sig_verify/replace_recent_blockhash/commitment/strict_sig_verify."
    )]
    pub simulate_config: Option<SolanaSimulateConfig>,

    // Back-compat fields
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Solana program id (base58)")]
    pub program_id: String,
    #[schemars(description = "IDL name/version key")]
    pub name: String,
    #[schemars(description = "Instruction name")]
    pub instruction: String,
    #[schemars(description = "Args object (name->value)")]
    pub args: serde_json::Value,
    #[schemars(description = "Accounts object (name->pubkey)")]
    pub accounts: serde_json::Value,

    #[schemars(description = "Fee payer pubkey (base58)")]
    pub fee_payer: String,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "If true, replace recent blockhash with latest before simulation (default true)"
    )]
    pub replace_recent_blockhash: Option<bool>,
    #[schemars(description = "If true, RPC verifies signatures during simulation (default false)")]
    pub sig_verify: Option<bool>,
    #[schemars(description = "Commitment used for simulation context (default confirmed)")]
    pub commitment: Option<String>,

    #[schemars(description = "Optional: validate on-chain using RPC (default false)")]
    pub validate_on_chain: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlSearchRequest {
    #[schemars(description = "Substring query over program_id/name")]
    pub query: String,
    #[schemars(description = "Max results (default 50)")]
    pub limit: Option<u32>,
}

// ---------------- Solana common RPC tools ----------------

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetBalanceRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Account address (base58)")]
    pub address: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetAccountInfoRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Account address (base58)")]
    pub address: String,
    #[schemars(description = "Encoding: base64|base64+zstd|jsonParsed (default base64)")]
    pub encoding: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetLatestBlockhashRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Optional commitment: processed|confirmed|finalized")]
    pub commitment: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetSignatureStatusRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Transaction signature (base58)")]
    pub signature: String,
    #[schemars(description = "Search history (default false)")]
    pub search_transaction_history: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetTransactionRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Transaction signature (base58)")]
    pub signature: String,
    #[schemars(description = "Encoding: json|jsonParsed|base64 (default json)")]
    pub encoding: Option<String>,
    #[schemars(description = "Max supported transaction version (default 0)")]
    pub max_supported_transaction_version: Option<u8>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetSlotRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Optional commitment: processed|confirmed|finalized")]
    pub commitment: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetBlockHeightRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Optional commitment: processed|confirmed|finalized")]
    pub commitment: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaRequestAirdropRequest {
    #[schemars(description = "Network: devnet|testnet (mainnet not supported)")]
    pub network: Option<String>,
    #[schemars(description = "Recipient address (base58)")]
    pub address: String,
    #[schemars(description = "Lamports amount (e.g., 1000000000 for 1 SOL)")]
    pub lamports: u64,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetTokenAccountsRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Owner address (base58)")]
    pub owner: String,
    #[schemars(description = "Optional mint address (base58) to filter")]
    pub mint: Option<String>,
    #[schemars(description = "Encoding: base64|jsonParsed (default jsonParsed)")]
    pub encoding: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaGetTokenBalanceRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Owner address (base58)")]
    pub owner: String,
    #[schemars(description = "Mint address (base58)")]
    pub mint: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSplTransferRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Mint address (base58) for SPL token (e.g. USDC mint)")]
    pub mint: String,
    #[schemars(description = "Token owner (sender) pubkey (base58)")]
    pub owner: String,
    #[schemars(description = "Recipient owner pubkey (base58)")]
    pub recipient: String,

    #[schemars(description = "Raw token amount (integer string, in base units)")]
    pub amount_raw: String,

    #[schemars(
        description = "If true (default), use transfer_checked by fetching mint decimals from chain. Set false to use plain transfer."
    )]
    pub use_transfer_checked: Option<bool>,

    #[schemars(
        description = "Optional: override source token account. If omitted, uses owner's ATA for mint"
    )]
    pub source_token_account: Option<String>,
    #[schemars(
        description = "Optional: override destination token account. If omitted, uses recipient's ATA for mint"
    )]
    pub destination_token_account: Option<String>,

    #[schemars(
        description = "If true, create destination ATA if missing (default false). Requires fee_payer/signing to actually broadcast."
    )]
    pub create_ata_if_missing: Option<bool>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSplTransferUiAmountRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Mint address (base58) for SPL token (e.g. USDC mint)")]
    pub mint: String,
    #[schemars(description = "Token owner (sender) pubkey (base58)")]
    pub owner: String,
    #[schemars(description = "Recipient owner pubkey (base58)")]
    pub recipient: String,

    #[schemars(description = "Token amount in UI units (decimal string, e.g. '1.23')")]
    pub amount: String,

    #[schemars(
        description = "Optional: override source token account. If omitted, uses owner's ATA for mint"
    )]
    pub source_token_account: Option<String>,
    #[schemars(
        description = "Optional: override destination token account. If omitted, uses recipient's ATA for mint"
    )]
    pub destination_token_account: Option<String>,

    #[schemars(
        description = "If true, create destination ATA if missing (default false)."
    )]
    pub create_ata_if_missing: Option<bool>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSplApproveRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Mint address (base58) for SPL token")]
    pub mint: String,
    #[schemars(description = "Token owner pubkey (base58)")]
    pub owner: String,
    #[schemars(description = "Delegate pubkey (base58)")]
    pub delegate: String,

    #[schemars(description = "Raw token amount (integer string, in base units)")]
    pub amount_raw: String,

    #[schemars(
        description = "If true (default), validate mint+token_account by decoding accounts on chain (recommended)."
    )]
    pub validate_mint_decimals: Option<bool>,

    #[schemars(
        description = "Optional: override owner token account. If omitted, uses owner's ATA for mint"
    )]
    pub token_account: Option<String>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSplRevokeRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Mint address (base58) for SPL token")]
    pub mint: String,
    #[schemars(description = "Token owner pubkey (base58)")]
    pub owner: String,

    #[schemars(
        description = "Optional: override owner token account. If omitted, uses owner's ATA for mint"
    )]
    pub token_account: Option<String>,

    #[schemars(
        description = "If true (default), validate token_account by decoding it and checking (mint, owner)."
    )]
    pub validate_token_account: Option<bool>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSplCloseAccountRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Mint address (base58) for SPL token")]
    pub mint: String,
    #[schemars(description = "Token owner pubkey (base58)")]
    pub owner: String,

    #[schemars(
        description = "Optional: override owner token account. If omitted, uses owner's ATA for mint"
    )]
    pub token_account: Option<String>,

    #[schemars(
        description = "Where to send reclaimed lamports (base58). Default = owner"
    )]
    pub destination: Option<String>,

    #[schemars(
        description = "If true (default), validate token_account by decoding it and checking (mint, owner)."
    )]
    pub validate_token_account: Option<bool>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSplCreateAtaRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Wallet owner pubkey (base58) for the ATA")]
    pub owner: String,
    #[schemars(description = "Mint address (base58) for SPL token")]
    pub mint: String,

    #[schemars(
        description = "If true (default), only create if missing (idempotent behavior implemented by checking existence)."
    )]
    pub create_if_missing: Option<bool>,

    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,

    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

// ---------------- Solana tx build ----------------

#[derive(Debug, Clone, Deserialize, schemars::JsonSchema)]
pub struct SolanaAccountMetaInput {
    #[schemars(description = "Account pubkey (base58)")]
    pub pubkey: String,
    #[schemars(description = "Is signer")]
    pub is_signer: bool,
    #[schemars(description = "Is writable")]
    pub is_writable: bool,
    #[schemars(description = "Optional name (for debugging)")]
    pub name: Option<String>,
}

#[derive(Debug, Clone, Deserialize, schemars::JsonSchema)]
pub struct SolanaInstructionInput {
    #[schemars(description = "Program id (base58)")]
    pub program_id: String,
    #[schemars(description = "Account metas")]
    pub accounts: Vec<SolanaAccountMetaInput>,
    #[schemars(description = "Instruction data (base64)")]
    pub data_base64: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaTxBuildRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(
        description = "Fee payer pubkey (base58). If omitted and sign=true, uses SOLANA_KEYPAIR_PATH pubkey"
    )]
    pub fee_payer: Option<String>,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,

    #[schemars(
        description = "Optional compute unit limit to prepend via ComputeBudget program (setComputeUnitLimit)"
    )]
    pub compute_unit_limit: Option<u32>,
    #[schemars(
        description = "Optional compute unit price (micro-lamports) to prepend via ComputeBudget program (setComputeUnitPrice)"
    )]
    pub compute_unit_price_micro_lamports: Option<u64>,

    #[schemars(description = "One or more instructions")]
    pub instructions: Vec<SolanaInstructionInput>,
    #[schemars(description = "Whether to sign with SOLANA_KEYPAIR_PATH (default false)")]
    pub sign: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSendTransactionRequest {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "Transaction bytes (base64). Can be signed or unsigned")]
    pub transaction_base64: String,
    #[schemars(
        description = "If true, broadcast immediately; if false (default), create a pending confirmation"
    )]
    pub confirm: Option<bool>,
    #[schemars(
        description = "Commitment to wait for when confirm=true: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaConfirmTransactionRequest {
    #[schemars(description = "Confirmation id returned by solana_send_transaction")]
    pub id: String,
    #[schemars(description = "tx_summary_hash returned by solana_send_transaction")]
    pub hash: String,
    #[schemars(
        description = "Network override: mainnet|devnet|testnet (optional; default from stored request context if available; otherwise mainnet)"
    )]
    pub network: Option<String>,
    #[schemars(
        description = "Commitment to wait for: processed|confirmed|finalized (default confirmed)"
    )]
    pub commitment: Option<String>,
    #[schemars(description = "Skip preflight (default false)")]
    pub skip_preflight: Option<bool>,
    #[schemars(description = "Optional timeout in ms for confirmation wait (default 60000)")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Clone, Deserialize, schemars::JsonSchema)]
pub struct SolanaSimulateConfig {
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(description = "If true, RPC verifies signatures during simulation (default false)")]
    pub sig_verify: Option<bool>,
    #[schemars(
        description = "If true, replace recent blockhash with latest before simulation (default true)"
    )]
    pub replace_recent_blockhash: Option<bool>,
    #[schemars(description = "Commitment used for simulation context (default confirmed)")]
    pub commitment: Option<String>,
    #[schemars(
        description = "If true and sig_verify=true, require a local keypair to produce/verify signatures when tx is missing signatures (default false)."
    )]
    pub strict_sig_verify: Option<bool>,

    #[schemars(
        description = "Optional: request simulated account results for these addresses (base58 pubkeys). This uses RPC simulateTransaction config.accounts."
    )]
    pub simulate_accounts: Option<Vec<String>>,
    #[schemars(
        description = "Encoding for simulate_accounts results: base64|base64+zstd|jsonParsed (default base64)."
    )]
    pub accounts_encoding: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSimulateTransactionRequest {
    #[schemars(
        description = "Simulation config (preferred). If present, overrides top-level network/sig_verify/replace_recent_blockhash/commitment/strict_sig_verify."
    )]
    pub simulate_config: Option<SolanaSimulateConfig>,

    // Back-compat fields
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,
    #[schemars(
        description = "Transaction bytes (base64). Signed recommended but not required if sig_verify=false"
    )]
    pub transaction_base64: String,
    #[schemars(description = "If true, RPC verifies signatures during simulation (default false)")]
    pub sig_verify: Option<bool>,
    #[schemars(
        description = "If true, replace recent blockhash with latest before simulation (default true)"
    )]
    pub replace_recent_blockhash: Option<bool>,
    #[schemars(description = "Commitment used for simulation context (default confirmed)")]
    pub commitment: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaSimulateInstructionRequest {
    #[schemars(
        description = "Simulation config (preferred). If present, overrides top-level network/sig_verify/replace_recent_blockhash/commitment/strict_sig_verify."
    )]
    pub simulate_config: Option<SolanaSimulateConfig>,

    // Back-compat fields
    #[schemars(description = "Network: mainnet|devnet|testnet (optional; default mainnet)")]
    pub network: Option<String>,

    #[schemars(description = "Fee payer pubkey (base58)")]
    pub fee_payer: String,
    #[schemars(description = "Recent blockhash (base58). If omitted, fetched from RPC")]
    pub recent_blockhash: Option<String>,
    #[schemars(description = "Instruction to simulate")]
    pub instruction: SolanaInstructionInput,

    #[schemars(
        description = "If true, replace recent blockhash with latest before simulation (default true)"
    )]
    pub replace_recent_blockhash: Option<bool>,
    #[schemars(description = "If true, RPC verifies signatures during simulation (default false)")]
    pub sig_verify: Option<bool>,
    #[schemars(description = "Commitment used for simulation context (default confirmed)")]
    pub commitment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct EvmTxRequest {
    #[schemars(description = "Chain id")]
    pub chain_id: u64,
    #[schemars(description = "Sender address")]
    pub from: String,
    #[schemars(description = "Recipient address")]
    pub to: String,
    #[schemars(description = "Value in wei (decimal string)")]
    pub value_wei: String,
    #[schemars(description = "Optional calldata (0x...) ")]
    pub data_hex: Option<String>,
    #[schemars(description = "Transaction nonce")]
    pub nonce: Option<u64>,
    #[schemars(description = "Gas limit")]
    pub gas_limit: Option<u64>,
    #[schemars(description = "EIP-1559 maxFeePerGas in wei (decimal string)")]
    pub max_fee_per_gas_wei: Option<String>,
    #[schemars(description = "EIP-1559 maxPriorityFeePerGas in wei (decimal string)")]
    pub max_priority_fee_per_gas_wei: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmPreflightRequest {
    #[schemars(description = "Transaction request to preflight (fills missing nonce/gas/fees)")]
    pub tx: EvmTxRequest,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmSignLocalRequest {
    #[schemars(description = "Transaction request (must include nonce, gas_limit, and fees)")]
    pub tx: EvmTxRequest,
    #[schemars(description = "Allow signer address to differ from tx.from")]
    pub allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmSendRawTransactionRequest {
    #[schemars(description = "Raw signed tx hex (0x...)")]
    pub raw_tx: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmSpeedUpTxRequest {
    #[schemars(description = "Chain id")]
    pub chain_id: u64,

    #[schemars(description = "Pending transaction hash to speed up (preferred)")]
    pub tx_hash: Option<String>,

    #[schemars(description = "Alternative: tx.from (0x...) when tx_hash is unavailable")]
    pub from: Option<String>,
    #[schemars(description = "Alternative: tx nonce (u64) when tx_hash is unavailable")]
    pub nonce: Option<u64>,
    #[schemars(description = "Alternative: tx.to (0x...) when tx_hash is unavailable")]
    pub to: Option<String>,
    #[schemars(description = "Alternative: tx.value_wei (decimal) when tx_hash is unavailable")]
    pub value_wei: Option<String>,
    #[schemars(description = "Alternative: tx.data_hex (0x...) when tx_hash is unavailable")]
    pub data_hex: Option<String>,

    #[schemars(
        description = "If true, avoid changing anything except fees (may skip preflight if gas_limit already known)"
    )]
    pub strict: Option<bool>,

    #[schemars(description = "Fee bump multiplier in basis points (default 12000 = +20%)")]
    pub fee_bump_bps: Option<u64>,
    #[schemars(description = "Override maxFeePerGas (wei) (decimal or 0x)")]
    pub max_fee_per_gas_wei: Option<String>,
    #[schemars(description = "Override maxPriorityFeePerGas (wei) (decimal or 0x)")]
    pub max_priority_fee_per_gas_wei: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmCancelTxRequest {
    #[schemars(description = "Chain id")]
    pub chain_id: u64,

    #[schemars(description = "Pending transaction hash to cancel (preferred)")]
    pub tx_hash: Option<String>,

    #[schemars(description = "Alternative: tx.from (0x...) when tx_hash is unavailable")]
    pub from: Option<String>,
    #[schemars(description = "Alternative: tx nonce (u64) when tx_hash is unavailable")]
    pub nonce: Option<u64>,

    #[schemars(
        description = "If true, avoid changing anything except fees (may skip preflight if gas_limit already known)"
    )]
    pub strict: Option<bool>,

    #[schemars(description = "Fee bump multiplier in basis points (default 13000 = +30%)")]
    pub fee_bump_bps: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmExecuteTransferNativeRequest {
    #[schemars(description = "Sender address (0x...)")]
    pub sender: String,
    #[schemars(description = "Recipient address (0x...)")]
    pub recipient: String,
    #[schemars(description = "Amount in ETH units (18 decimals), e.g. '0.001'")]
    pub amount: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
    #[schemars(description = "Require explicit confirmation for large transfers")]
    pub confirm_large_transfer: Option<bool>,
    #[schemars(description = "Large transfer threshold in wei (default 0.1 ETH)")]
    pub large_transfer_threshold_wei: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmErc20BalanceOfRequest {
    #[schemars(description = "ERC20 token contract address")]
    pub token: String,
    #[schemars(description = "Owner address")]
    pub owner: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmErc20AllowanceRequest {
    #[schemars(description = "ERC20 token contract address")]
    pub token: String,
    #[schemars(description = "Owner address")]
    pub owner: String,
    #[schemars(description = "Spender address")]
    pub spender: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmExecuteErc20TransferRequest {
    #[schemars(
        description = "Sender address (must match EVM_PRIVATE_KEY unless allow_sender_mismatch is true)"
    )]
    pub sender: String,
    #[schemars(description = "ERC20 token contract address")]
    pub token: String,
    #[schemars(description = "Recipient address")]
    pub recipient: String,
    #[schemars(description = "Token amount in base units (raw integer, e.g. USDC has 6 decimals)")]
    pub amount_raw: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    pub allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmExecuteErc20ApproveRequest {
    #[schemars(
        description = "Owner/sender address (must match EVM_PRIVATE_KEY unless allow_sender_mismatch is true)"
    )]
    pub sender: String,
    #[schemars(description = "ERC20 token contract address")]
    pub token: String,
    #[schemars(description = "Spender address")]
    pub spender: String,
    #[schemars(description = "Token amount in base units (raw integer)")]
    pub amount_raw: String,
    #[schemars(description = "Optional chain id")]
    pub chain_id: Option<u64>,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    pub allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmBuildErc20ApproveTxRequest {
    #[schemars(description = "Owner/sender address")]
    pub sender: String,
    #[schemars(description = "ERC20 token contract address")]
    pub token: String,
    #[schemars(description = "Spender address")]
    pub spender: String,
    #[schemars(
        description = "Token amount in base units (raw integer). Use max uint256 to give infinite approval."
    )]
    pub amount_raw: String,
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmRegisterContractRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Contract address")]
    pub address: String,
    #[schemars(description = "Optional human-friendly name")]
    pub name: Option<String>,
    #[schemars(description = "Contract ABI JSON (string)")]
    pub abi_json: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmRegisterContractFromPathRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Contract address")]
    pub address: String,
    #[schemars(description = "Optional human-friendly name")]
    pub name: Option<String>,
    #[schemars(
        description = "Path to ABI JSON file (either an ABI array, or a full registry entry with {abi: [...]})"
    )]
    pub abi_path: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmListContractsRequest {
    #[schemars(description = "Optional chain id filter")]
    pub chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmFindContractsRequest {
    #[schemars(description = "Optional chain id filter")]
    pub chain_id: Option<u64>,
    #[schemars(description = "Search query (matched against name/address/path)")]
    pub query: String,
    #[schemars(description = "Optional max results (default 10)")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmPlanContractCallRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,

    #[schemars(
        description = "Contract address (optional if contract_name/contract_query is provided)"
    )]
    pub address: Option<String>,
    #[schemars(description = "Contract name/alias in ABI registry (optional)")]
    pub contract_name: Option<String>,
    #[schemars(description = "Contract fuzzy query (e.g. 'usdc', 'cetus', partial address)")]
    pub contract_query: Option<String>,

    #[schemars(
        description = "If true, pick the top contract match automatically when query is ambiguous"
    )]
    pub accept_best_match: Option<bool>,

    #[schemars(description = "Natural language instruction")]
    pub text: String,

    #[schemars(description = "Optional function hint (e.g. 'approve', 'swap', 'deposit')")]
    pub function_hint: Option<String>,

    #[schemars(description = "Optional max function candidates (default 5)")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmGetContractRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Contract address")]
    pub address: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmCallViewRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(
        description = "Contract address (optional if contract_name/contract_query is provided)"
    )]
    pub address: Option<String>,
    #[schemars(description = "Contract name/alias in ABI registry (optional)")]
    pub contract_name: Option<String>,
    #[schemars(
        description = "Contract fuzzy query (e.g. 'usdc', 'cetus', partial address). Used if address/contract_name not provided."
    )]
    pub contract_query: Option<String>,
    #[schemars(
        description = "If true, pick the top fuzzy match automatically when contract_query returns multiple results"
    )]
    pub accept_best_match: Option<bool>,
    #[schemars(description = "Function name (e.g. 'balanceOf')")]
    pub function: String,
    #[schemars(description = "Optional exact function signature (e.g. 'balanceOf(address)')")]
    pub function_signature: Option<String>,
    #[schemars(
        description = "Arguments as JSON array (supports basic types: address, uint/int, bool, string, bytes)"
    )]
    pub args: Option<Value>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmExecuteContractCallRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(
        description = "Contract address (optional if contract_name/contract_query is provided)"
    )]
    pub address: Option<String>,
    #[schemars(description = "Contract name/alias in ABI registry (optional)")]
    pub contract_name: Option<String>,
    #[schemars(
        description = "Contract fuzzy query (e.g. 'usdc', 'cetus', partial address). Used if address/contract_name not provided."
    )]
    pub contract_query: Option<String>,
    #[schemars(
        description = "If true, pick the top fuzzy match automatically when contract_query returns multiple results"
    )]
    pub accept_best_match: Option<bool>,
    #[schemars(description = "Function name")]
    pub function: String,
    #[schemars(
        description = "Optional exact function signature (e.g. 'transfer(address,uint256)')"
    )]
    pub function_signature: Option<String>,
    #[schemars(
        description = "Arguments as JSON array (supports basic types: address, uint/int, bool, string, bytes)"
    )]
    pub args: Option<Value>,
    #[schemars(description = "Optional value in wei (decimal string or 0x hex)")]
    pub value_wei: Option<String>,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
    #[schemars(
        description = "If true, only build+preflight and return tx without signing/broadcasting"
    )]
    pub dry_run_only: Option<bool>,
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    pub allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmBuildContractTxRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(
        description = "Contract address (optional if contract_name/contract_query is provided)"
    )]
    pub address: Option<String>,
    #[schemars(description = "Contract name/alias in ABI registry (optional)")]
    pub contract_name: Option<String>,
    #[schemars(
        description = "Contract fuzzy query (e.g. 'usdc', 'cetus', partial address). Used if address/contract_name not provided."
    )]
    pub contract_query: Option<String>,
    #[schemars(
        description = "If true, pick the top fuzzy match automatically when contract_query returns multiple results"
    )]
    pub accept_best_match: Option<bool>,
    #[schemars(description = "Function name")]
    pub function: String,
    #[schemars(
        description = "Optional exact function signature (e.g. 'transfer(address,uint256)')"
    )]
    pub function_signature: Option<String>,
    #[schemars(
        description = "Arguments as JSON array (supports basic types: address, uint/int, bool, string, bytes)"
    )]
    pub args: Option<Value>,
    #[schemars(description = "Optional value in wei (decimal string or 0x hex)")]
    pub value_wei: Option<String>,
    #[schemars(description = "Optional gas limit override")]
    pub gas_limit: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetObjectRequest {
    #[schemars(description = "The object ID to query (hex format starting with 0x)")]
    pub object_id: String,
    #[schemars(description = "Include content in response (default: true)")]
    pub show_content: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetOwnedObjectsRequest {
    #[schemars(description = "The Sui address to query (hex format starting with 0x)")]
    pub address: String,
    #[schemars(description = "Optional limit on number of results (max 50)")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetTransactionRequest {
    #[schemars(description = "The transaction digest to query (base58 encoded)")]
    pub digest: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct QueryEventsRequest {
    #[schemars(description = "The transaction digest to query events for")]
    pub digest: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetCoinsRequest {
    #[schemars(description = "The Sui address to query")]
    pub address: String,
    #[schemars(description = "Optional coin type (defaults to 0x2::sui::SUI)")]
    pub coin_type: Option<String>,
    #[schemars(description = "Optional limit on number of results")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct WalletOverviewRequest {
    #[schemars(description = "Optional Sui address to query")]
    pub address: Option<String>,
    #[schemars(
        description = "Optional signer address or alias (used if address is omitted and keystore has multiple accounts)"
    )]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Optional coin type for balance/coins (defaults to 0x2::sui::SUI)")]
    pub coin_type: Option<String>,
    #[schemars(description = "Include coin objects in response (default: false)")]
    pub include_coins: Option<bool>,
    #[schemars(description = "Optional limit for coin objects (default: 20, max: 50)")]
    pub coins_limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct TransactionTemplateRequest {
    #[schemars(description = "Template name: transfer_sui|transfer_object|stake|unstake|pay_sui")]
    pub template: String,
    #[schemars(description = "Sender address (required for templates)")]
    pub sender: String,
    #[schemars(description = "Recipient address (transfer_sui, transfer_object, pay_sui)")]
    pub recipient: Option<String>,
    #[schemars(description = "Object ID to transfer (transfer_object)")]
    pub object_id: Option<String>,
    #[schemars(description = "Validator address (stake)")]
    pub validator: Option<String>,
    #[schemars(description = "Staked SUI object id (unstake)")]
    pub staked_sui: Option<String>,
    #[schemars(description = "Optional amount in raw SUI (transfer_sui/pay_sui/stake)")]
    pub amount: Option<u64>,
    #[schemars(description = "Recipients for pay_sui")]
    pub recipients: Option<Vec<String>>,
    #[schemars(description = "Amounts for pay_sui")]
    pub amounts: Option<Vec<u64>>,
    #[schemars(description = "Optional gas budget (default: 1_000_000)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ZkLoginExecuteTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    pub tx_bytes: String,
    #[schemars(description = "ZkLogin inputs JSON string from prover")]
    pub zk_login_inputs_json: String,
    #[schemars(description = "Address seed used for zkLogin (decimal string)")]
    pub address_seed: String,
    #[schemars(description = "Maximum epoch for the zkLogin signature")]
    pub max_epoch: u64,
    #[schemars(description = "Ephemeral user signature over tx bytes (base64 flag||sig||pubkey)")]
    pub user_signature: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct VerifyZkLoginSignatureRequest {
    #[schemars(description = "Base64-encoded bytes to verify (transaction bytes or message)")]
    pub bytes: String,
    #[schemars(description = "Base64-encoded zkLogin signature bytes")]
    pub signature: String,
    #[schemars(description = "Sui address that should match the zkLogin address")]
    pub address: String,
    #[schemars(
        description = "Intent scope: transaction or personal_message (default: transaction)"
    )]
    pub intent_scope: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct KeystoreAccountsRequest {
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct KeystoreSignTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    pub tx_bytes: String,
    #[schemars(
        description = "Signer address or alias (required if multiple accounts in keystore)"
    )]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct KeystoreExecuteTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    pub tx_bytes: String,
    #[schemars(
        description = "Signer address or alias (required if multiple accounts in keystore)"
    )]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildTransferObjectRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Object ID to transfer")]
    pub object_id: String,
    #[schemars(description = "Recipient address")]
    pub recipient: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildTransferSuiRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Recipient address")]
    pub recipient: String,
    #[schemars(description = "Optional amount to transfer; omit to transfer all")]
    pub amount: Option<u64>,
    #[schemars(description = "Input coin object IDs used for payment")]
    pub input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Automatically select input coins when empty (default: true)")]
    pub auto_select_coins: Option<bool>,
    #[schemars(
        description = "Confirm large transfer when amount exceeds threshold (default: false)"
    )]
    pub confirm_large_transfer: Option<bool>,
    #[schemars(
        description = "Large transfer threshold in raw SUI (default: 1_000_000_000 = 1 SUI)"
    )]
    pub large_transfer_threshold: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ExecuteTransferSuiRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Recipient address")]
    pub recipient: String,
    #[schemars(description = "Optional amount to transfer; omit to transfer all")]
    pub amount: Option<u64>,
    #[schemars(description = "Input coin object IDs used for payment")]
    pub input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Automatically select input coins when empty (default: true)")]
    pub auto_select_coins: Option<bool>,
    #[schemars(
        description = "Confirm large transfer when amount exceeds threshold (default: false)"
    )]
    pub confirm_large_transfer: Option<bool>,
    #[schemars(
        description = "Large transfer threshold in raw SUI (default: 1_000_000_000 = 1 SUI)"
    )]
    pub large_transfer_threshold: Option<u64>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
    #[schemars(description = "Merge small SUI coins before transfer (default: false)")]
    pub auto_merge_small_coins: Option<bool>,
    #[schemars(description = "Merge when coin count exceeds this threshold (default: 10)")]
    pub merge_threshold: Option<usize>,
    #[schemars(description = "Maximum number of coins to merge (default: 10)")]
    pub merge_max_inputs: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ExecuteTransferObjectRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Object ID to transfer")]
    pub object_id: String,
    #[schemars(description = "Recipient address")]
    pub recipient: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    pub confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ExecutePaySuiRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Recipients")]
    pub recipients: Vec<String>,
    #[schemars(description = "Amounts in raw SUI")]
    pub amounts: Vec<u64>,
    #[schemars(description = "Input coin object IDs used for payment")]
    pub input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
    #[schemars(
        description = "Confirm sensitive action (required). If false, a confirmation_id is returned."
    )]
    pub confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SuiConfirmExecutionRequest {
    #[schemars(description = "Confirmation id (sui_confirm_...)")]
    pub id: String,
    #[schemars(description = "Tx summary hash (0x...) to prevent stale/changed tx")]
    pub tx_summary_hash: String,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Signer address or alias (optional; defaults to tx sender)")]
    pub signer: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution at confirm-time (default: true)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SuiListPendingConfirmationsRequest {
    #[schemars(description = "Max items (default 20, max 200)")]
    pub limit: Option<u64>,
    #[schemars(description = "Filter by status: pending|consumed|sent|failed")]
    pub status: Option<String>,
    #[schemars(description = "Include tx_bytes_b64 in response (default false)")]
    pub include_tx_bytes: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SuiGetPendingConfirmationRequest {
    #[schemars(description = "Confirmation id (sui_confirm_...)")]
    pub id: String,
    #[schemars(description = "Include tx_bytes_b64 in response (default true)")]
    pub include_tx_bytes: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SuiRetryPendingConfirmationRequest {
    #[schemars(description = "Confirmation id (sui_confirm_...)")]
    pub id: String,
    #[schemars(description = "Tx summary hash (0x...) to prevent stale/changed tx")]
    pub tx_summary_hash: String,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Signer address or alias (optional; defaults to tx sender)")]
    pub signer: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution at retry-time (default: true)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ExecuteAddStakeRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Validator address")]
    pub validator: String,
    #[schemars(description = "Input coin object IDs used for stake")]
    pub coins: Vec<String>,
    #[schemars(description = "Optional amount to stake")]
    pub amount: Option<u64>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    pub confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ExecuteWithdrawStakeRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Staked SUI object id")]
    pub staked_sui: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    pub confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildPaySuiRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Recipient addresses")]
    pub recipients: Vec<String>,
    #[schemars(description = "Amounts for recipients")]
    pub amounts: Vec<u64>,
    #[schemars(description = "Input coin object IDs used for payment (first coin used as gas)")]
    pub input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildPayAllSuiRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Recipient address")]
    pub recipient: String,
    #[schemars(description = "Input coin object IDs used for payment (first coin used as gas)")]
    pub input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildMoveCallRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments, e.g. 0x2::sui::SUI")]
    pub type_args: Vec<String>,
    #[schemars(description = "Move call arguments as JSON values")]
    pub arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildPublishRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Compiled Move modules (base64 BCS) in order")]
    pub compiled_modules: Vec<String>,
    #[schemars(description = "Dependency package object IDs")]
    pub dependencies: Vec<String>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildSplitCoinRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Coin object ID to split")]
    pub coin_object_id: String,
    #[schemars(description = "Split amounts")]
    pub split_amounts: Vec<u64>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildMergeCoinsRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Primary coin object ID")]
    pub primary_coin: String,
    #[schemars(description = "Coin object ID to merge")]
    pub coin_to_merge: String,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildBatchTransactionRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Batch transaction requests")]
    pub requests: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ExecuteBatchTransactionRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Batch transaction requests")]
    pub requests: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    pub signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    pub keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    pub allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    pub preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    pub allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    pub confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildAddStakeRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Validator address to stake with")]
    pub validator: String,
    #[schemars(description = "Coin object IDs to stake")]
    pub coins: Vec<String>,
    #[schemars(description = "Optional amount to stake (uses all if omitted)")]
    pub amount: Option<u64>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildWithdrawStakeRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Staked SUI object ID")]
    pub staked_sui: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct BuildUpgradeRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID to upgrade")]
    pub package_id: String,
    #[schemars(description = "Compiled Move modules (base64 BCS) in order")]
    pub compiled_modules: Vec<String>,
    #[schemars(description = "Dependency package object IDs")]
    pub dependencies: Vec<String>,
    #[schemars(description = "Upgrade capability object ID")]
    pub upgrade_capability: String,
    #[schemars(description = "Upgrade policy as u8")]
    pub upgrade_policy: u8,
    #[schemars(description = "Digest bytes (base64)")]
    pub digest: String,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct DryRunTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    pub tx_bytes: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct DevInspectTransactionRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    pub tx_bytes: String,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
    #[schemars(description = "Optional epoch override")]
    pub epoch: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetStakesRequest {
    #[schemars(description = "Owner address to query stakes for")]
    pub owner: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetCommitteeInfoRequest {
    #[schemars(description = "Optional epoch to query")]
    pub epoch: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetCheckpointRequest {
    #[schemars(description = "Checkpoint sequence number")]
    pub sequence_number: Option<u64>,
    #[schemars(description = "Checkpoint digest")]
    pub digest: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetCheckpointsRequest {
    #[schemars(description = "Optional cursor (checkpoint sequence number)")]
    pub cursor: Option<u64>,
    #[schemars(description = "Optional limit on results (max 100)")]
    pub limit: Option<usize>,
    #[schemars(description = "Return in descending order")]
    pub descending_order: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct QueryTransactionBlocksRequest {
    #[schemars(description = "Optional transaction filter as JSON")]
    pub filter: Option<Value>,
    #[schemars(description = "Optional cursor (transaction digest)")]
    pub cursor: Option<String>,
    #[schemars(description = "Optional limit on results (max 50)")]
    pub limit: Option<usize>,
    #[schemars(description = "Return in descending order")]
    pub descending_order: Option<bool>,
    #[schemars(description = "Optional response options")]
    pub options: Option<TransactionResponseOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct MultiGetTransactionsRequest {
    #[schemars(description = "Transaction digests to fetch")]
    pub digests: Vec<String>,
    #[schemars(description = "Optional response options")]
    pub options: Option<TransactionResponseOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SelectCoinsRequest {
    #[schemars(description = "Owner address to select coins from")]
    pub owner: String,
    #[schemars(description = "Optional coin type")]
    pub coin_type: Option<String>,
    #[schemars(description = "Total amount to cover")]
    pub amount: u128,
    #[schemars(description = "Object IDs to exclude")]
    pub exclude: Vec<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetCoinMetadataRequest {
    #[schemars(description = "Coin type to query")]
    pub coin_type: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetTotalSupplyRequest {
    #[schemars(description = "Coin type to query")]
    pub coin_type: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetNormalizedMoveModulesRequest {
    #[schemars(description = "Package object ID")]
    pub package: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetDynamicFieldsRequest {
    #[schemars(description = "Parent object ID")]
    pub object_id: String,
    #[schemars(description = "Optional cursor (dynamic field object ID)")]
    pub cursor: Option<String>,
    #[schemars(description = "Optional limit on results (max 50)")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetDynamicFieldObjectRequest {
    #[schemars(description = "Parent object ID")]
    pub parent_object_id: String,
    #[schemars(description = "Dynamic field name type")]
    pub name_type: String,
    #[schemars(description = "Dynamic field name value (JSON)")]
    pub name_value: Value,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetMoveObjectBcsRequest {
    #[schemars(description = "Object ID")]
    pub object_id: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ObjectOptionsRequest {
    #[schemars(description = "Include object type")]
    pub show_type: Option<bool>,
    #[schemars(description = "Include owner")]
    pub show_owner: Option<bool>,
    #[schemars(description = "Include previous transaction")]
    pub show_previous_transaction: Option<bool>,
    #[schemars(description = "Include display metadata")]
    pub show_display: Option<bool>,
    #[schemars(description = "Include content")]
    pub show_content: Option<bool>,
    #[schemars(description = "Include BCS bytes")]
    pub show_bcs: Option<bool>,
    #[schemars(description = "Include storage rebate")]
    pub show_storage_rebate: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetPastObjectRequest {
    #[schemars(description = "Object ID")]
    pub object_id: String,
    #[schemars(description = "Object version")]
    pub version: u64,
    #[schemars(description = "Optional object response options")]
    pub options: Option<ObjectOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct PastObjectRequestItem {
    #[schemars(description = "Object ID")]
    pub object_id: String,
    #[schemars(description = "Object version")]
    pub version: u64,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct MultiGetPastObjectsRequest {
    #[schemars(description = "Objects to query")]
    pub objects: Vec<PastObjectRequestItem>,
    #[schemars(description = "Optional object response options")]
    pub options: Option<ObjectOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetAllCoinsRequest {
    #[schemars(description = "Owner address")]
    pub owner: String,
    #[schemars(description = "Optional cursor")]
    pub cursor: Option<String>,
    #[schemars(description = "Optional limit on results")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct DescribeMoveFunctionRequest {
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GenerateModuleTemplatesRequest {
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Optional module name to scope results")]
    pub module: Option<String>,
    #[schemars(description = "Only include entry functions (default true)")]
    pub entry_only: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SuggestObjectMethodsRequest {
    #[schemars(description = "Object ID to inspect")]
    pub object_id: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GetDynamicFieldTreeRequest {
    #[schemars(description = "Parent object ID")]
    pub object_id: String,
    #[schemars(description = "Maximum recursion depth (default 2)")]
    pub max_depth: Option<usize>,
    #[schemars(description = "Limit per level (default 50)")]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GenerateMoveCallFormSchemaRequest {
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Maximum struct expansion depth (default 2)")]
    pub max_struct_depth: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SuggestMoveCallInputsRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Limit owned objects to scan")]
    pub limit: Option<usize>,
    #[schemars(description = "Optional gas budget for auto gas selection")]
    pub gas_budget: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ResolveMoveCallArgsRequest {
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments")]
    pub type_args: Vec<String>,
    #[schemars(description = "Arguments as JSON values")]
    pub arguments: Vec<Value>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct AutoExecuteMoveCallRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments")]
    pub type_args: Vec<String>,
    #[schemars(description = "Arguments as JSON values")]
    pub arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
    #[schemars(description = "ZkLogin inputs JSON string from prover")]
    pub zk_login_inputs_json: String,
    #[schemars(description = "Address seed used for zkLogin (decimal string)")]
    pub address_seed: String,
    #[schemars(description = "Maximum epoch for the zkLogin signature")]
    pub max_epoch: u64,
    #[schemars(description = "Ephemeral user signature over tx bytes (base64 flag||sig||pubkey)")]
    pub user_signature: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct PrepareMoveCallRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments")]
    pub type_args: Vec<String>,
    #[schemars(description = "Arguments as JSON values")]
    pub arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct AutoFillMoveCallRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments (optional, will infer if empty)")]
    pub type_args: Option<Vec<String>>,
    #[schemars(description = "Arguments as JSON values; use null or '<auto>' for object params")]
    pub arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct DappManifestRequest {
    #[schemars(
        description = "Optional manifest file path (defaults to SUI_DAPP_MANIFEST or ./dapps.json)"
    )]
    pub path: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct DappMoveCallRequest {
    #[schemars(description = "Dapp name as listed in manifest")]
    pub dapp: String,
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments (optional)")]
    pub type_args: Option<Vec<String>>,
    #[schemars(description = "Arguments as JSON values; use null or '<auto>' for object params")]
    pub arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
    #[schemars(
        description = "Optional manifest file path (defaults to SUI_DAPP_MANIFEST or ./dapps.json)"
    )]
    pub manifest_path: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DappManifest {
    pub dapps: Vec<DappEntry>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DappEntry {
    pub name: String,
    pub package: String,
    pub modules: Option<Vec<String>>,
    pub functions: Option<Vec<DappFunctionEntry>>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DappFunctionEntry {
    pub module: String,
    pub function: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct AutoPrepareMoveCallRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Type arguments (optional, will infer if empty)")]
    pub type_args: Option<Vec<String>>,
    #[schemars(description = "Arguments as JSON values; use null or '<auto>' for object params")]
    pub arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    pub gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GenerateMoveCallPayloadRequest {
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Package object ID")]
    pub package: String,
    #[schemars(description = "Move module name")]
    pub module: String,
    #[schemars(description = "Move function name")]
    pub function: String,
    #[schemars(description = "Optional gas budget")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas price")]
    pub gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GraphqlQueryRequest {
    #[schemars(description = "GraphQL endpoint (defaults to SUI_GRAPHQL_URL)")]
    pub endpoint: Option<String>,
    #[schemars(description = "GraphQL query string")]
    pub query: String,
    #[schemars(description = "GraphQL variables")]
    pub variables: Option<Value>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct RpcServiceInfoRequest {
    #[schemars(description = "gRPC endpoint (defaults to SUI_GRPC_URL)")]
    pub endpoint: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct VerifySimpleSignatureRequest {
    #[schemars(description = "Message bytes (base64)")]
    pub message_base64: String,
    #[schemars(description = "Simple signature (base64 flag||sig||pk)")]
    pub signature_base64: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct GraphqlHelperRequest {
    #[schemars(description = "GraphQL endpoint (defaults to SUI_GRAPHQL_URL)")]
    pub endpoint: Option<String>,
    #[schemars(
        description = "Helper type: chain_info|object|balance|transaction|checkpoint|events|coins"
    )]
    pub helper: String,
    #[schemars(description = "Optional address for balance")]
    pub address: Option<String>,
    #[schemars(description = "Optional object id")]
    pub object_id: Option<String>,
    #[schemars(description = "Optional transaction digest")]
    pub digest: Option<String>,
    #[schemars(description = "Optional checkpoint sequence")]
    pub checkpoint: Option<u64>,
    #[schemars(description = "Optional limit")]
    pub limit: Option<u64>,
    #[schemars(description = "Optional selection set for helper")]
    pub selection: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct IntentRequest {
    #[schemars(description = "Natural language instruction")]
    pub text: String,
    #[schemars(description = "Optional sender address")]
    pub sender: Option<String>,
    #[schemars(description = "Optional network override")]
    pub network: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct IntentExecuteRequest {
    #[schemars(description = "Natural language instruction")]
    pub text: String,
    #[schemars(description = "Sender address")]
    pub sender: String,
    #[schemars(description = "Optional network override")]
    pub network: Option<String>,
    #[schemars(description = "Optional input coins for transfers/staking")]
    pub input_coins: Option<Vec<String>>,
    #[schemars(description = "Optional amount override")]
    pub amount: Option<u64>,
    #[schemars(description = "Optional recipient")]
    pub recipient: Option<String>,
    #[schemars(description = "Optional object id (transfer object)")]
    pub object_id: Option<String>,
    #[schemars(description = "Optional validator address for staking")]
    pub validator: Option<String>,
    #[schemars(description = "Optional staked SUI object id for withdraw")]
    pub staked_sui: Option<String>,
    #[schemars(description = "Optional package for move call intents")]
    pub package: Option<String>,
    #[schemars(description = "Optional module for move call intents")]
    pub module: Option<String>,
    #[schemars(description = "Optional function for move call intents")]
    pub function: Option<String>,
    #[schemars(description = "Optional type arguments for move call intents")]
    pub type_args: Option<Vec<String>>,
    #[schemars(description = "Optional arguments for move call intents")]
    pub arguments: Option<Vec<Value>>,
    #[schemars(description = "Gas budget")]
    pub gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    pub gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price")]
    pub gas_price: Option<u64>,
    #[schemars(description = "ZkLogin inputs JSON string from prover")]
    pub zk_login_inputs_json: Option<String>,
    #[schemars(description = "Address seed used for zkLogin (decimal string)")]
    pub address_seed: Option<String>,
    #[schemars(description = "Maximum epoch for the zkLogin signature")]
    pub max_epoch: Option<u64>,
    #[schemars(description = "Ephemeral user signature over tx bytes (base64 flag||sig||pubkey)")]
    pub user_signature: Option<String>,
}
