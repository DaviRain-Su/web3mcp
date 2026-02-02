# Web3MCP Server

A [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server for interacting with multiple chains:

- **Sui**
- **Solana** (including Solana IDL-driven dynamic calls)
- **EVM** (multi-chain via `chain_id` + per-chain RPC env vars)

Built using the official [Rust MCP SDK](https://github.com/modelcontextprotocol/rust-sdk).

## Features

This MCP server provides tools across chains (the list below is not exhaustive):

- **get_balance** - Get the balance of SUI or other coins for an address
- **get_all_balances** - Get all coin balances for an address
- **get_object** - Get detailed information about a Sui object by its ID
- **get_owned_objects** - Get all objects owned by an address
- **get_transaction** - Get detailed information about a transaction by its digest
- **get_reference_gas_price** - Get the current reference gas price
- **query_transaction_events** - Query events emitted by a transaction
- **get_latest_checkpoint_sequence** - Get the latest checkpoint sequence number
- **get_total_transactions** - Get the total number of transactions on the network
- **get_coins** - Get all coins of a specific type owned by an address
- **get_chain_identifier** - Get the chain identifier for the Sui network
- **get_protocol_config** - Get the protocol configuration

## Installation

### Build from source

```bash
cargo build --release
```

The compiled binary will be available at `target/release/web3mcp`.

## Usage

### With Claude Desktop

Add this to your Claude Desktop configuration file:

**macOS**: `~/Library/Application\ Support/Claude/claude_desktop_config.json`
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "sui": {
      "command": "/path/to/web3mcp/target/release/web3mcp",
      "env": {
        "SUI_RPC_URL": "https://fullnode.mainnet.sui.io:443"
      }
    }
  }
}
```

### Environment Variables

Sui:
- `SUI_RPC_URL` - Sui RPC endpoint (defaults to `https://fullnode.mainnet.sui.io:443`)

EVM:
- `EVM_DEFAULT_CHAIN_ID` - Default EVM chain id (defaults to Base Sepolia `84532`)
- `EVM_RPC_URL_<chain_id>` - Override the RPC URL for an EVM chain (e.g. `EVM_RPC_URL_8453=https://mainnet.base.org`).
  If not set, the server falls back to built-in public RPC defaults for common chains.

Tip:
- Use the tool `evm_list_rpc_defaults` to see which chain IDs have built-in defaults.

## Mainnet safety (Solana / Sui / EVM)

For **mainnet** transactions, the server enforces a stricter workflow:
- Tools that would broadcast a tx will return a **pending confirmation** instead.
- Broadcasting requires a second step with an explicit `confirm_token`.

This is designed to reduce accidental mainnet sends.

### Quick flows (copy/paste)

EVM (mainnet):
1) Build + preflight (safe)
2) Create pending confirmation (safe; returns `confirm_token`)
3) Send via retry (requires token on mainnet)

Example (Base mainnet `chain_id=8453`):

1) Build
```json
{
  "tool": "evm_build_transfer_native",
  "args": {
    "chain_id": 8453,
    "sender": "0xSENDER...",
    "recipient": "0xRECIPIENT...",
    "amount": "0.000001"
  }
}
```

2) Preflight (fills nonce/gas/fees)
```json
{
  "tool": "evm_preflight",
  "args": {
    "tx": "<paste tx from step 1 output>"
  }
}
```

3) Create pending confirmation (returns confirm_token)
```json
{
  "tool": "evm_create_pending_confirmation",
  "args": {
    "tx": "<paste tx from step 2 output>",
    "label": "base-mainnet-transfer"
  }
}
```

4) Broadcast (mainnet requires confirm_token)
```json
{
  "tool": "evm_retry_pending_confirmation",
  "args": {
    "id": "<confirmation_id>",
    "tx_summary_hash": "<tx_summary_hash>",
    "confirm_token": "<confirm_token>"
  }
}
```

Solana (mainnet):

0) Check networks
```json
{ "tool": "solana_list_networks", "args": {} }
```

