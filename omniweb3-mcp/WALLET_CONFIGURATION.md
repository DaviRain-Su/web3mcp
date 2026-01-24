# Wallet Configuration Guide

This guide explains how to configure wallets for signing and sending transactions using OmniWeb3 MCP tools.

## Overview

OmniWeb3 MCP supports two wallet types:
- **Privy wallets** (default when `wallet_id` is provided)
- **Local wallets** (filesystem keypairs or private keys)

## Wallet Type Selection

### Automatic Detection (Recommended)

**When you provide `wallet_id`, Privy wallet type is assumed by default:**

```json
{
  "wallet_id": "your-privy-wallet-id"
}
```

This is equivalent to:

```json
{
  "wallet_type": "privy",
  "wallet_id": "your-privy-wallet-id"
}
```

### Explicit Configuration

You can explicitly specify the wallet type:

**Privy Wallet:**
```json
{
  "wallet_type": "privy",
  "wallet_id": "your-privy-wallet-id"
}
```

**Local Wallet:**
```json
{
  "wallet_type": "local",
  "keypair_path": "/path/to/keypair.json"  // For Solana
}
```

or for EVM chains:

```json
{
  "wallet_type": "local",
  "private_key": "0x..."  // For Ethereum/EVM
}
```

## Supported Tools

The following tools support both wallet types:

### Unified Tools
- `transfer` - Transfer native tokens across Solana/EVM
- `sign_and_send` - Sign and send transactions

### Solana DeFi Tools

#### Jupiter
- `jupiter_swap` - Build Jupiter swap transaction
- `jupiter_execute_swap` - Execute complete Jupiter swap
- `jupiter_ultra_order` - Create Jupiter Ultra order
- `jupiter_create_trigger_order` - Create Jupiter trigger (limit) order
- `jupiter_cancel_trigger_order` - Cancel Jupiter trigger order
- `jupiter_cancel_trigger_orders` - Batch cancel Jupiter trigger orders
- `jupiter_create_recurring_order` - Create Jupiter recurring (DCA) order
- `jupiter_cancel_recurring_order` - Cancel Jupiter recurring order
- `jupiter_lend_deposit` - Create Jupiter Lend deposit transaction
- `jupiter_lend_withdraw` - Create Jupiter Lend withdraw transaction
- `jupiter_lend_mint` - Create Jupiter Lend mint transaction
- `jupiter_lend_redeem` - Create Jupiter Lend redeem transaction
- `jupiter_craft_send` - Create Jupiter Send transaction
- `jupiter_craft_clawback` - Create Jupiter Send clawback transaction
- `jupiter_claim_dbc_fee` - Claim DBC pool fees
- `jupiter_create_dbc_pool` - Create DBC pool

#### Meteora
- All Meteora DeFi operations

#### dFlow
- All dFlow trading operations

## Examples

### Example 1: Transfer with Privy Wallet (Implicit)

```json
{
  "tool": "transfer",
  "chain": "solana",
  "to_address": "...",
  "amount": "1000000",
  "wallet_id": "privy-wallet-123"
}
```

The tool automatically detects this as a Privy wallet because `wallet_id` is provided.

### Example 2: Transfer with Local Wallet

```json
{
  "tool": "transfer",
  "chain": "solana",
  "to_address": "...",
  "amount": "1000000",
  "wallet_type": "local",
  "keypair_path": "~/.config/solana/id.json"
}
```

### Example 3: Jupiter Swap with Privy Wallet

```json
{
  "tool": "jupiter_execute_swap",
  "input_mint": "So11111111111111111111111111111111111111112",
  "output_mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "amount": "1000000",
  "wallet_id": "privy-wallet-123",
  "slippage_bps": 50
}
```

No need to specify `wallet_type` - it defaults to `privy` when `wallet_id` is present.

### Example 4: Jupiter Swap with Local Wallet

```json
{
  "tool": "jupiter_execute_swap",
  "input_mint": "So11111111111111111111111111111111111111112",
  "output_mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "amount": "1000000",
  "wallet_type": "local",
  "keypair_path": "~/.config/solana/id.json",
  "slippage_bps": 50
}
```

## Environment Configuration

### Privy Wallet Setup

To use Privy wallets, set the following environment variables:

```bash
export PRIVY_APP_ID="your-app-id"
export PRIVY_APP_SECRET="your-app-secret"
```

### Local Wallet Setup

For Solana local wallets, ensure your keypair file exists:

```bash
# Default Solana CLI location
~/.config/solana/id.json

# Or custom path
/path/to/your/keypair.json
```

For EVM local wallets, provide the private key directly in the request.

## Key Points

✅ **Default Behavior**: Providing `wallet_id` automatically selects Privy wallet type
✅ **Local Wallets**: Explicitly set `wallet_type: "local"` and provide `keypair_path` or `private_key`
✅ **Backward Compatible**: Existing code with explicit `wallet_type` continues to work
✅ **Security**: Local keypairs are read from filesystem; Privy uses API authentication

## Troubleshooting

### Error: "Missing required parameter: wallet_type"

**Cause**: Neither `wallet_id` nor explicit `wallet_type` was provided.

**Solution**: Provide either:
- `wallet_id` (for Privy), or
- `wallet_type: "local"` with `keypair_path`/`private_key`

### Error: "wallet_id is required when wallet_type='privy'"

**Cause**: Explicitly set `wallet_type: "privy"` but didn't provide `wallet_id`.

**Solution**: Provide the `wallet_id` parameter.

### Error: "Invalid wallet_type. Use 'local' or 'privy'"

**Cause**: Invalid value for `wallet_type`.

**Solution**: Use only `"local"` or `"privy"` (case-sensitive).

## Migration Guide

If you have existing code that explicitly specifies `wallet_type: "privy"`:

**Before:**
```json
{
  "wallet_type": "privy",
  "wallet_id": "wallet-123"
}
```

**After (simplified):**
```json
{
  "wallet_id": "wallet-123"
}
```

Both work identically. The simplified version is recommended for cleaner code.
