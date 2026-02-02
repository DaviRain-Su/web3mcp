# Prompt injection notes (ACP executor)

This note focuses on **prompt injection / instruction hijacking** risks when running an ACP executor agent that can submit on-chain transactions.

## Threat model

- The executor receives job payloads that may contain:
  - malicious text in fields (e.g. `instruction`, `idl.name`, ABI strings)
  - attempts to override rules ("ignore previous instructions")
  - attempts to get the agent to reveal secrets

The executor must treat all payload content as **untrusted input**.

## Hard mitigations (recommended)

### 1) Strict kind allowlist

Executor must accept only explicit kinds:

- `solana_idl_2phase`
- `sui_move_2phase`
- `evm_call_2phase`

Reject any other kind with structured JSON error.

### 2) Strict JSON-only I/O

- Input must be valid JSON.
- Output must be valid JSON.
- Do not include prose, markdown, or hidden context.

This reduces the chance that a prompt injection string becomes part of an instruction chain.

### 3) Field validation + length limits

- Validate addresses (base58 pubkeys for Solana; 0x addresses for EVM/Sui).
- Enforce max length for:
  - ABI JSON blobs
  - IDL JSON blobs
  - free-text fields

If too large, return a `missing` / `error` response and request a reference (e.g. IDL registry name) rather than inline blobs.

### 4) No secret egress

Executor must never:

- print env vars
- read key files and return their contents
- return private keys / seed phrases

Allowed outputs are limited to:

- tx digests / signatures
- pending confirmation ids
- simulation logs (redacted)
- missing-field lists

### 5) Two-phase workflow enforcement

If a payload tries to force broadcast directly:

- still require `plan` and `simulate` unless an explicit, audited override is present
- default to pending-confirm (`confirm=false`)

### 6) Deterministic tool usage

Executor should prefer deterministic tools:

- `solana_rpc_call` for reads
- IDL plan/build/simulate tools for Solana IDL execution

Avoid "creative" inference steps.

## Response pattern for rejection

When rejecting, use a consistent JSON error shape:

```json
{
  "ok": false,
  "stage": "plan",
  "result": {
    "error_class": "Rejected",
    "message": "unsupported kind"
  },
  "missing": { "args": [], "accounts": [] },
  "warnings": [],
  "next": { "mode": null }
}
```

## Operational mitigations

- Run executor in an isolated environment (container/VM)
- Restrict filesystem access
- Restrict network egress if possible
- Rate limit job submissions
- Monitor and alert on repeated failures or unusual destinations

See also:
- `examples/acp/notes/security.md`
- `examples/acp/notes/rollout.md`
