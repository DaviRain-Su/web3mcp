# Web3 AI Runtime (W3RT)

**W3RT** is the product direction: **one sentence → deterministic workflow → safe on-chain execution**.

This repo contains a Rust **MCP server** (`web3mcp/`) that implements the workflow engine + adapters.

## TL;DR (Solana-first default)

Default builds expose a **small, stable public API**:
- `w3rt_run_workflow_v0` — one entrypoint (analysis → simulate → approval → execute)
- `w3rt_get_run` — fetch run artifacts by `run_id`
- `w3rt_request_override` — power-user/agent override token for `approval_required`
- `solana_confirm_transaction` — explicit mainnet broadcast (requires `confirm_token`)

Everything else is **advanced/debug** and is only exposed when you build with:

```bash
cargo build --release --features expose-advanced-tools
```

Why: W3RT is meant to be used by humans and agents with *one sentence*, not by asking an LLM to pick from hundreds of low-level tools.

## What’s implemented today

### Solana mainnet workflow (current MVP)
- Natural language → intent schema (Solana swap)
- Jupiter v6 quote → build tx → simulate
- Approval summary + warnings (slippage/price impact)
- Safe execute: creates a **pending confirmation** (no broadcast)
- Explicit broadcast: `solana_confirm_transaction` (mainnet requires `confirm_token`)

### Advanced toolbox (optional)
If you build with `--features expose-advanced-tools`, the server exposes the full internal toolbox (Sui/EVM/Solana helpers, protocol APIs). This is useful for development/debugging, but not recommended as the default UX.

### Safety / ops
- **Audit log** ✅ (`WEB3MCP_AUDIT_LOG`, back-compat: `SUI_MCP_AUDIT_LOG`)
- **Mainnet safety** ✅ (pending confirmation + `confirm_token`)
- **Two-phase templates** ✅ (see `web3mcp/docs/acp-*` and examples)

### Integration contract (important)
Write-capable tools follow a consistent **status contract**:
- `sent`: broadcast completed
- `pending`: pending confirmation created (no broadcast)
- `needs_confirmation`: safety guard blocked the action (not a hard error). Follow `guard.next`.
- Hard failures are returned as `ErrorData` (treat as errors/retry).

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

### Human: one sentence → safe workflow (Solana mainnet)
- "Swap 0.01 SOL to USDC on Solana mainnet."

What should happen:
1) call `w3rt_run_workflow_v0` (simulate + approval + pending confirmation)
2) if approval is `ok`, you get `execute.next.confirm` → call `solana_confirm_transaction` with `confirm_token`

### Power user / Agent: inspect artifacts
- "Run `w3rt_run_workflow_v0` for 'swap 0.01 sol to usdc on solana mainnet' with sender=<PUBKEY>. Then call `w3rt_get_run` with the returned run_id and show me simulate/approval/execute JSON."

### Power user / Agent: override approval_required (explicit risk acceptance)
- "If execute is blocked with `approval_required`, call `w3rt_request_override` with the run_id and a reason, then re-run `w3rt_run_workflow_v0` with override_token."

### Advanced/debug mode only
If built with `--features expose-advanced-tools`, you can still use the internal chain/protocol tools directly for debugging.

Example (Solana native SOL transfer):
- "Send 0.01 SOL to <RECIPIENT_PUBKEY> on Solana mainnet"

Example (Solana SPL transfer by mint address; supports token-2022 mints too):
- "Send 10 9BB6NFEcjBCtnNLFko2FqVQBq8HHM13kCyYcdQbgpump to <RECIPIENT_PUBKEY> on Solana mainnet"

## Docs

- **Public API contract (recommended)**: `web3mcp/docs/w3rt-public-api.md`
- **Product vision**: `web3mcp/docs/product-vision.md`
- **Server docs**: `web3mcp/README.md`
- **Research / design**: `docs/`
- **Final research pack**: `docs/final/` (note: Avalanche/BNB are treated as **EVM sample chains** in research)

## Contributing

See `CONTRIBUTING.md`.
