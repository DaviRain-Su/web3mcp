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

## Example prompts

- Sui: “Get the SUI balance of 0x… on testnet.”
- Solana: “Call the <program> IDL instruction <ix_name> with args … (simulate first).”
- EVM: “On Base Sepolia (chain_id 84532), get the ETH balance of 0x….”

## Docs

- **Server docs**: `web3mcp/README.md`
- **Research / design**: `docs/`
- **Final research pack**: `docs/final/` (note: Avalanche/BNB are treated as **EVM sample chains** in research)

## Contributing

See `CONTRIBUTING.md`.
