# Troubleshooting

## Quick diagnostics (recommended)

When something looks off (wrong network, pending confirmation stuck, send fails), generate a debug bundle:

- Tool: `system_debug_bundle`

Suggested call:
- `system_debug_bundle out_path=./debug_bundle.json`

What it includes:
- Sui rpc_url + inferred network
- Solana supported networks
- Pending confirmation store counts + small samples
- (Optional) EVM rpc defaults map

What it **does not** include:
- private keys
- keystore contents
- full environment variables

If you need support, share the JSON output (and redact anything you consider sensitive).

## Interpreting `needs_confirmation`

Some tools intentionally return a **successful** response with:

- `status: "needs_confirmation"`

This means the server blocked a potentially sensitive action via the safety model.

What to do:
- Inspect `guard.guard_class` and follow `guard.next`.
- Typical causes:
  - Missing / wrong `confirm_token` on mainnet
  - Attempting direct broadcast without allowing it (e.g. Solana `allow_direct_send=false`)
  - `tx_summary_hash` mismatch (use the one from the pending record)
  - Pending confirmation expired (rebuild to get a fresh confirmation)

## Interpreting structured EVM errors (`error_class`)

When an EVM tool fails with an RPC/runtime error, `ErrorData.data` may include:
- `error_class`: a coarse error category
- `retryable`: whether an automatic retry is reasonable
- `suggest_fix`: a next-step suggestion
- (best-effort) `revert_reason` for `EXECUTION_REVERTED`

Common EVM classes:
- `EXECUTION_REVERTED` / `CALL_EXCEPTION`: simulate/preview to extract reason; check params/state; for ERC20/swap check allowance/approval
- `INSUFFICIENT_FUNDS_FOR_GAS`: add native token for gas
- `INSUFFICIENT_ALLOWANCE`: approve allowance_target/spender, then retry
- `NONCE_TOO_LOW` / `NONCE_TOO_HIGH`: rebuild with correct pending nonce
- `FEE_TOO_LOW` / `REPLACEMENT_UNDERPRICED`: increase maxFeePerGas/maxPriorityFeePerGas
- `CHAIN_ID_MISMATCH`: ensure you are signing for the correct chain_id and broadcasting to the matching network RPC
- `UNPREDICTABLE_GAS_LIMIT`: simulate to find revert; then set explicit gas limit if appropriate

## Interpreting structured Solana errors (`error_class`)

When a Solana tool fails, `ErrorData.data` may include `error_class` + `retryable` + `suggest_fix`.

Common Solana classes:
- `BLOCKHASH_EXPIRED`: fetch fresh blockhash, rebuild, resend
- `ACCOUNT_IN_USE`: wait/retry later
- `INSUFFICIENT_FUNDS_FOR_FEE`: fund fee payer with SOL
- `SIMULATION_FAILED`: inspect simulation logs (preview/simulate), fix accounts/params, rebuild
- `INVALID_ACCOUNT_DATA`: account layout/type mismatch; verify ATA/program/accounts
- `ACCOUNT_NOT_FOUND`: missing account (often missing ATA); create required account and retry

## Interpreting structured Sui errors (`error_class`)

When a Sui tool fails, `ErrorData.data` may include `error_class` + `retryable` + `suggest_fix`.

Common Sui classes:
- `GAS_TOO_LOW`: increase gas_budget / rerun preflight
- `INSUFFICIENT_GAS`: fund the signer with enough SUI for gas
- `OBJECT_NOT_FOUND`: verify object id/ownership
- `OBJECT_LOCKED`: retry later or refetch latest object version and rebuild
- `MOVE_ABORT`: inspect module/function/code, fix params/state, dry-run then rebuild
