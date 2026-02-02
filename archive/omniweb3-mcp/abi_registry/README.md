# EVM ABI Registry

This directory contains ABI (Application Binary Interface) files for EVM-compatible smart contracts across multiple chains.

## Overview

The ABI registry enables **dynamic tool generation** for EVM contracts, similar to the Solana IDL registry. Contract ABIs are automatically loaded at startup and converted into MCP tools.

## Directory Structure

```
abi_registry/
├── README.md                 # This file
├── contracts.json            # Contract registry (metadata)
├── bsc/                      # Binance Smart Chain (BSC) contracts
│   ├── wbnb.json            # Wrapped BNB
│   ├── erc20_standard.json  # Standard ERC20 ABI
│   ├── pancakeswap_router_v2.json
│   └── ...
└── ethereum/                 # Ethereum mainnet contracts (future)
    └── ...
```

## Supported Chains

### BSC (Binance Smart Chain) - Chain ID: 56

| Contract | Address | Category | Description |
|----------|---------|----------|-------------|
| **PancakeSwap Router V2** | `0x10ED43C718714eb63d5aA57B78B54704E256024E` | DEX | Swap, liquidity |
| **PancakeSwap Factory V2** | `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73` | DEX | Pair creation |
| **WBNB** | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` | Token | Wrapped BNB |
| **BUSD** | `0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56` | Token | Stablecoin |
| **USDT** | `0x55d398326f99059fF775485246999027B3197955` | Token | Stablecoin |
| **CAKE** | `0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82` | Token | PancakeSwap token |
| **Venus Comptroller** | `0xfD36E2c2a6789Db23113685031d7F16329158384` | Lending | Lending protocol |

## ABI File Format

ABI files follow the standard Ethereum ABI JSON format:

```json
[
  {
    "inputs": [...],
    "name": "functionName",
    "outputs": [...],
    "stateMutability": "nonpayable|view|pure|payable",
    "type": "function"
  },
  {
    "anonymous": false,
    "inputs": [...],
    "name": "EventName",
    "type": "event"
  }
]
```

## Contract Registration

Contracts are registered in `contracts.json`:

```json
{
  "evm_contracts": [
    {
      "chain": "bsc",
      "chain_id": 56,
      "address": "0x10ED43C718714eb63d5aA57B78B54704E256024E",
      "name": "pancakeswap_router_v2",
      "display_name": "PancakeSwap Router V2",
      "category": "dex",
      "enabled": true,
      "description": "PancakeSwap V2 Router - swap, liquidity management"
    }
  ]
}
```

### Registration Fields

- **chain**: Chain identifier (e.g., `bsc`, `ethereum`)
- **chain_id**: EIP-155 chain ID (BSC: 56, Ethereum: 1)
- **address**: Contract address (EIP-55 checksummed)
- **name**: Internal identifier (used for file naming)
- **display_name**: Human-readable name
- **category**: Contract category (`dex`, `lending`, `token`, etc.)
- **enabled**: Whether to load this contract (true/false)
- **description**: Brief description

## Tool Generation

Each contract function generates an MCP tool with naming convention:

```
{chain}_{contract_name}_{function_name}
```

Examples:
- `bsc_pancakeswap_router_v2_swapExactTokensForTokens`
- `bsc_wbnb_deposit`
- `bsc_wbnb_withdraw`
- `bsc_busd_transfer`

### Function Categories

**View Functions** (read-only):
- `balanceOf`, `allowance`, `totalSupply`
- `getAmountsOut`, `getAmountsIn`
- Generate tools that query state without transactions

**State-Changing Functions** (write):
- `transfer`, `approve`, `swap*`, `addLiquidity`
- Generate tools that build and send transactions
- Require wallet signature and gas fees

## Adding New Contracts

### Step 1: Obtain ABI

**From BSCScan**:
1. Go to BSCScan.com
2. Navigate to contract address
3. Click "Contract" tab → "Code"
4. Copy ABI JSON from "Contract ABI" section

**From verified source**:
- GitHub repositories
- Official documentation
- npm packages (`@pancakeswap/sdk`, etc.)

### Step 2: Save ABI File

Save to `abi_registry/{chain}/{contract_name}.json`:

```bash
# Example: Adding a new BSC contract
cat > abi_registry/bsc/my_contract.json << 'EOF'
[
  {
    "inputs": [...],
    "name": "myFunction",
    ...
  }
]
EOF
```

### Step 3: Register in contracts.json

Add entry to `contracts.json`:

```json
{
  "chain": "bsc",
  "chain_id": 56,
  "address": "0xYourContractAddress",
  "name": "my_contract",
  "display_name": "My Contract",
  "category": "dex|lending|token|...",
  "enabled": true,
  "description": "Brief description"
}
```

### Step 4: Restart Server

The contract will be loaded automatically on server startup.

## Common ABI Patterns

### ERC20 Token
Standard functions:
- `balanceOf(address) → uint256`
- `transfer(address, uint256) → bool`
- `approve(address, uint256) → bool`
- `transferFrom(address, address, uint256) → bool`
- `allowance(address, address) → uint256`

### Uniswap V2 / PancakeSwap Router
Key swap functions:
- `swapExactTokensForTokens(uint256, uint256, address[], address, uint256)`
- `swapExactETHForTokens(uint256, address[], address, uint256)` (payable)
- `swapTokensForExactTokens(uint256, uint256, address[], address, uint256)`

### Liquidity Management
- `addLiquidity(...) → (uint256, uint256, uint256)`
- `removeLiquidity(...) → (uint256, uint256)`

## Best Practices

1. **Use checksummed addresses** (EIP-55) in `contracts.json`
2. **Verify ABIs** from official sources (BSCScan verified contracts)
3. **Test in testnet first** before enabling on mainnet
4. **Document custom contracts** with clear descriptions
5. **Keep ABIs minimal** - only include functions you need

## Troubleshooting

### Tool not generating?
- Check `enabled: true` in `contracts.json`
- Verify ABI file exists at correct path
- Check server logs for parsing errors
- Ensure valid JSON format

### Transaction failing?
- Verify gas price and limit
- Check token approvals for DEX operations
- Ensure sufficient balance
- Review contract requirements (deadline, slippage, etc.)

## Security Notes

⚠️ **Important**:
- Always verify contract addresses from official sources
- Be cautious with `approve()` - limits max approval amount
- Test with small amounts first
- Use slippage protection for swaps
- Set appropriate deadlines for time-sensitive operations

## Future Chains

Planned support:
- ✅ BSC (Binance Smart Chain) - **ACTIVE**
- ⏳ Ethereum Mainnet
- ⏳ Polygon (Matic)
- ⏳ Arbitrum
- ⏳ Optimism
- ⏳ Avalanche C-Chain

---

**Dynamic Tool Generation**: Enabled
**Status**: ✅ Production Ready
**Last Updated**: 2026-01-27
