# Prompt Pack — Mainnet Safe (2-phase)

These prompts are designed to demonstrate mainnet flows **without accidental sends**.

0) If anything looks wrong
- "Run `system_debug_bundle out_path=./debug_bundle.json` and show me the JSON output (no secrets)."

## EVM mainnet (safe)
- "On Base mainnet (`chain_id=8453`), build a tiny native transfer, run `evm_preflight`, then `evm_create_pending_confirmation`. Do not broadcast until I confirm; then use `evm_retry_pending_confirmation` with `confirm_token`."

## Solana mainnet (safe)
- "Create a transaction, call `solana_send_transaction` with `confirm=false`, then show me how `solana_confirm_transaction` requires `confirm_token` on mainnet. Do not broadcast until I confirm."

## Sui mainnet (safe)
- "Build a Sui transaction using a safe-default tool so it returns a pending confirmation, then show me how `sui_confirm_execution` requires `confirm_token` on mainnet. Do not send until I confirm."