1) Create a pending confirmation (safe; does not broadcast)
```json
{
  "tool": "solana_send_transaction",
  "args": {
    "network": "mainnet",
    "transaction_base64": "<TX_BASE64>",
    "confirm": false
  }
}
```

2) Broadcast (mainnet requires confirm_token)
```json
{
  "tool": "solana_confirm_transaction",
  "args": {
    "id": "<pending_confirmation_id>",
    "hash": "<tx_summary_hash>",
    "confirm_token": "<confirm_token>",
    "commitment": "confirmed"
  }
}
```

Sui (mainnet):

0) Check networks
```json
{ "tool": "sui_list_networks", "args": {} }
```

1) Create a pending confirmation using a safe-default Sui tx tool (does not broadcast)
- Run the tool with `confirm=false` (it will return `confirmation_id` + `tx_summary_hash`).

2) Broadcast (mainnet requires confirm_token)
```json
{
  "tool": "sui_confirm_execution",
  "args": {
    "id": "<confirmation_id>",
    "tx_summary_hash": "<tx_summary_hash>",
    "confirm_token": "<confirm_token>",
    "keystore_path": "<PATH_TO_SUI_KEYSTORE>"
  }
}
```

Token helpers (optional, used by the intent router for `get_coins` when the user says "USDC" / "USDT"):

Sui:
- `SUI_USDC_COIN_TYPE` - Full Sui coin type string for USDC (overrides built-in defaults)
- `SUI_USDT_COIN_TYPE` - Full Sui coin type string for USDT

EVM:
- `EVM_USDC_ADDRESS_<chain_id>` - Override USDC ERC20 contract address for a specific chain id (e.g. `EVM_USDC_ADDRESS_8453=0x...`).
  (We ship built-in defaults for several Circle-supported chains; see source link below.)
- `EVM_USDT_ADDRESS_<chain_id>` - Optional override for USDT ERC20 contract address (env-only; no built-in defaults).

Built-in defaults (can be overridden):
- USDC mainnet: `0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC`
- USDC testnet: `0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC`

Selection rule:
- If `SUI_NETWORK` contains `test` or `SUI_RPC_URL` contains `testnet` → use testnet USDC
- Else → use mainnet USDC

Source:
- Circle Docs “USDC Contract Addresses”
  <https://developers.circle.com/stablecoins/usdc-contract-addresses>
- (Also referenced by) Circle blog “Now Available: Native USDC on Sui”
  <https://www.circle.com/blog/now-available-native-usdc-on-sui>

How to find these values:
- Use a Sui token list / explorer for your target network (mainnet/testnet) and copy the **coin type** string.
- Keep them as env vars so you can change networks without rebuilding.

Available networks:
- **Mainnet**: `https://fullnode.mainnet.sui.io:443`
- **Testnet**: `https://fullnode.testnet.sui.io:443`
- **Devnet**: `https://fullnode.devnet.sui.io:443`

### Standalone Usage

You can also run the server directly via stdio:

```bash
# Use default mainnet endpoint
./target/release/web3mcp

# Or specify a custom RPC URL
SUI_RPC_URL=https://fullnode.testnet.sui.io:443 ./target/release/web3mcp
```

## Example Queries

Once configured with Claude Desktop, you can ask Claude to:

- "What is the SUI balance of address 0x..."
- "Show me the objects owned by address 0x..."
- "Get the details of transaction ABC..."
- "What is the current gas price on Sui?"
- "Show me all balances for address 0x..."

## Intent Router

Design notes for the multi-chain intent router are in `docs/intent-router.md`.
Chinese version: `docs/intent-router.zh.md`.

## Claude Prompts

See `docs/claude-prompts.md` for ready-to-use prompts.

## Troubleshooting

- Quick check: `system_network_context`
- Full diagnostics bundle: `system_debug_bundle` (optionally `out_path=./debug_bundle.json`)

See:
- `docs/troubleshooting.md`
- `docs/tx-tools.md` (transaction tools & safety model)
- `docs/prompts/` (prompt packs)

