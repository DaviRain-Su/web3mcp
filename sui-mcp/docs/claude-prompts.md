# Claude Prompt Examples

These are copy-paste friendly prompts for Claude Desktop using this MCP server.

## Wallet overview

"Show me a wallet overview for 0x... including coin objects."

## Simple transfer

"Send 0.01 SUI to 0x... from my default keystore account."

## One-step transfer (explicit tool)

```
Use tool: execute_transfer_sui
{
  "sender": "0x...",
  "recipient": "0x...",
  "amount": 10000000,
  "input_coins": [],
  "auto_select_coins": true,
  "gas_budget": null,
  "preflight": true
}
```

## Stake

"Stake 0.5 SUI to validator 0x..."

## Unstake

"Withdraw stake from 0x<staked_sui>"

## Batch transaction

"Batch: send 0.01 SUI to 0xA and 0.01 SUI to 0xB"

## Move call

"Call 0x<package>::module::function with args ..."

## Notes

- If multiple keystore accounts exist, set `SUI_DEFAULT_SIGNER` or specify `signer`.
- Use `preflight=true` to get dry-run diagnostics before execution.
