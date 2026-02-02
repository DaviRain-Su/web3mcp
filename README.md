# Web3 Anywhere

**Web3 Anywhere** is a cross-chain MCP (Model Context Protocol) server that lets AI agents operate Web3 via natural language.

- **Current implementation**: `web3mcp/` (Rust) — **Sui + Solana (incl. Solana IDL dynamic calls) + EVM (chain_id/RPC)**
- **Positioning**: *DeFi-first, chain-agnostic* (long-term goal: connect all chains and broader Web3 capabilities)

## TL;DR

- Run the MCP server locally.
- Connect it to Claude Desktop / Cursor.
- Ask for balances, objects, transactions, and (when enabled) build/send transactions with safer workflows.

## What’s implemented today

### Capability matrix (high level)

- Sui
  - Read/query ✅
  - Tx build + pending confirmation ✅
  - Mainnet broadcast ✅ (requires `confirm_token`)
- Solana
  - Read/query ✅
  - IDL planning/simulation ✅
  - Mainnet broadcast ✅ (requires `confirm_token`)
- EVM
  - Read/query ✅
  - Tx build + preflight ✅
  - Mainnet broadcast ✅ (requires `confirm_token`; one-step transfer returns pending)

### Safety / ops
- **Audit log** ✅ (`WEB3MCP_AUDIT_LOG`, back-compat: `SUI_MCP_AUDIT_LOG`)
- **Mainnet safety** ✅ (pending confirmation + `confirm_token`)
- **Two-phase templates** ✅ (see `web3mcp/docs/acp-*` and examples)

## Quickstart (5 minutes)

See the server README:
- `web3mcp/README.md`

At minimum:
```bash
cd web3mcp
cargo build --release
```
Binary:
- `web3mcp/target/release/web3mcp`

## Example prompts (copy/paste)

### 0) Sanity check (recommended)
- "Run `system_network_context` and tell me what networks are active for Sui/Solana/EVM."

### Sui
- "On Sui testnet (set `SUI_RPC_URL=https://fullnode.testnet.sui.io:443`), use `get_balance` for 0x..."
- "On Sui testnet, use `get_owned_objects` for 0x..."
- "(Mainnet demo, safe) Build a Sui transaction using a safe-default tool so it returns a pending confirmation, then show me how `sui_confirm_execution` requires `confirm_token` on mainnet. Do not send until I confirm." 

### Solana
- "Use `solana_list_networks`, then on devnet use `solana_rpc_call` to getBalance for <base58_pubkey>."
- "(No send) Load an IDL via `solana_idl_load`, then run `solana_idl_plan_instruction` and `solana_idl_simulate_instruction` for program <PROGRAM_ID> instruction <IX_NAME>."
- "(Mainnet demo, safe) Create a transaction, call `solana_send_transaction` with `confirm=false`, then show me how `solana_confirm_transaction` requires `confirm_token` on mainnet. Do not broadcast until I confirm." 

### EVM
- "Use `evm_list_rpc_defaults`, then on Base Sepolia (`chain_id=84532`) run `evm_get_balance` for 0x..."
- "(No broadcast) On Base Sepolia, run `evm_build_transfer_native` then `evm_preflight` and show me the resulting tx summary."
- "(Mainnet demo, safe) On Base mainnet (`chain_id=8453`), build+preflight a 0.000001 ETH transfer and show me the pending confirmation flow. Do not send until I confirm; then require `confirm_token` and use `evm_retry_pending_confirmation`."

## Docs

- **Server docs**: `web3mcp/README.md`
- **Research / design**: `docs/`
- **Final research pack**: `docs/final/` (note: Avalanche/BNB are treated as **EVM sample chains** in research)

## Contributing

See `CONTRIBUTING.md`.