## Multi-chain adapters

Adapters live at `src/intent/adapters.rs`.

## Solana (overview)

This server includes **Solana** tooling oriented around:

- keeping Claude Desktop tool lists small (minimal default surface)
- enabling more advanced Solana workflows (IDL planning/simulation) behind an optional feature
- safer execution defaults via **pending confirmation** (confirm/broadcast is a separate step)

### Minimal Solana tool surface (Claude Desktop-friendly)

Default builds expose a small set of Solana tools, including:

- `solana_rpc_call` (raw JSON-RPC; defaults to `result_only=true`, supports `result_path`)
- `solana_send_transaction` (safe default: creates a pending confirmation)
- `solana_confirm_transaction` (broadcast a pending tx)
- pending store helpers (`solana_list_pending_confirmations`, `solana_get_pending_confirmation`, `solana_cleanup_pending_confirmations`)

### Enable extended Solana tools (for agents / power users)

Build with:

```bash
cargo build --release --features solana-extended-tools
```

This enables additional Solana tools including **IDL helpers** such as:

- `solana_idl_plan_instruction` (returns missing args/accounts, enum variants, example arg shapes)
- `solana_idl_simulate_instruction` (returns ok/error_class/suggest_fix/logs_excerpt)
- `solana_idl_execute` (pending-confirm safe default)

### ACP (Agent Commerce Protocol) integration

If you are integrating with Virtuals ACP and using an executor agent pattern, see:

- `docs/acp-integration.md`
- `docs/acp-executor-prompt.md`
- `docs/acp-main-agent-template.md`
- `examples/acp/`

## Human-friendly EVM network mapping (testnet-first)

## ABI Registry (EVM)

This repo supports a dir-based ABI registry so you can add new DApps without modifying code.

Default location (can be overridden with `EVM_ABI_REGISTRY_DIR`):
- `~/.web3mcp/abi_registry/evm/<chain_id>/<address>.json`

An ERC20 ABI template is included:
- `abi_registry/evm/84532/erc20.example.json`

To use it, copy it and replace `address` with your token contract address (keep the file name as the address):
- `abi_registry/evm/84532/0xYourTokenAddressHere.json`

This server is evolving into a multi-chain MCP server. For EVM execution, we keep the user experience human-friendly:
users can say “Base testnet”, “Ethereum Sepolia”, “Arbitrum testnet”, etc., and the intent router maps that to an EVM `chain_id`.

### Built-in mapping

Defaults prefer **testnets** to reduce the risk of accidental mainnet transfers.

- Base
  - Base Sepolia / Base testnet → `chain_id=84532`
  - Base mainnet → `chain_id=8453`
- Ethereum
  - Sepolia / Ethereum testnet → `chain_id=11155111`
  - Ethereum mainnet → `chain_id=1`
- Arbitrum
  - Arbitrum Sepolia / Arbitrum testnet → `chain_id=421614`
  - Arbitrum One mainnet → `chain_id=42161`
- BSC
  - BSC testnet / BNB testnet → `chain_id=97`
  - BSC mainnet → `chain_id=56`

### EVM RPC configuration

Configure RPC URLs per chain id:

- `EVM_RPC_URL_<chainId>` (e.g. `EVM_RPC_URL_84532=https://sepolia.base.org`)
- `EVM_DEFAULT_CHAIN_ID` (recommended: `84532`)

### EVM signing

EVM execution currently supports local signing via:

- `EVM_PRIVATE_KEY=0x...` (use a testnet key)

## Dapp Manifest

You can dynamically load Sui dapps via a manifest file (`dapps.json` by default). Use `list_dapps` and `dapp_move_call_payload` to generate call payloads.

The example manifest `examples/dapps.json` includes Cetus mainnet/testnet package IDs.

### Example: Build transfer without coin selection

```json
{
  "tool": "build_transfer_sui",
  "params": {
    "sender": "0x...",
    "recipient": "0x...",
    "amount": 10000000,
    "input_coins": [],
    "auto_select_coins": true,
    "confirm_large_transfer": true,
    "gas_budget": 10000000
  }
}
```

