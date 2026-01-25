# Test Scripts

This directory contains test scripts for the omniweb3-mcp server.

## Scripts

### `solana_devnet_test.py`
Tests Solana devnet functionality using stdio MCP transport (local server).

**Requirements:**
- Built binary: `./zig-out/bin/omniweb3-mcp`
- Solana CLI tools installed
- Environment variables in `.env`:
  - `SOLANA_ADDRESS` - Your test wallet address
  - Optional: `JUPITER_API_KEY`, `SOLANA_RPC_ENDPOINT`

**Usage:**
```bash
./build_linux.sh  # or zig build
python3 scripts/solana_devnet_test.py
```

### `solana_mainnet_test.py`
Tests Solana mainnet functionality using HTTP MCP transport (remote server).

**Requirements:**
- Deployed HTTP MCP server (e.g., https://api.web3mcp.app)
- Bearer token for authentication
- Environment variables in `.env`:
  - `WEB3MCP_ACCESS_TOKEN` - **Required** Bearer token for HTTP auth
  - `WEB3MCP_API_URL` - Optional, defaults to https://api.web3mcp.app
  - `PRIVY_WALLET_ID` - Optional, for Privy wallet tests
  - `SOLANA_ADDRESS` - Optional, for account/transaction tests

**Usage:**
```bash
# Set access token (required)
export WEB3MCP_ACCESS_TOKEN="your-jwt-token-here"

# Optional: Set wallet info
export PRIVY_WALLET_ID="v1xxxxxxxxxxx"
export SOLANA_ADDRESS="YourSolanaAddressHere"

# Run tests
python3 scripts/solana_mainnet_test.py
```

**What it tests:**
- ✅ Network Status APIs (slot, epoch, version, etc.)
- ✅ Account & Transaction APIs (balance, signatures, transactions)
- ✅ Token APIs (supply, largest holders)
- ✅ Jupiter Price & Quote APIs
- ✅ Jupiter DeFi APIs (search tokens, lend, trigger orders)
- ✅ Privy Wallet APIs (list wallets, get balance)
- ✅ Block APIs (block time)

### `evm_anvil_test.py`
Tests EVM functionality using local Anvil node.

**Requirements:**
- Built binary: `./zig-out/bin/omniweb3-mcp`
- Anvil (from Foundry) installed
- Environment variables in `.env`

**Usage:**
```bash
./build_linux.sh  # or zig build
python3 scripts/evm_anvil_test.py
```

## Environment Setup

1. Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

2. Fill in your credentials:
```bash
# For Privy wallet functionality
PRIVY_APP_ID=your-app-id
PRIVY_APP_SECRET=your-app-secret

# For Jupiter API
JUPITER_API_KEY=your-jupiter-key

# For HTTP MCP testing (mainnet)
WEB3MCP_ACCESS_TOKEN=your-bearer-token
WEB3MCP_API_URL=https://api.web3mcp.app
PRIVY_WALLET_ID=your-wallet-id
SOLANA_ADDRESS=your-test-address
```

## Getting Your Access Token

For `solana_mainnet_test.py`, you need a Bearer token to authenticate with the HTTP MCP server.

**Option 1: Using Privy Session (Recommended)**
```bash
# The token is your Privy session JWT
# Get it from your authentication flow
export WEB3MCP_ACCESS_TOKEN="eyJhbGciOiJFUzI1NiIsInR5cCI..."
```

**Option 2: Check Server Logs**
If you have access to the server, check the Authorization header from successful requests.

**Security Note:**
- Never commit `.env` file to git
- Keep your access tokens secure
- Tokens may expire - refresh as needed

## Troubleshooting

### "WEB3MCP_ACCESS_TOKEN environment variable is required"
You forgot to set the access token:
```bash
export WEB3MCP_ACCESS_TOKEN="your-token"
```

### "HTTP 401 - Unauthorized"
Your access token is invalid or expired. Get a fresh token.

### "Tool not found"
The server may not have that tool enabled. Check:
```bash
curl -X POST https://api.web3mcp.app/ \
  -H "Authorization: Bearer $WEB3MCP_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq '.result.tools[].name'
```

### Tests timeout
The server might be slow or down. Check:
1. Server is running: `curl https://api.web3mcp.app/health`
2. Your network connection
3. Firewall settings

## CI/CD Integration

These scripts can be used in CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run mainnet tests
  env:
    WEB3MCP_ACCESS_TOKEN: ${{ secrets.WEB3MCP_TOKEN }}
    PRIVY_WALLET_ID: ${{ secrets.PRIVY_WALLET_ID }}
  run: python3 scripts/solana_mainnet_test.py
```

## Contributing

When adding new APIs:
1. Add tests to the appropriate script
2. Update this README
3. Ensure tests pass before merging
