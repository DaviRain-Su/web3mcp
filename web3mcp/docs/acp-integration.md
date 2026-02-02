# ACP Integration (Virtuals Protocol Agent Commerce Protocol)

This repository (`web3mcp`) is a **multi-chain MCP server** (Sui + EVM + Solana today, more later). When users interact via **Claude Desktop**, complex operations (especially **arbitrary Solana IDL interactions**) can be unreliable if you try to go from *natural language → fully correct args/accounts → broadcast* in one shot.

For **AI-agent users**, a better pattern is to execute transactions through **ACP (Agent Commerce Protocol)** using a dedicated *executor agent*.

This doc describes a recommended integration:

- Claude Desktop / “main” agent: understands the human request and creates an ACP Job.
- ACP executor agent: performs **two-phase execution** against this MCP server:
  1) `plan` / validate / determine missing fields
  2) `simulate` → `send_pending` → `confirm`

## Why ACP for "arbitrary IDL" use cases

Arbitrary Solana IDL interactions often fail in LLM tool mode due to:

- missing accounts, wrong signer/mut flags
- nested/option/enum types and numeric encoding mistakes (float vs integer)
- needing deterministic account derivations (ATA/PDA)

ACP lets you:

- run a dedicated executor agent with a **strict JSON protocol**
- iterate (plan → request missing fields → simulate) instead of guessing once
- separate “human-facing intent” from “deterministic execution”

## Components

### 1) This MCP server (web3mcp)

- Runs locally (stdio) or behind a bridge.
- Exposes tools for Sui/EVM/Solana.
- Solana has a minimal default toolset plus an optional feature flag:

`solana-extended-tools` enables additional Solana tools including IDL helpers.

> Recommendation: enable `solana-extended-tools` **only** in the ACP executor environment.

### 2) ACP skill pack (OpenClaw)

Repository:
- <https://github.com/Virtual-Protocol/openclaw-acp>

It provides tools:
- `browse_agents`
- `execute_acp_job`
- `get_wallet_balance`

## Recommended ACP Job protocol (MVP)

Use a single **explicit** payload shape so the executor agent can be deterministic.

### Envelope

```json
{
  "kind": "solana_idl_2phase",
  "network": "mainnet",
  "mode": "plan",
  "action": { /* solana-specific */ },
  "safety": {
    "require_simulate_ok": true,
    "send": false,
    "confirm": false
  }
}
```

- `kind`: fixed `solana_idl_2phase`
- `mode`: `plan | simulate | send | confirm`
- `safety.send`: default `false`
- `safety.confirm`: default `false` (prefer pending-confirm UX)

### Solana arbitrary IDL action

```json
{
  "type": "idl_instruction",
  "program_id": "<base58>",
  "idl": { "source": "registry", "name": "<string>" },
  "instruction": "<ix_name>",
  "args": { "amount_in": "1000000" },
  "accounts": { "user": "<base58>" }
}
```

**Rules (important):**
- all integer amounts (`u64/u128`) must be **strings** (never floats)
- never guess unknown accounts: return them as missing

### Expected executor result shape

```json
{
  "ok": true,
  "stage": "plan",
  "network": "mainnet",
  "result": { /* stage-specific */ },
  "missing": { "args": [], "accounts": [] },
  "warnings": [],
  "next": { "mode": "simulate" }
}
```

## Tool mapping to web3mcp

The executor agent should call **only a small set of tools** and enforce the workflow:

1) `plan`
   - use Solana IDL plan tool (requires `solana-extended-tools`)
   - return missing args/accounts

2) `simulate`
   - build tx + simulate (IDL helper tool)
   - parse logs, return actionable error summaries

3) `send`
   - send using pending-confirm defaults

4) `confirm`
   - confirm broadcast of pending tx

For RPC reads and lightweight queries, use:
- `solana_rpc_call` (raw JSON-RPC)

## Executor agent prompt (suggested requirements)

**Hard requirements:**
- strictly JSON in/out
- never broadcast on `plan` or `simulate`
- do not proceed to `send` unless `simulate` succeeded (unless explicitly overridden)
- do not fabricate addresses; request missing fields

## Example: plan → simulate → send_pending → confirm

1) `plan` job returns missing fields
2) caller supplies missing fields
3) executor simulates
4) executor sends pending tx and returns `pending_confirmation_id`
5) caller sends confirm job referencing `pending_confirmation_id`

---

## Next: full integration example repo

See:
- `examples/acp/README.md`
- `examples/acp/payloads/` (sample job payloads)
- `docs/acp-executor-prompt.md` (Solana executor prompt)
- `docs/acp-executor-prompt.sui_move_2phase.md` (Sui executor prompt)
- `docs/acp-executor-prompt.evm_call_2phase.md` (EVM executor prompt)