### Example: Execute transfer with local keystore

```json
{
  "tool": "execute_transfer_sui",
  "params": {
    "sender": "0x...",
    "recipient": "0x...",
    "amount": 10000000,
    "input_coins": [],
    "auto_select_coins": true,
    "confirm_large_transfer": true,
    "gas_budget": 10000000,
    "signer": "0x..."
  }
}
```

Other one-step execute tools:

- `execute_transfer_object`
- `execute_pay_sui`
- `execute_add_stake`
- `execute_withdraw_stake`
- `execute_batch_transaction`

### Safety checks

- `build_transfer_sui` will require `confirm_large_transfer=true` when the amount exceeds the threshold (default: 1 SUI).
- `sign_transaction_with_keystore` and `execute_transaction_with_keystore` require `allow_sender_mismatch=true` if the signer differs from the transaction sender.

### Gas estimation

When `gas_budget` is omitted on build/execute tools, the server will dry-run the transaction, estimate gas usage, and apply a buffer.

### Preflight

Execution tools accept `preflight=true` to run a dry-run before signing. If the dry-run fails, execution stops unless `allow_preflight_failure=true`.

### Audit log

Set `WEB3MCP_AUDIT_LOG` to enable JSONL audit logs (defaults to `~/.web3mcp/audit.log`).

Back-compat: `SUI_MCP_AUDIT_LOG` is still supported for older configs.

### Example: Wallet overview

```json
{
  "tool": "get_wallet_overview",
  "params": {
    "address": "0x...",
    "include_coins": true,
    "coins_limit": 10
  }
}
```

### Example: Transaction template

```json
{
  "tool": "get_transaction_template",
  "params": {
    "template": "transfer_sui",
    "sender": "0x...",
    "recipient": "0x..."
  }
}
```

## Local Keystore (no zkLogin)

This server can sign and execute transactions using your local Sui keystore (e.g. `~/.sui/sui_config/sui.keystore`).

### Environment Variables

- `SUI_KEYSTORE_PATH` - Optional keystore path override
- `SUI_DEFAULT_SIGNER` - Default signer address or alias when multiple accounts exist

### Tools

- `get_keystore_accounts` - List keystore addresses and aliases
- `sign_transaction_with_keystore` - Sign transaction bytes using the local keystore
- `execute_transaction_with_keystore` - Sign and execute a transaction using the local keystore

### Example: Execute tx_bytes via keystore

```json
{
  "tool": "execute_transaction_with_keystore",
  "params": {
    "tx_bytes": "<base64 tx_bytes>",
    "signer": "0x..."
  }
}
```

## zkLogin (Google) Flow

This MCP server supports zkLogin execution without storing any local private key. The Google login and prover steps should happen in your frontend or wallet, then pass the four fields to MCP.

### Frontend Flow (Connection-style)

1. Generate an ephemeral keypair in the client and derive a nonce for zkLogin.
2. Start Google OIDC login with the nonce.
3. Exchange the `id_token` with the Sui zkLogin prover to get:
   - `zk_login_inputs_json`
   - `address_seed`
   - `max_epoch`
4. Sign the transaction bytes with the ephemeral private key to get `user_signature` (base64 flag||sig||pubkey).
5. Call MCP with these fields to execute the transaction.

### Minimal Frontend Pseudocode (Google OIDC -> zkLogin -> MCP)

