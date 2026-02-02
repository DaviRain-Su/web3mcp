# ACP Main Agent Template (Claude Desktop / Human-facing)

This is a template prompt / playbook for the **human-facing** agent (e.g. Claude Desktop) that will create ACP Jobs for an **executor agent**.

Goal: convert natural language requests into strict ACP payloads, then iterate:

- `plan` → request missing fields → `simulate` → `send` (pending by default) → `confirm`

## High-level rules

1) Never try to broadcast directly from the main agent.
2) Always start with `mode=plan`.
3) If the executor returns `missing.args` / `missing.accounts`, ask the user (or derive if deterministic) and re-run `plan`.
4) Only proceed to `simulate` once missing lists are empty.
5) Only proceed to `send` after a successful `simulate`.
6) Default to `confirm=false` and require explicit user confirmation to broadcast.

## Constructing jobs

Use `execute_acp_job` with a payload that matches one of:

- `solana_idl_2phase`
- `sui_move_2phase`
- `evm_call_2phase`

### Solana (arbitrary IDL)

Start with:

```json
{
  "kind": "solana_idl_2phase",
  "network": "mainnet",
  "mode": "plan",
  "action": {
    "type": "idl_instruction",
    "program_id": "...",
    "idl": { "source": "registry", "name": "..." },
    "instruction": "...",
    "args": {},
    "accounts": {}
  },
  "safety": { "require_simulate_ok": true, "send": false, "confirm": false }
}
```

**Main-agent responsibilities:**
- Ensure u64/u128 amounts are strings.
- Do NOT invent missing accounts; let executor return missing lists.

### EVM

```json
{
  "kind": "evm_call_2phase",
  "chain_id": 8453,
  "mode": "plan",
  "action": {
    "type": "contract_call",
    "to": "0x...",
    "from": "0x...",
    "abi": "...",
    "method": "...",
    "args": []
  },
  "safety": { "require_simulate_ok": true, "send": false, "confirm": false }
}
```

### Sui

```json
{
  "kind": "sui_move_2phase",
  "network": "mainnet",
  "mode": "plan",
  "action": {
    "type": "move_call",
    "package_id": "0x...",
    "module": "...",
    "function": "...",
    "type_args": [],
    "args": []
  },
  "safety": { "require_simulate_ok": true, "send": false, "confirm": false }
}
```

## Handling missing fields

When executor returns:

```json
{"missing": {"args": ["min_out"], "accounts": ["token_program"]}}
```

Main agent should:

- Ask the user for the missing fields if they are user-specific.
- Fill deterministic defaults ONLY when universally safe (e.g. known program ids), otherwise ask.

## Confirmation UX

When executor returns a pending id (example):

```json
{"result": {"pending_confirmation_id": "abc123"}}
```

Main agent must ask the user:

- "Confirm broadcast?" and summarize:
  - chain/network
  - target program/contract
  - amounts + destination

Then send a `mode=confirm` job referencing that id.
