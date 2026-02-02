# Security notes (ACP + sui-mcp)

This document summarizes practical security guidance for running an ACP executor agent that can submit on-chain transactions via `sui-mcp`.

## Principle: split roles

- **Main agent (Claude Desktop / human-facing)**
  - interprets human intent
  - creates ACP jobs
  - **must not** hold signing keys
  - **must not** have access to executor-only MCP servers

- **Executor agent (ACP)**
  - holds the ability to sign / submit transactions
  - runs a strict 2-phase workflow
  - should be isolated (env, filesystem, permissions)

## Key material rules (hard)

1) Never store private keys in the main agent environment.
2) Never expose signing secrets in tool outputs.
3) Only the executor environment may have:
   - EVM private keys
   - Solana keypair file paths
   - Sui keystore / mnemonic material
   - ACP whitelisted wallet private key (Virtuals ACP)

## ACP (Virtuals) credentials

From the `openclaw-acp` skill, the executor-side env typically includes:

- `AGENT_WALLET_ADDRESS`
- `SESSION_ENTITY_KEY_ID`
- `WALLET_PRIVATE_KEY`

**Never** place these in Claude Desktop config or any user-facing agent.

## MCP server isolation

Recommended:

- Run **two builds** of `sui-mcp`:
  1) **Desktop build (minimal tools)**
     - no Solana IDL tools, fewer dangerous helpers
     - safe for day-to-day use
  2) **Executor build (extended tools enabled)**
     - `--features solana-extended-tools`
     - connected only to the executor agent

This reduces attack surface and accidental misuse.

## Transaction safety defaults

Executor agent should enforce:

- Always start at `mode=plan`
- Require `simulate` success before `send`
- Default `confirm=false` (pending-confirm)
- Require explicit user confirmation (through the main agent) for broadcast

## Logging

- Avoid logging raw secrets (private keys, keypair JSON, seed phrases)
- If you log payloads, redact:
  - `WALLET_PRIVATE_KEY`
  - any `private_key`, `seed`, `mnemonic`, `keystore`

## Common failure/attack patterns

- Prompt injection through "job payload" fields
  - Mitigation: executor only accepts strict JSON and strict `kind` values

- Tool exfiltration (LLM tries to print secrets)
  - Mitigation: executor never returns secrets; only returns tx ids, digests, pending ids

- Human-facing agent accidentally gets executor MCP access
  - Mitigation: separate configs and hosts; do not reuse the same OpenClaw session

## Checklist

- [ ] Desktop agent has **no** private keys and no executor-only MCP servers configured
- [ ] Executor agent runs in isolated environment
- [ ] Executor uses strict 2-phase protocol
- [ ] Pending-confirm is default
- [ ] Logs are redacted
