# W3RT MVP Milestones (Executable)

This doc turns `product-vision.md` into a **ship plan** with **testable acceptance criteria**.

## Target users (must be supported from v0)

1) **Strategy buyers (end users)**
- Input: natural language + minimal parameters (amount, token, risk)
- Output: safe flow with simulation + explicit approval; no accidental mainnet send

2) **Strategy publishers (developers)**
- Can author/version a strategy/workflow package
- Clear schemas, testability, deterministic replay, trace artifacts

3) **Eagents (other agents/platforms)**
- Machine-readable contract: structured inputs/outputs, idempotency, guard/next-step guidance

---

## MVP v0: One end-to-end DeFi flow (Solana swap)

### M0 — Docs + contracts
**Goal:** make the product shape unambiguous.

Acceptance:
- `docs/product-vision.md` exists (✅)
- This file defines milestones + acceptance
- Define one canonical flow name: `swap_exact_in`

### M1 — Intent schema v0 (Solana swap)
**Goal:** AI produces *intent*, Rust produces deterministic tx.

Acceptance:
- Given a natural language request, the agent can output a JSON intent with fields:
  - `chain`, `action`, `input_token`, `output_token`, `amount_in`, `slippage_bps`, `user_pubkey` (or reference)
- Intent is validated (missing/invalid fields return a structured error)

### M2 — Deterministic workflow v0 (analysis → simulate → approval → execute)
**Goal:** a repeatable, auditable pipeline.

Acceptance:
- A workflow run has a `run_id`
- Each stage emits a JSON artifact (inputs/outputs) that can be reloaded/replayed
- The same workflow+inputs yields the same stage ordering + tool calls (within network variance)

### M3 — Policy/guard v0
**Goal:** safety-first execution.

Acceptance:
- Mainnet write actions require explicit confirmation (pending confirmation token)
- "No simulate, no send": attempting to execute without a simulation result is blocked
- Slippage limit enforced (e.g. max bps)

### M4 — Jupiter adapter v0 (quote → build → simulate)
**Goal:** end-to-end swap without manual ABI/IDL.

Acceptance:
- A single workflow can:
  - get quote
  - build transaction deterministically
  - simulate transaction
- Outputs include enough data for next stage (`tx`, summary, expected out)

### M5 — Execute + confirmation v0
**Goal:** safe broadcast flow.

Acceptance:
- On mainnet: execute returns `pending`/`needs_confirmation` with a `confirm_token`
- After confirmation: broadcast happens and returns tx signature

### M6 — Trace artifacts (buyer + dev + eagent)
**Goal:** observability.

Acceptance:
- Run directory contains:
  - `trace.jsonl` or equivalent
  - stage artifacts
  - policy decisions
- Redaction rules: secrets are never written

---

## Next MVP (v0.1): Strategy publishing hooks

Acceptance:
- A strategy can be packaged as:
  - metadata (name/version/permissions)
  - workflow template
  - parameter schema
- Loader can list available strategies and render a workflow from parameters

---

## Notes

- Repo name stays `web3mcp` for now (implementation detail). Product name is **W3RT**.
- We prioritize **one complete demo** over partial multi-chain coverage.
