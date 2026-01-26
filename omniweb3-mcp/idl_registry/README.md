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

### Example Programs Configuration

Currently configured programs:

| Program | ID | Status | Tools |
|---------|-----|--------|-------|
| Jupiter v6 | `JUP6...` | ✅ Enabled | 6 tools |
| Metaplex Token Metadata | `meta...` | ⏸️ Disabled | TBD |
| Raydium AMM v4 | `675k...` | ⏸️ Disabled | TBD |
| Orca Whirlpool | `whir...` | ⏸️ Disabled | TBD |
| Marinade Finance | `MarB...` | ⏸️ Disabled | TBD |

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
