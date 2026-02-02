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
