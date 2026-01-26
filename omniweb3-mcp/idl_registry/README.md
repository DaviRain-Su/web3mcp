# IDL Registry

This directory contains Anchor IDL files for Solana programs and configuration for dynamic tool generation.

## Configuration File: programs.json

The `programs.json` file defines which Solana programs should be loaded for dynamic tool generation.

### Structure

```json
{
  "solana_programs": [
    {
      "id": "program_address",
      "name": "short_name",
      "display_name": "Human Readable Name",
      "category": "category_name",
      "enabled": true/false,
      "description": "Description of the program",
      "note": "Optional note"
    }
  ]
}
```

### Fields

- **id** (required): The program's on-chain address
- **name** (required): Short name used for tool prefixing (e.g., `jupiter_route`)
- **display_name** (required): Human-readable name for logging
- **category** (optional): Category for organization (e.g., `dex`, `nft`, `liquid_staking`)
- **enabled** (required): `true` to load this program, `false` to skip
- **description** (optional): Brief description of what the program does
- **note** (optional): Additional notes or TODOs

### Categories

- `dex`: Decentralized exchanges
- `dex_aggregator`: DEX aggregators like Jupiter
- `nft`: NFT-related programs
- `liquid_staking`: Liquid staking protocols
- `lending`: Lending protocols
- `oracle`: Price oracles

### How to Add a New Program

1. Add a new entry to `solana_programs` array in `programs.json`
2. Set `enabled: false` initially
3. Download the IDL file (see below)
4. Test with `enabled: true`

### Downloading IDL Files

Option 1: Use the download script
```bash
./scripts/download_idls.sh
```

Option 2: Manual download from Solana FM
```bash
curl "https://api.solanafm.com/v0/accounts/PROGRAM_ID/idl" \
  -o idl_registry/PROGRAM_ID.json
```

Option 3: From program's GitHub repository
```bash
# Example: Orca Whirlpool
curl "https://raw.githubusercontent.com/orca-so/whirlpools/main/programs/whirlpool/target/idl/whirlpool.json" \
  -o idl_registry/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json
```

### IDL File Naming

IDL files should be named exactly as the program ID:
```
idl_registry/JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4.json
```

The IDL resolver will:
1. First check for local file: `idl_registry/{PROGRAM_ID}.json`
2. Fall back to Solana FM API if not found locally

### Configured Programs

**Current Status** (2026-01-26):
- **Total Programs Configured**: 16
- **Enabled**: 12 programs
- **Disabled**: 4 programs (IDL not publicly available)
- **Dynamic Tools Generated**: 637 instructions

#### ✅ Enabled Programs (12)

| # | Program | ID | Instructions | Category |
|---|---------|-----|--------------|----------|
| 1 | Jupiter v6 | `JUP6...` | 6 | DEX Aggregator |
| 2 | Metaplex | `meta...` | 58 | NFT |
| 3 | Orca Whirlpool | `whir...` | 58 | DEX |
| 4 | Marinade | `MarB...` | 28 | Liquid Staking |
| 5 | Drift | `dRif...` | 241 | Perpetuals |
| 6 | Meteora DLMM | `LBUZ...` | 74 | DEX |
| 7 | Meteora DAMM v2 | `cpam...` | 35 | DEX |
| 8 | Meteora DAMM v1 | `Eo7W...` | 26 | DEX |
| 9 | Meteora DBC | `dbci...` | 28 | Token Launch |
| 10 | PumpFun | `6EF8...` | 27 | Token Launch |
| 11 | Squads V4 | `SQDS...` | 31 | Multisig |
| 12 | Raydium CLMM | `CAMM...` | 25 | DEX |
| | **Total** | | **637** | |

#### ❌ Disabled Programs (4)

| Program | ID | Reason |
|---------|-----|--------|
| Raydium AMM v4 | `675k...` | Non-Anchor, legacy |
| Kamino Lending | `KLen...` | IDL not publicly available |
| Meteora M3M3 | `FEES...` | IDL not publicly available |
| Sanctum S Controller | `5ocn...` | IDL not publicly available |

**For detailed acquisition attempts and findings, see:**
- [Manual IDL Guide](./MANUAL_IDL_GUIDE.md)
- [IDL Acquisition Summary](/tmp/final_idl_summary.md)

### Environment Variables

Related environment variables:
- `ENABLE_DYNAMIC_TOOLS=true` - Enable/disable dynamic tool loading
- `SOLANA_RPC_URL` - Solana RPC endpoint (default: mainnet-beta)

### Error Handling

The system gracefully handles errors:
- If `programs.json` is missing → falls back to Jupiter only
- If a program's IDL fails to load → logs warning and continues with other programs
- If enabled=false → skips the program entirely

### Logging

The server logs program loading status:
```
info: Loading Solana programs from configuration...
info: Attempting to load Jupiter v6...
info: IDL loaded: jupiter, 7 instructions
info: Skipping disabled program: Metaplex Token Metadata
info: Programs: 1 loaded, 0 failed, 4 skipped
```

### Best Practices

1. **Start with enabled=false** for new programs
2. **Test locally** before enabling in production
3. **Keep IDLs updated** when programs upgrade
4. **Document failures** in the "note" field
5. **Use descriptive names** for easy identification

### Troubleshooting

**Program not loading?**
1. Check if `enabled: true` in `programs.json`
2. Verify IDL file exists: `ls idl_registry/PROGRAM_ID.json`
3. Validate IDL JSON: `jq empty idl_registry/PROGRAM_ID.json`
4. Check server logs for specific error

**Invalid JSON error?**
```bash
# Validate programs.json
jq empty idl_registry/programs.json

# Pretty print for debugging
jq '.' idl_registry/programs.json
```

**IDL not found?**
- Download manually from Solana FM or program's GitHub
- Check program ID is correct
- Ensure file has `.json` extension

### Future Enhancements

- [ ] Auto-discovery of programs from on-chain data
- [ ] IDL versioning and automatic updates
- [ ] Web UI for managing program configuration
- [ ] Hot-reloading without server restart
- [ ] IDL caching with TTL
- [ ] Support for non-Anchor programs (native Solana programs)

---

## Related Documentation

- [Manual IDL Acquisition Guide](./MANUAL_IDL_GUIDE.md) - Detailed guide for obtaining IDLs manually
- [API Services Analysis](../docs/zh-CN/API_SERVICES_ANALYSIS.md) - Analysis of REST APIs provided by onchain programs
- [Next Steps](../docs/zh-CN/NEXT_STEPS.md) - Roadmap and future plans
- [Hybrid Architecture](../docs/zh-CN/HYBRID_ARCHITECTURE.md) - Overview of static + dynamic tool architecture

---

## Statistics

**Growth Timeline**:
- Initial (Phase 1): 171 tools (165 static + 6 dynamic from Jupiter only)
- Current (Phase 2): ~802 tools (165 static + 637 dynamic from 12 programs)
- **Growth**: +369% tools (+631 tools)

**Programs by Category**:
- DEX/AMM: 7 programs (356 instructions, 56%)
- Perpetuals: 1 program (241 instructions, 38%)
- NFT: 1 program (58 instructions, 9%)
- Liquid Staking: 1 program (28 instructions, 4%)
- Token Launch: 2 programs (55 instructions, 9%)
- Multisig: 1 program (31 instructions, 5%)

**Success Rate**: 12/16 programs successfully integrated (75%)
