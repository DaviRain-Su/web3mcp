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
