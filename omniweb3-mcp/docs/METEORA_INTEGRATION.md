# Meteora Integration Status

## Overview

This document describes the current status of Meteora protocol integration in omniweb3-mcp and known limitations.

## Current Status

### ✅ Working
- Tools are accessible via MCP and can fetch on-chain account data
- Pool account discovery works (finds DLMM, DAMM pools by address)
- Program ID verification works correctly
- Basic account structure fetching from Solana RPC

### ⚠️  Partial / Known Issues
- **On-chain data parsing is incorrect**: The current implementation reads account data at hardcoded byte offsets (lines like `std.mem.readInt(i32, data[8..12], .little)`) that don't match the actual Meteora program account layouts.
- This results in garbage values for critical fields:
  - `active_bin_id`: Should be in range -443,636 to 443,636, but returns values like -1,543,503,728
  - `bin_step`: Returns unexpected values like 29,787
  - `price`: Returns 0 or infinity instead of actual market prices

## Root Cause

The Meteora DLMM program uses Borsh serialization with a complex account structure that has evolved over time. The current implementation:

1. **Uses manual byte offsets** instead of proper Borsh deserialization
2. **Account structure has changed**: Issue #247 in Meteora SDK mentions "The IDL is too old, LbPair does not match the new version of the IDL"
3. **No discriminator handling**: Anchor accounts include an 8-byte discriminator that must be accounted for
4. **Field ordering unknown**: Without the exact Borsh schema, byte offsets are unreliable

## Proper Account Structure (from IDL)

The LbPair account should contain (in Borsh-serialized format):
- `parameters`: Pool parameters struct
- `v_parameters`: Additional parameters
- `bump_seed`: PDA bump seeds
- `bin_step_seed`: Bin step value
- `pair_type`: Pool type enum
- `active_id`: Current active bin ID (i24)
- `bin_step`: Price increment per bin (u16)
- `status`: Pool status
- `padding`: Reserved bytes
- `token_x_mint`: Token X mint address (32 bytes)
- `token_y_mint`: Token Y mint address (32 bytes)
- `reserve_x`: Token X reserve address (32 bytes)
- `reserve_y`: Token Y reserve address (32 bytes)
- `protocol_fee`: Protocol fee configuration
- `oracle`: Oracle address (32 bytes)
- `reward_infos`: Reward configuration array

**Plus**: 8-byte Anchor discriminator at the beginning

## Recommended Solutions

### Option 1: Use Meteora REST API (Easiest)
Use the official Meteora APIs instead of parsing on-chain data:
- **DLMM Pairs**: `https://dlmm-api.meteora.ag/pair/all`
- **Pool Info**: `https://dlmm-api.meteora.ag/pair/{pool_address}`
- **Swap Quote**: Built into the API endpoints

**Benefits**:
- Accurate data
- No deserialization needed
- Includes computed fields (APY, volume, TVL)

**Implementation**: Add new tools that call these HTTP endpoints

### Option 2: Implement Proper Borsh Deserialization
Parse account data correctly using Borsh:
1. Add Borsh deserialization library to Zig project
2. Define Meteora account structures matching the IDL
3. Handle discriminators properly
4. Parse nested structures

**Benefits**:
- Works offline with any RPC
- No API rate limits

**Challenges**:
- Requires Borsh library for Zig (or manual implementation)
- Must keep structs in sync with Meteora program updates
- Complex nested structures

### Option 3: Use TypeScript SDK via Node Process
Call the official `@meteora-ag/dlmm` SDK:
1. Create a Node.js helper script
2. Call SDK methods from Zig using process execution
3. Parse JSON output

**Benefits**:
- Uses official, maintained code
- Always up-to-date with program changes

**Challenges**:
- Requires Node.js installation
- Performance overhead
- Complex error handling

## Testing Results

### Test Pool
- **Address**: `BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y`
- **Type**: DLMM SOL-USDC
- **Source**: [Meteora App](https://www.meteora.ag/dlmm/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y)

### Current Output vs Expected

| Field | Current Output | Expected | Issue |
|-------|---------------|----------|-------|
| active_bin_id | -1,543,503,728 | ~24,000 to 25,000 | Wrong offset |
| bin_step | 29,787 | 1-100 | Wrong offset |
| price | 0 | ~$125 (SOL price) | Derived from bad bin_id |
| program_id | ✅ Correct | ✅ | Works |
| data_len | ✅ 1208 bytes | ✅ | Works |

## Tools Affected

All 42 Meteora tools that read on-chain data:

### DLMM (9 tools)
- `meteora_dlmm_get_pool` ⚠️  Returns incorrect data
- `meteora_dlmm_get_active_bin` ⚠️  Returns incorrect data
- `meteora_dlmm_get_bins` ⚠️  Returns incorrect data
- `meteora_dlmm_get_positions` ⚠️  Returns incorrect data
- `meteora_dlmm_swap_quote` ⚠️  Returns incorrect data
- Write operations (swap, add/remove liquidity, claim) ❌ Unusable with bad data

### DAMM V2 (7 tools)
Similar issues with on-chain data parsing

### Other Protocols
- DBC, Alpha Vault, M3M3, Vault: Same pattern of issues

## References

- [Meteora Documentation](https://docs.meteora.ag)
- [Meteora DLMM SDK](https://github.com/MeteoraAg/dlmm-sdk)
- [Meteora API Endpoint](https://dlmm-api.meteora.ag/pair/all)
- [IDL Structure Issue #247](https://github.com/MeteoraAg/dlmm-sdk/issues/247)
- [DLMM Pool on Meteora](https://www.meteora.ag/dlmm/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y)
- [DexScreener SOL-USDC](https://dexscreener.com/solana/bgm1tav58ogcsqjehl9wxbfxf7d27vzskefj4xjkd5y)

## Next Steps

**Recommended**: Implement Option 1 (REST API integration) as it provides:
- Immediate accurate results
- No maintenance burden
- Additional computed metrics
- Production-ready endpoints

**Long-term**: Consider Option 2 for a complete on-chain solution if Borsh deserialization library becomes available for Zig.

## Example API Usage

```bash
# Get all DLMM pairs
curl https://dlmm-api.meteora.ag/pair/all

# Get specific pool info
curl https://dlmm-api.meteora.ag/pair/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y

# Get swap quote
curl "https://dlmm-api.meteora.ag/swap/quote?inputMint=So11111111111111111111111111111111111111112&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&amount=100000000&slippage=1"
```
