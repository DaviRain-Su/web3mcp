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

## EVM examples (Base Sepolia / testnet-first)

### EVM balance (Base testnet)

"On Base testnet, what is the ETH balance of 0x...?"

### EVM transfer (natural language)

"On Base testnet, send 0.001 ETH to 0x..."

> Execution requires `EVM_PRIVATE_KEY=0x...` (use a testnet key) and (optionally) `EVM_RPC_URL_84532=https://sepolia.base.org`.

### EVM transfer (explicit tools)

1) Build:
```json
{
  "tool": "evm_build_transfer_native",
  "params": {
    "sender": "0x...",
    "recipient": "0x...",
    "amount_wei": "1000000000000000",
    "chain_id": 84532,
    "confirm_large_transfer": false
  }
}
```

2) Preflight:
```json
{
  "tool": "evm_preflight",
  "params": {
    "tx": "<paste the JSON from evm_build_transfer_native>"
  }
}
```

3) Sign:
```json
{
  "tool": "evm_sign_transaction_local",
  "params": {
    "tx": "<paste the tx from evm_preflight>",
    "allow_sender_mismatch": false
  }
}
```

4) Send:
```json
{
  "tool": "evm_send_raw_transaction",
  "params": {
    "raw_tx": "<raw_tx from signer>",
    "chain_id": 84532
  }
}
```

## Notes

- If multiple Sui keystore accounts exist, set `SUI_DEFAULT_SIGNER` or specify `signer`.
- Use `preflight=true` (Sui) / `evm_preflight` (EVM) to get dry-run diagnostics before execution.
- Network names like “Base testnet / Sepolia / Arbitrum testnet / BSC testnet” are normalized to EVM `chain_id` under the hood (testnet-first).

