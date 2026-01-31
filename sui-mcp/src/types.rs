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
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct EvmDecodeTransactionReceiptRequest {
    #[schemars(description = "EVM chain id")]
    pub chain_id: u64,
    #[schemars(
        description = "Transaction receipt JSON (as returned by evm_get_transaction_receipt)"
    )]
    pub receipt_json: Value,
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
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    pub allow_sender_mismatch: Option<bool>,
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
    #[schemars(description = "Confirm sensitive action (required)")]
    pub confirm: Option<bool>,
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
