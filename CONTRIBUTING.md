# Contributing to Web3 Anywhere / web3mcp

Thanks for helping.

## Repo layout

- `web3mcp/` — **current** Rust multi-chain MCP server (binary: `web3mcp`)
- `docs/` — research, design notes
- `archive/` — historical/archived projects

## Dev setup

Requirements:
- Rust toolchain (stable)

Common commands:
```bash
cd web3mcp
cargo fmt
cargo test
cargo clippy --tests -- -D warnings
```

## Adding a new tool

Guidelines:
- Prefer **read-only** tools by default; write/tx tools should be **2-phase** (plan/simulate -> confirm -> send) when possible.
- Validate inputs aggressively and return `ErrorData` with:
  - `-32602` for invalid params
  - `-32603` for internal errors
- Keep outputs **machine-friendly JSON** (use `pretty_json` helpers).
- Add/update docs in `web3mcp/README.md` if user-facing.

## Adding a new EVM chain

- Configure an RPC URL via env var: `EVM_RPC_URL_<chain_id>`
- Optionally set `EVM_DEFAULT_CHAIN_ID`
- If you add a new built-in default in code, also update:
  - `evm_list_rpc_defaults` tool (system/chain)
  - documentation

## PR checklist

- [ ] `cargo fmt`
- [ ] `cargo test`
- [ ] `cargo clippy --tests -- -D warnings`
- [ ] Docs updated if behavior/config changed
