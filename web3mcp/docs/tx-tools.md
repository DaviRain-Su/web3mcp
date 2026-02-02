# Transaction tools & safety model

This document is a quick reference for **transaction/broadcast-related tools** and how the server enforces safety, especially on **mainnet**.

## TL;DR matrix

| Chain | Create pending (no broadcast) | Broadcast / confirm | Mainnet requires `confirm_token` | Store |
|------|-------------------------------|---------------------|----------------------------------|-------|
| EVM | `evm_create_pending_confirmation` | `evm_retry_pending_confirmation` | Yes | sqlite (`evm_pending_confirmations`) |
| Solana | `solana_send_transaction` (`confirm=false`) | `solana_confirm_transaction` | Yes | file (`confirm_store/solana_confirm_store.json`) |
| Sui | any safe-default Sui tx tool (`confirm=false`) | `sui_confirm_execution` / `sui_retry_pending_confirmation` | Yes | sqlite (`sui_pending_confirmations`) |

## Safety model (summary)

- **Mainnet** broadcasts require a second-step `confirm_token`.
- Most write-capable tools follow a **2-phase** workflow:
  1) Build/preflight or create a pending confirmation (no broadcast)
  2) Confirm/retry/broadcast (requires `confirm_token` on mainnet)

## Pending stores

- **EVM**: sqlite `evm_pending_confirmations` (under repo cwd)
- **Sui**: sqlite `sui_pending_confirmations` (under repo cwd)
- **Solana**: file-backed `confirm_store/solana_confirm_store.json` (under repo cwd)

Tip:
- Use `system_debug_bundle` to see store paths + pending counts.

## EVM (broadcast path)

### Build / preflight
- `evm_build_transfer_native` (builds an `EvmTxRequest`)
- `evm_preflight` (fills nonce/gas/fees)

### Create pending confirmation
- `evm_create_pending_confirmation`
  - Input: `EvmTxRequest` (recommended: from `evm_preflight`)
  - Output: `confirmation_id`, `tx_summary_hash`, `confirm_token`

### Broadcast / retry
- `evm_retry_pending_confirmation`
  - **Mainnet**: requires `confirm_token`
  - Also requires `tx_summary_hash` match

### Raw broadcast (advanced)
- `evm_send_raw_transaction`
  - Not recommended for normal users.

## Solana (broadcast path)

### Create pending confirmation
- `solana_send_transaction` with `confirm=false`
  - Output: `pending_confirmation_id`, `tx_summary_hash`

### Broadcast
- `solana_confirm_transaction`
  - **Mainnet**: requires `confirm_token`

## Sui (broadcast path)

### Create pending confirmation
- Safe-default Sui tx tools with `confirm=false` will return:
  - `confirmation_id`, `tx_summary_hash`

### Broadcast
- `sui_confirm_execution`
  - **Mainnet**: requires `confirm_token`

### Retry
- `sui_retry_pending_confirmation`
  - **Mainnet**: requires `confirm_token`
