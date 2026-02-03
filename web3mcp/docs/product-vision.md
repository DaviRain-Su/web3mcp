# Web3 AI Runtime (W3RT) — Product Vision

> Initial product concept and execution plan based on current discussions.

## 1. One-line positioning
A Web3 AI Runtime that understands natural language, generates strategies, and **safely executes** on-chain actions via a deterministic workflow engine.

**Product promise:** users can say *one sentence* ("swap 0.01 SOL to USDC"), and W3RT will:
1) plan
2) simulate
3) request approval (policy)
4) create a pending confirmation
5) require an explicit confirm token on mainnet before broadcast

## 2. Core idea
AI should **not** assemble complex contract parameters directly, and it should not be asked to pick from hundreds of low-level chain tools.

Instead we expose a **small, stable set of workflow tools** (a "meta-language" / DSL), and keep protocol/chain details inside Rust adapters:

```
Natural language → Intent (schema) → Plan (meta-language) → Workflow Engine → Protocol Adapter → Chain drivers
```

This keeps AI in the *decision* layer, while Rust code performs deterministic parameter construction, simulation, policy checks, and execution.

## 3. Target user shapes
1. **Desktop AI users** (Claude/Codex/ChatGPT Desktop)
   - Use via MCP server or Pi extension wrapper.
2. **Developers**
   - Integrate via SDK/API, call structured strategy/workflow endpoints.
3. **Other agents / platforms**
   - Use W3RT as a sub-agent / execution engine.

## 4. Product shape (layered architecture)

### 4.0 Human-facing UX: "one sentence"
The user does **not** need to know protocol IDs, ABI/IDL, or which tool to call.

Examples (Solana mainnet):
- "Swap 0.01 SOL to USDC."
- "Swap 50 USDC to SOL, slippage 0.5%."
- "Send 0.005 SOL to <address>."

The runtime converts the sentence into a deterministic workflow run.

### 4.1 AI Agent layer
- Multi-step reasoning loop
- Gathers required data via read-only tools
- Generates strategy / workflow
- Requests user approval for write operations

### 4.2 Workflow Engine (deterministic)
Stages:
- analysis → simulation → approval → execution → monitor

**Design requirement:** these stages are the *only* supported way to do writes. Any mainnet broadcast must be preceded by simulation and approval.

### 4.3 Protocol Adapter layer
- Translates chain-agnostic intent into chain-specific transactions
- Handles protocol differences (Jupiter/Cetus/Uniswap etc.)

### 4.4 Chain tool layer (web3mcp)
- Actual chain RPC interaction
- Pending confirmation flow for mainnet
- Signing, simulation, execution

## 5. Not limited to DeFi
The runtime can extend beyond DeFi to:
- NFT mint/transfer/listing
- DAO governance and voting
- GameFi asset management
- Cross-chain actions
- On-chain identity workflows

## 6. Key product principles
- **Safety-first**: every write action passes policy checks
- **Deterministic execution**: workflows are auditable and replayable
- **Protocol abstraction**: AI never touches low-level ABI/IDL/Move details
- **Multi-user compatibility**: desktop users, developers, and other agents

## 7. Core modules (planned)
| Module | Purpose | Notes |
| --- | --- | --- |
| Policy Runtime | allowlist/limits/risk rules | upgrade current mainnet safety |
| Workflow Engine | staged execution | analysis→simulation→approval→execution→monitor |
| Protocol Adapters | protocol translation | Jupiter/Cetus/Uniswap etc. |
| Trace Runtime | runId + audit trail | JSONL + artifacts + replay |
| Wallet Manager | unified signer / wallet state | future phase |
| CLI / TUI | optional UX layer | MCP remains primary entry |

## 8. Solana-first plan (initial MVP)
1. **Intent schema** for Solana swap/transfer
2. **Jupiter Adapter** (quote → build → simulate → execute)
3. **Minimal workflow engine**
4. **Policy basics** (mainnet gate, allowlist, slippage limit)

## 9. Integration strategy
- Keep Rust core in `web3mcp`.
- Provide optional **TypeScript Pi extension wrapper** that proxies to MCP.

### 9.1 Public MCP surface area (should be small)
The MCP server should **not** expose the entire internal chain/protocol toolbox by default.

**Public tools (recommended default):**
- `w3rt_run_workflow_v0` — single entrypoint that writes artifacts for analysis/simulate/approval/execute and enforces safety.
- `solana_confirm_transaction` / `evm_retry_pending_confirmation` / `sui_confirm_execution` — explicit confirmation tools (mainnet safety).
- Basic health/debug: `system_healthcheck`, `system_network_context`, `system_debug_bundle`.

Everything else should be considered **internal / advanced** (feature-flagged or hidden), to keep the UX "one sentence" and to reduce LLM tool-selection errors.

### 9.2 Meta-language (stable contract)
The output artifacts (intent/plan/simulate/approval/execute) are the stable contract.
Clients integrate against these JSON artifacts and status codes, not against chain-specific tool names.

## 10. Why this shape works
- Fixes AI parameter errors by removing raw ABI/IDL manipulation.
- Preserves high performance and safety with Rust.
- Keeps MCP compatibility while enabling agent-based execution.

---

*Status: initial vision draft (to be expanded into design specs).* 
