# W3RT Public API (Solana-first, minimal MCP surface)

This document defines the **public contract** of the Web3 AI Runtime (W3RT) exposed via the `web3mcp` MCP server.

Goal: **one sentence → deterministic workflow → safe execution**.

> Principle: the MCP surface should be **small and stable**. Most chain/protocol tools are internal.

## 0. Tool surface

### Default (recommended)
Only these tools are exposed:

1) `w3rt_run_workflow_v0`
- Single entrypoint.
- Writes stage artifacts to disk (run_id).
- Enforces safety guards.

2) `w3rt_get_run`
- Fetch artifacts by `run_id` (agent/power-user friendly).

3) `w3rt_request_override`
- Request a short-lived `override_token` to bypass `approval_required`.

4) `solana_confirm_transaction`
- Explicit final confirmation for broadcasting a pending tx.
- On mainnet requires `confirm_token`.

### Advanced (debug / power users)
Build with:

Notes (advanced mode):
- `transfer_native` supports SOL native transfer.
- `transfer_spl` supports mint addresses, known symbols (via Jupiter token list), and token-2022 mints (program-aware ATA + TransferChecked).

```bash
cargo build --release --features expose-advanced-tools
```

This exposes the full internal toolbox (read tools, Solana helpers, EVM/Sui, protocol APIs). Advanced mode is not the default, because it increases LLM tool-selection risk.

## 1. Workflow entrypoint

### 1.1 `w3rt_run_workflow_v0`

**Intent input** (either):
- `intent_text`: natural language (recommended for humans)
- `intent`: validated intent object (recommended for agent frameworks)

Request fields (current):
- `intent_text?: string`
- `intent?: object`
- `sender?: string` (Solana pubkey)
- `network?: string` (mainnet|devnet|testnet)
- `label?: string`

Response:
- `status: "ok"`
- `run_id: string`
- `runs_dir: string`
- `artifacts: { analysis, simulate, approval, execute }`

## 2. Stage artifacts (stable contract)

Artifacts are JSON written to `runs_dir/<run_id>/...`.

### 2.1 `analysis`
- Captures the resolved intent.

### 2.2 `simulate`
For Solana swap (Jupiter v6):
- `status: ok|failed`
- `simulation_performed: true`
- `adapter: jupiter_v6`
- `quote`: Jupiter quote response
- `swap.tx_base64`: unsigned/signed versioned tx (base64)
- `simulation.logs/err/units_consumed`

### 2.3 `approval`
- `status: ok|needs_review|todo`
- `warnings`: array of warning objects (price impact, slippage, etc.)

### 2.4 `execute`
Possible statuses:
- `blocked` with `guard`
  - `no_sim_no_send`
  - `approval_required` (use `w3rt_request_override` to obtain `override_token`)
- `pending_confirmation_created`
  - includes `result` and `next.confirm` template

## 3. Mainnet safety: pending confirmation + confirm_token

On mainnet, broadcasts are never done in one step.

Flow:
1) `w3rt_run_workflow_v0` → creates pending confirmation
2) user explicitly calls `solana_confirm_transaction` with `confirm_token`

## 4. Copy/paste examples

### 4.1 Human (one sentence)
- "Swap 0.01 SOL to USDC on Solana mainnet"

### 4.2 Agent (structured)
Provide an `intent` object with:
- `chain=solana`
- `action=swap_exact_in`
- `user_pubkey`
- `input_token/output_token`
- `amount_in` (UI string)

## 5. Roadmap: public API evolution

Short-term (Solana-first):
- Keep minimal surface.
- Stabilize artifact schemas.
- Add explicit override mechanism for `approval_required` (token-based).

Mid-term (power users + agent frameworks):
- Add `w3rt_get_run` (read artifacts by run_id)
- Add `w3rt_confirm` (chain-agnostic confirm wrapper)
- Add `w3rt_plan` / `w3rt_simulate` / `w3rt_execute` split (optional)

Long-term (multi-chain):
- EVM and Sui become adapters behind the same artifact contract.
