# Main Agent (Claude Desktop) — ACP Job Playbook

This doc is for the **human-facing main agent** (e.g. Claude Desktop). Your job is to:

1) understand the user's intent
2) create ACP Jobs for an executor agent
3) present results and ask for explicit confirmation before broadcast

You do **not** directly broadcast transactions.

## Tools you will use (from openclaw-acp skill)

- `browse_agents` — find an executor agent
- `execute_acp_job` — send a structured job payload to the executor agent

## Executor agent expectation

The executor agent must:

- accept jobs with kinds:
  - `solana_idl_2phase`
  - `sui_move_2phase`
  - `evm_call_2phase`
- output **strict JSON only**
- follow: `plan → simulate → send (pending) → confirm`

## Workflow (always)

### Step 0 — Choose executor

Use `browse_agents` with a query like:

- "solana idl executor"
- "sui move executor"
- "evm contract executor"

Pick the agent that is intended to execute against your `web3mcp` MCP server.

### Step 1 — PLAN

Always start with `mode=plan`.

#### Solana arbitrary IDL (plan)

Use `execute_acp_job` with payload:

```json
{
  "kind": "solana_idl_2phase",
  "network": "mainnet",
  "mode": "plan",
  "action": {
    "type": "idl_instruction",
    "program_id": "<PROGRAM_ID_BASE58>",
    "idl": { "source": "registry", "name": "<IDL_NAME>" },
    "instruction": "<INSTRUCTION_NAME>",
    "args": {},
    "accounts": {}
  },
  "safety": { "require_simulate_ok": true, "send": false, "confirm": false }
}
```

**Rules:**
- All u64/u128 amounts must be strings.
- Do not invent missing accounts.

### Step 2 — Handle missing fields

If executor returns:

```json
{
  "ok": false,
  "stage": "plan",
  "missing": { "args": ["min_out"], "accounts": ["user"] }
}
```

You must:

- ask the user for missing user-specific values (e.g. `user` address)
- or provide deterministic defaults only when universally safe (e.g. known Token program id)

Then re-run `mode=plan` with filled fields.

### Step 3 — SIMULATE

When `missing` is empty, run `mode=simulate`.

```json
{
  "kind": "solana_idl_2phase",
  "network": "mainnet",
  "mode": "simulate",
  "action": {
    "type": "idl_instruction",
    "program_id": "<PROGRAM_ID_BASE58>",
    "idl": { "source": "registry", "name": "<IDL_NAME>" },
    "instruction": "<INSTRUCTION_NAME>",
    "args": { "amount_in": "1000000", "min_out": "990000" },
    "accounts": { "user": "<USER_BASE58>" }
  },
  "safety": { "require_simulate_ok": true, "send": false, "confirm": false }
}
```

If simulation fails, present the executor’s `result.suggest_fix` and ask the user for missing/corrected fields; then go back to plan/simulate.

### Step 4 — SEND (pending by default)

Only after a successful simulation:

```json
{
  "kind": "solana_idl_2phase",
  "network": "mainnet",
  "mode": "send",
  "action": {
    "type": "idl_instruction",
    "program_id": "<PROGRAM_ID_BASE58>",
    "idl": { "source": "registry", "name": "<IDL_NAME>" },
    "instruction": "<INSTRUCTION_NAME>",
    "args": { "amount_in": "1000000", "min_out": "990000" },
    "accounts": { "user": "<USER_BASE58>" }
  },
  "safety": { "require_simulate_ok": true, "send": true, "confirm": false }
}
```

Executor should return `pending_confirmation_id`.

### Step 5 — Ask user to CONFIRM

Before broadcasting, summarize:

- chain/network
- program/contract
- amounts
- destination
- any warnings

Then send `mode=confirm`:

```json
{
  "kind": "solana_idl_2phase",
  "network": "mainnet",
  "mode": "confirm",
  "action": {
    "type": "pending_confirmation",
    "pending_confirmation_id": "<PENDING_CONFIRMATION_ID>"
  },
  "safety": { "confirm": true }
}
```

## Quick links

- `docs/acp-integration.md`
- `docs/acp-main-agent-template.md`
- `docs/acp-executor-prompt.md` (Solana)
- `examples/acp/payloads/`
