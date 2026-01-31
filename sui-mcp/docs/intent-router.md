# Intent Router Design

This document captures the intent-router design for a multi-chain MCP server. The intent router sits above chain-specific tools and translates natural language into executable tool plans.

## Goal

Provide a chain-agnostic intent layer that can parse user intent, generate execution plans, and route tool calls across Sui, EVM, and Solana without hardcoding behavior per chain.

## Conceptual Layers

1) **Intent Core (Chain-agnostic)**
- `intent_parse`: Convert natural language into a structured intent payload.
- `intent_plan`: Produce a plan with tool calls and missing fields.
- `intent_execute`: Execute a validated plan and return results.

2) **Chain Adapters (Chain-specific)**
- **SuiAdapter**: map intent to Sui tools (`build_transfer_sui`, `execute_transaction_with_keystore`, `auto_fill_move_call`).
- **EvmAdapter**: map intent to EVM tools (`eth_sendTransaction`, ERC20 transfer, gas estimate).
- **SolanaAdapter**: map intent to Solana tools (system transfer, SPL transfer).

3) **Execution Layer**
- Executes tool calls in order, supports dry-run, simulation, and confirmation steps.
- Tracks partial results and updates missing fields as they become available.

## Intent Schema (Draft)

Key idea: **humans talk in chain names** ("Base testnet", "Ethereum", "Arbitrum"), but the execution layer must be stable.
So we normalize user input into:

- `family`: `sui | evm | solana`
- `chain_id`: EVM chain id when `family=evm`
- `network_name`: human-friendly normalized name

```json
{
  "action": "transfer | swap | stake | unstake | pay | query",
  "network": {
    "family": "sui | evm | solana | auto",
    "network_name": "sui | base-sepolia | ethereum | arbitrum-sepolia | ...",
    "chain_id": 84532
  },
  "asset": "SUI | USDC | ETH | ...",
  "amount": "1.5",
  "from": "0x...",
  "to": "0x...",
  "constraints": {
    "max_slippage": "0.5%",
    "gas_budget": 1000000
  }
}
```

### Human-friendly EVM mapping (testnet-first)

Defaults prefer **testnets** to reduce the risk of accidental mainnet transfers.

- Base
  - `base-sepolia` / "Base testnet" → `chain_id=84532`
  - `base` / "Base mainnet" → `chain_id=8453`
- Ethereum
  - `sepolia` / "Ethereum testnet" → `chain_id=11155111`
  - `ethereum` / "Ethereum mainnet" → `chain_id=1`
- Arbitrum
  - `arbitrum-sepolia` / "Arbitrum testnet" → `chain_id=421614`
  - `arbitrum` / "Arbitrum One mainnet" → `chain_id=42161`
- BSC
  - `bsc-testnet` / "BSC testnet" → `chain_id=97`
  - `bsc` / "BSC mainnet" → `chain_id=56`

RPC URLs are configured per chain id via `EVM_RPC_URL_<chainId>` (example: `EVM_RPC_URL_84532=https://sepolia.base.org`).


## Plan Schema (Draft)

```json
{
  "intent": { "..." },
  "missing": ["to", "amount"],
  "plan": [
    {
      "chain": "sui",
      "tool": "build_transfer_sui",
      "params": { "sender": "0x...", "recipient": "0x..." }
    },
    {
      "chain": "sui",
      "tool": "execute_transaction_with_keystore",
      "params": { "tx_bytes": "<tx_bytes>", "signer": "0x..." }
    }
  ]
}
```

## Safety & Validation

- Validate sender/signing address match unless explicitly allowed.
- Require explicit confirmation for large transfers.
- Allow dry-run/simulation before execution.

## Implementation Steps (Suggested)

1) Extract `nl_intent` into `intent_parse` and `intent_plan` tools.
2) Create a common intent schema used across chains.
3) Add Sui adapter mapping first (existing tools).
4) Stub EVM/Solana adapters with TODO mappings.
5) Add `intent_execute` to run tool plans and collect results.

## Notes

- This is an **application-level router**, not a chain-level intent protocol.
- The design is compatible with AI-agent workflows: intent → plan → execute.
