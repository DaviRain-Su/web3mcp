# OpenClaw USDC Hackathon (Moltbook) — W3RT Submission

This repo contains **W3RT (Web3 AI Runtime)**: *one sentence → deterministic workflow → safe on-chain execution*.

This hackathon submission focuses on a **Solana-first USDC demo** (devnet/testnet) with two-phase safety:

1) `w3rt_run_workflow_v0` creates a **pending confirmation** (no broadcast)
2) `solana_confirm_transaction` explicitly broadcasts (mainnet requires `confirm_token`)

> ⚠️ Hackathon / demo only: use **devnet/testnet**, do **not** use mainnet, real funds, or sensitive credentials.

---

## Recommended track

- **Best OpenClaw Skill** (primary)
- **Agentic Commerce** (secondary framing: USDC as settlement unit)

---

## Quickstart (devnet)

### 0) Build + run the MCP server

```bash
cd web3mcp
cargo build --release

# Run the server (example)
./target/release/web3mcp
```

### 1) Environment

Required (Solana signing for transfer/swap workflows):

```bash
export SOLANA_KEYPAIR_PATH="$HOME/.config/solana/id.json"
```

Optional:
- `SOLANA_RPC_URL` / network selection depends on your setup; W3RT uses `network=devnet|testnet|mainnet` in the workflow request.
- `SOLANA_JUPITER_QUOTE_BASE_URL` (default: https://quote-api.jup.ag)
- `SOLANA_JUPITER_TOKENS_URL` (default: https://tokens.jup.ag/tokens?tags=verified)

> You must have devnet SOL for fees. For USDC on devnet, use a devnet USDC mint and acquire test tokens as needed.

---

## Demo script (copy/paste prompts)

### A) Read-only quote (no tx)

- **ExactIn quote**:
  - "quote 0.1 sol to usdc on solana devnet"

- **ExactOut quote**:
  - "quote sol to get 10 usdc on solana devnet"

Expected fields:
- `simulate.adapter = solana_quote`
- `simulate.quote_adapter = jupiter_v6`
- `simulate.about_quote`
- `simulate.quote_summary.{in_amount_ui,out_amount_ui,price_impact_pct}`

### B) Swap (safe default: pending confirmation)

- **ExactOut swap** (recommended demo):
  - "swap sol to get 10 usdc on solana devnet"

Expected:
- `execute.status = pending_confirmation_created`
- `execute.result.next.confirm.tool = solana_confirm_transaction`

### C) USDC transfer (safe default: pending confirmation)

- "send 1 usdc to <RECIPIENT_PUBKEY> on solana devnet"

Expected:
- `approval.summary.will_create_ata` shows whether recipient ATA will be created
- `execute.status = pending_confirmation_created`

### D) Confirm (explicit broadcast)

Call `solana_confirm_transaction` using the `next.confirm` template from the execute stage.

Expected:
- `about_to_broadcast` string in confirm output
- `summary` echoed in confirm output

---

## Moltbook submission template

Title:
- **W3RT: Solana-first USDC agent runtime with safe two-phase execution**

Body (suggested):
- What it does: natural language → workflow → simulate/approve → pending confirmation → explicit confirm.
- Why USDC: stable unit of account for agent commerce.
- What to try (copy/paste):
  1) quote 0.1 sol to usdc on solana devnet
  2) swap sol to get 10 usdc on solana devnet
  3) send 1 usdc to <RECIPIENT_PUBKEY> on solana devnet
- Safety: devnet/testnet only; never broadcast on mainnet without explicit confirmation.

---

## Notes on multi-chain

W3RT is architected to support multiple chains (Solana/Sui/EVM adapters exist), but this hackathon submission focuses on **Solana** where the end-to-end USDC workflow is most complete.
