---
name: w3rt-usdc-hackathon
description: Hackathon-ready OpenClaw skill wrapper for the web3mcp W3RT server. Provides a Solana-first USDC demo on devnet/testnet with safe two-phase execution (pending confirmation + explicit confirm).
---

# W3RT USDC Hackathon (OpenClaw Skill)

This skill exists to make the hackathon submission easy to reproduce: **install → run server → copy/paste demo prompts**.

## What you get

- A simple launcher script to build/run `web3mcp`
- A copy/paste demo flow (quote → swap → transfer → confirm)
- Safety defaults: **no mainnet** for demo

## Setup

### 0) Prereqs

- Rust toolchain
- Solana keypair file

### 1) Environment

```bash
export SOLANA_KEYPAIR_PATH="$HOME/.config/solana/id.json"
```

### 2) Start the server

From repo root:

```bash
bash skills/w3rt-usdc-hackathon/start-web3mcp.sh
```

## Demo prompts

Use these in your OpenClaw/MCP client:

- Quote (ExactIn): "quote 0.1 sol to usdc on solana devnet"
- Quote (ExactOut): "quote sol to get 10 usdc on solana devnet"
- Swap (ExactOut): "swap sol to get 10 usdc on solana devnet"
- Transfer: "send 1 usdc to <RECIPIENT_PUBKEY> on solana devnet"

Then confirm using `solana_confirm_transaction` template returned by execute stage.

## Safety

- Hackathon is demo/testnet only.
- Do **not** use mainnet or real funds.
- Never paste sensitive credentials into chat.
