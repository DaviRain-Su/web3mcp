# Sui MCP Server

A [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server for interacting with the Sui blockchain. Built using the official [Rust MCP SDK](https://github.com/modelcontextprotocol/rust-sdk).

## Features

This MCP server provides tools for querying the Sui blockchain:

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

The compiled binary will be available at `target/release/sui-mcp`.

## Usage

### With Claude Desktop

Add this to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "sui": {
      "command": "/path/to/sui-mcp/target/release/sui-mcp",
      "env": {
        "SUI_RPC_URL": "https://fullnode.mainnet.sui.io:443"
      }
    }
  }
}
```

### Environment Variables

- `SUI_RPC_URL` - The Sui RPC endpoint to use (defaults to `https://fullnode.mainnet.sui.io:443`)

Available networks:
- **Mainnet**: `https://fullnode.mainnet.sui.io:443`
- **Testnet**: `https://fullnode.testnet.sui.io:443`
- **Devnet**: `https://fullnode.devnet.sui.io:443`

### Standalone Usage

You can also run the server directly via stdio:

```bash
# Use default mainnet endpoint
./target/release/sui-mcp

# Or specify a custom RPC URL
SUI_RPC_URL=https://fullnode.testnet.sui.io:443 ./target/release/sui-mcp
```

## Example Queries

Once configured with Claude Desktop, you can ask Claude to:

- "What is the SUI balance of address 0x..."
- "Show me the objects owned by address 0x..."
- "Get the details of transaction ABC..."
- "What is the current gas price on Sui?"
- "Show me all balances for address 0x..."

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
    "gas_budget": 10000000
  }
}
```

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

## Local Keystore (no zkLogin)

This server can sign and execute transactions using your local Sui keystore (e.g. `~/.sui/sui_config/sui.keystore`).

### Environment Variables

- `SUI_KEYSTORE_PATH` - Optional keystore path override

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

1. **SuiMcpServer** - Main server struct that handles RPC communication
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
