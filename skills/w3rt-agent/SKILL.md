---
name: w3rt-agent
description: OpenClaw skill for turning fuzzy Chinese/English DeFi intents into strict W3RT workflow calls (Solana-first), with safe simulate→policy→pending→confirm flow.
---

# W3RT Agent (OpenClaw Skill)

Use this skill when the user gives **fuzzy natural language** requests (CN/EN) like:
- “把 0.01 SOL 换成 USDC”
- “查一下我主网 SOL 余额”
- “帮我存到 lend 里赚收益”（future adapters)

Goal: **you (the agent) do the thinking**; W3RT tools do deterministic execution.

## Core principle

- **User speaks naturally** → you produce a **strict intent object**.
- Never let the model “trial-and-error parameters” against chain.
- Always follow: **plan → simulate → policy/preview → pending confirmation → explicit confirm**.

## Minimal stable tool surface (W3RT)

Use these MCP tools (names depend on your MCP client prefixing):
- `w3rt_run_workflow_v0`
- `w3rt_get_run`
- `w3rt_request_override` (only for `approval_required`)
- `solana_confirm_transaction` (mainnet requires confirm_token)

## Quick start (copy/paste prompt)

When the user sends a fuzzy request, respond by producing **exactly one** strict intent object and a single W3RT call.

Use this system-ish instruction (copy/paste into your own thinking / scratchpad):

> You are a W3RT intent compiler. Output ONLY valid JSON (no markdown). Must be an object with keys: label, network, sender, intent. intent must be an object (NOT a string). Fill missing fields by asking exactly 1 clarification question if required. Default network=mainnet. For Solana swap ExactIn, use action=swap_exact_in and amount_in. For ExactOut, use action=swap_exact_out and amount_out. Always include chain=solana, resolved_network.family=solana, resolved_network.network_name. Always include user_pubkey.

Example output:
```json
{
  "label": "Swap 0.005 SOL -> USDC (10bps)",
  "network": "mainnet",
  "sender": "<pubkey>",
  "intent": {
    "chain": "solana",
    "action": "swap_exact_in",
    "user_pubkey": "<pubkey>",
    "input_token": "SOL",
    "output_token": "USDC",
    "amount_in": "0.005",
    "slippage_bps": 10,
    "resolved_network": {"family": "solana", "network_name": "mainnet"}
  }
}
```

Then call `w3rt_run_workflow_v0` with that JSON.

## Step-by-step workflow

### 1) Normalize the user request into a strict intent

Always build an **object**, never a JSON string.

#### A. Swap (ExactIn)
```json
{
  "chain": "solana",
  "action": "swap_exact_in",
  "user_pubkey": "<sender_pubkey>",
  "input_token": "SOL",
  "output_token": "USDC",
  "amount_in": "0.005",
  "slippage_bps": 10,
  "resolved_network": {"family": "solana", "network_name": "mainnet"}
}
```

#### B. Swap (ExactOut)
```json
{
  "chain": "solana",
  "action": "swap_exact_out",
  "user_pubkey": "<sender_pubkey>",
  "input_token": "SOL",
  "output_token": "USDC",
  "amount_out": "1.0",
  "slippage_bps": 50,
  "resolved_network": {"family": "solana", "network_name": "mainnet"}
}
```

#### C. Balance / portfolio
Prefer explicit actions:
```json
{
  "chain": "solana",
  "action": "get_portfolio",
  "owner": "<sender_pubkey>",
  "resolved_network": {"family": "solana", "network_name": "mainnet"}
}
```

### 2) Call `w3rt_run_workflow_v0`

Pass BOTH:
- `intent` (object)
- `sender` and `network` (so server can backfill if needed)

Example request:
```json
{
  "label": "Swap 0.005 SOL -> USDC (10bps)",
  "network": "mainnet",
  "sender": "<sender_pubkey>",
  "intent": {"chain":"solana","action":"swap_exact_in", ... }
}
```

### 3) Fetch artifacts with `w3rt_get_run`

- Read `analysis`, `simulate`, `approval`, `execute`.
- If `execute.status == blocked`:
  - `guard_class == no_sim_no_send` → simulation didn’t run/failed. Inspect `simulate`.
  - `guard_class == approval_required` → request override via `w3rt_request_override`.

### 4) Safety checks before broadcast

If `simulate` produced `swap.tx_base64`:
- Run `solana_tx_analyze` (advanced) or `tx_preview` action (workflow) to get:
  - programs_used
  - transfers/authorities/ATA creates
- Apply policy (warn/block) per `policies/solana_confirm_policy.json`.

### 5) Mainnet confirmation

Never broadcast automatically.
- Use `solana_confirm_transaction` with:
  - `id`
  - `hash`
  - `confirm_token` (required on mainnet)

## Troubleshooting: “Tool execution failed” in Claude Desktop

If you see errors like JSON parse failures, it’s usually because **stdio stdout was polluted**.
- In stdio MCP mode, **stdout must be only MCP JSON**.
- Ensure server logs go to stderr and ANSI is disabled.

If you’re developing web3mcp locally:
- Fix: configure tracing to log to `stderr` and `with_ansi(false)`.

Also:
- Restart Claude Desktop after rebuilding.
- Kill stale server processes.

## Guardrails

- For mainnet money ops: require explicit user confirmation before calling `solana_confirm_transaction`.
- Keep amounts small for first-time testing.
- If policy mode is `warn`, still surface `policy_warnings` to user.