```ts
// Pseudocode only. Replace with your wallet or SDK utilities.
// 1) Create ephemeral keypair (keep in memory)
const { ephemeralKeypair, nonce, maxEpoch } = createEphemeralKeypairWithNonce();

// 2) Start Google OIDC with nonce
const idToken = await loginWithGoogleOidc({ nonce });

// 3) Call zkLogin prover
const proverResp = await fetch("https://prover-mainnet.sui.io/v1/zklogin", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    jwt: idToken,
    maxEpoch,
    // include your ephemeral public key / randomness per SDK
  })
}).then(r => r.json());

const { zk_login_inputs_json, address_seed, max_epoch } = proverResp;

// 4) Build tx bytes (from your own builder / wallet)
const tx_bytes = await buildTransactionBytes({ sender: zkLoginAddress });

// 5) Sign tx bytes with ephemeral private key
const user_signature = signWithEphemeralKeypair({ tx_bytes, ephemeralKeypair });

// 6) Call MCP tool
await mcp.call("execute_zklogin_transaction", {
  tx_bytes,
  zk_login_inputs_json,
  address_seed,
  max_epoch,
  user_signature
});
```

### Flow Diagram

```
User → Google OIDC → id_token
  │
  ├─(nonce + ephemeral pubkey)→ zkLogin Prover → zk_login_inputs_json + address_seed + max_epoch
  │
  └─(ephemeral privkey)→ user_signature (base64 flag||sig||pubkey)
                 │
                 └→ MCP execute_zklogin_transaction / auto_execute_move_call_filled
```

### Field Requirements

| Field | Source | Format | Notes |
| --- | --- | --- | --- |
| `zk_login_inputs_json` | Prover response | JSON string | From zkLogin prover; ties to `id_token` and nonce |
| `address_seed` | Prover response | Decimal string | Used to derive zkLogin address |
| `max_epoch` | Frontend / prover | u64 | Must match nonce epoch and prover response |
| `user_signature` | Ephemeral signing | Base64 flag\|\|sig\|\|pubkey | Signature over tx bytes using ephemeral key |

### Example App

See `examples/zklogin-google` for a runnable Vite app that mirrors a “Connect Google” flow and builds the MCP payload.

The example app also supports an all-in-one mode that runs the UI, HTTP bridge, and MCP server together.

### MCP HTTP Bridge

If you want the web app to directly call MCP, use the local HTTP bridge in `examples/mcp-http-bridge`.

### Local zkLogin Prover

If you don't have Enoki access, run a local prover via Docker in `examples/zklogin-prover-local`.

### Example: Execute a Move Call with zkLogin

```json
{
  "tool": "auto_execute_move_call_filled",
  "params": {
    "sender": "0x...",
    "package": "0x...",
    "module": "m",
    "function": "f",
    "type_args": [],
    "arguments": [],
    "gas_budget": 1000000,
    "gas_object_id": null,
    "gas_price": null,
    "zk_login_inputs_json": "<zk_login_inputs_json>",
    "address_seed": "<address_seed>",
    "max_epoch": 12345,
    "user_signature": "<base64 flag||sig||pubkey>"
  }
}
```

If you already have `tx_bytes`, you can use `execute_zklogin_transaction` directly with the same four zkLogin fields.

## Development

### Requirements

- Rust 1.75 or later
- Tokio async runtime

### Dependencies

- **rmcp** - Official Rust MCP SDK
- **tokio** - Async runtime
- **reqwest** - HTTP client for RPC calls
- **serde** / **serde_json** - JSON serialization
- **schemars** - JSON schema generation
- **anyhow** - Error handling

## Architecture

The server uses the Model Context Protocol to expose Sui blockchain functionality as tools that can be used by AI assistants like Claude. It communicates with Sui nodes via JSON-RPC and translates responses into a format suitable for AI consumption.

### Key Components

1. **Web3McpServer** - Main server struct that handles RPC communication
2. **Tool Router** - Automatically generated by the `#[tool_router]` macro to route tool calls
3. **Tool Definitions** - Each method annotated with `#[tool]` becomes an available tool
4. **ServerHandler** - Implements the MCP server protocol

## Resources

- [Model Context Protocol Documentation](https://modelcontextprotocol.io)
- [Rust MCP SDK](https://github.com/modelcontextprotocol/rust-sdk)
- [Sui Documentation](https://docs.sui.io)
- [Sui JSON-RPC API](https://docs.sui.io/references/sui-api)

## License

This project is licensed under the MIT License.
