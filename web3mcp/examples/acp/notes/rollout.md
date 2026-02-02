# Rollout / Deployment notes (ACP + web3mcp)

This is a practical checklist for rolling out the ACP executor pattern with `web3mcp`.

## Goal

- Claude Desktop / main agent: safe, minimal tool surface.
- ACP executor agent: extended capabilities, deterministic 2-phase execution.

## Step 1 — Build two binaries

### A) Desktop build (minimal)

```bash
cargo build --release
```

Use this binary for:
- Claude Desktop
- any human-facing agent session

### B) Executor build (extended tools)

```bash
cargo build --release --features solana-extended-tools
```

Use this binary only for:
- ACP executor agent

## Step 2 — Configure MCP server separation

- Do not point Claude Desktop at the executor build.
- Prefer separate host/container for executor build.

Recommended separation:

- Desktop: local machine, stdio MCP
- Executor: server/container VM, stdio or HTTP bridge MCP

## Step 3 — Configure credentials

### ACP (Virtuals)

Executor environment only:

- `AGENT_WALLET_ADDRESS`
- `SESSION_ENTITY_KEY_ID`
- `WALLET_PRIVATE_KEY`

### Chain keys

Executor environment only:

- Solana keypair path / key material
- EVM private key(s)
- Sui keystore / mnemonic

Main agent must have none of the above.

## Step 4 — Adopt the protocol

Executor must accept only these kinds:

- `solana_idl_2phase`
- `sui_move_2phase`
- `evm_call_2phase`

and enforce:

- `plan` → `simulate` → `send (pending)` → `confirm`

## Step 5 — Smoke tests

### Solana

1) Send `solana_idl_2phase` `mode=plan` payload
2) Ensure you get structured `missing` lists
3) Fill missing and run `mode=simulate`
4) Ensure `simulate` logs are returned and error is classified
5) Run `mode=send` and confirm you receive `pending_confirmation_id`
6) Run `mode=confirm` and confirm signature / explorer link

### Sui / EVM

Repeat with `sui_move_2phase` and `evm_call_2phase` payloads.

## Step 6 — UX defaults

- Pending-confirm by default (`confirm=false`)
- Main agent always asks user for explicit confirmation before broadcasting

## Step 7 — Monitoring

- Redact secrets from logs
- Store pending confirmations in a controlled directory
- Alert on repeated failures (simulate errors, missing fields loops)
