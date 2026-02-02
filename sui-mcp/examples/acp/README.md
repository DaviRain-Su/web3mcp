# ACP Integration Example (sui-mcp + openclaw-acp)

This folder is a **documentation-only example** showing how to structure an integration where:

- Your *main agent* (human-facing) creates ACP jobs.
- A dedicated *executor agent* executes a strict 2-phase workflow against `sui-mcp`.

This is intended as a starting point for a separate “integration repo” later.

## Architecture

```
Human → Claude Desktop/Main Agent
   → (execute_acp_job)
      → ACP Executor Agent
         → sui-mcp (MCP tools)
         → Solana/Sui/EVM RPCs
```

## Requirements

1) You have `sui-mcp` built and runnable.
2) You have OpenClaw configured with the `virtuals-protocol-acp` skill:
   - <https://github.com/Virtual-Protocol/openclaw-acp>

## Important: enable Solana extended tools only in executor environment

For arbitrary Solana IDL flows, the executor must run `sui-mcp` with:

- Cargo feature: `solana-extended-tools`

Example build:

```bash
cargo build --release --features solana-extended-tools
```

Then point the executor agent’s MCP server config at that binary.

> Keep your Claude Desktop config pointing at the default build (minimal tool list).

## Suggested ACP Job payload (MVP)

Envelope:

```json
{
  "kind": "tx_2phase",
  "chain": "solana",
  "network": "mainnet",
  "mode": "plan",
  "action": { /* chain-specific */ },
  "safety": {
    "require_simulate_ok": true,
    "send": false,
    "confirm": false
  }
}
```

Solana arbitrary IDL action:

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

## Executor agent system prompt (skeleton)

Copy/paste and adapt:

- Only accept JSON jobs.
- On `mode=plan`: determine missing args/accounts; do not broadcast.
- On `mode=simulate`: build and simulate; return structured error summaries.
- On `mode=send`: only if simulate ok; create pending tx by default.
- On `mode=confirm`: broadcast pending tx.
- Never invent addresses. Always return missing fields.
- All u64/u128 amounts must be strings.

See `docs/acp-integration.md` for more detail.
