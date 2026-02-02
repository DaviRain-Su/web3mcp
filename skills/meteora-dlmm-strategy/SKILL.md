---
name: meteora-dlmm-strategy
description: Strategy-layer workflow for Solana Meteora DLMM using web3mcp tools: rank pools, generate fillable templates, build pending-confirm transactions, and monitor/rebalance candidates. Use when implementing or operating an automated (but mainnet-safe) DLMM liquidity strategy, especially with rules like “top N by volume/fees”, frequent monitoring, and pending-confirm execution.
---

# Meteora DLMM Strategy (web3mcp)

Goal: keep **execution** safe (pending-confirm), while enabling frequent monitoring and parameter iteration.

## Assumptions

- You have `web3mcp` running with Solana tools enabled.
- For DLMM IDL tools, server must be built with:
  - `--features solana-extended-tools`

## Core tool chain

### 0) Discovery / ranking
- Use `solana_meteora_dlmm_rank_pairs`.
  - Strategy default: **Top 50 by volume/fee proxy**, then filter by risk tags.

### 1) Get a fillable template
- `solana_meteora_dlmm_plan` (IDL-based)
  - Returns required `args/accounts` names + `__FILL_ME__` templates.

### 2) Auto-fill what we can (heuristics)
- `solana_meteora_dlmm_fill_template`
  - Input: `pair_address`, `owner` (+ optional amounts)
  - Output: partially filled `args_template/accounts_template` + diagnostics of what was filled.

### 3) Build tx (no broadcast) + pending-confirm
- `solana_meteora_dlmm_build_tx`
  - Default: `create_pending=true`

### 4) Broadcast only via confirmation
- `solana_confirm_transaction`
  - Mainnet: requires `confirm_token`.

## Monitoring loop (recommended)

Run every **15 minutes** (or faster) but only act when thresholds are crossed.

Suggested loop:
1) Fetch ranked list (top 50).
2) Apply gates: tvl>=1m; ignore very_low_liquidity.
3) Triggers (mode B): fee/tvl >= 1% OR top10 volume.
4) If triggered, notify (v0: no auto pending tx). Optional: run local simulation script to estimate fee share for a hypothetical investment.

## Safety rules (default)

- Never auto-broadcast on mainnet.
- Always create pending confirmations.
- Only notify with a short summary + next command to confirm.

## Configuration knobs (start simple)

- `top_n`: 50
- `min_tvl_usd`: (choose a conservative floor)
- `rebalance_check_interval_min`: 15
- `max_pending_per_day`: (cap to avoid spam)

See references for suggested defaults and trigger rules.
