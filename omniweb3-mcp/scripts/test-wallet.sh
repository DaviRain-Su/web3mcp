#!/bin/bash
# Test wallet configuration and functionality

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"

echo ""
echo "================================================"
echo "  🧪 Testing Wallet Configuration"
echo "================================================"
echo ""

# Check server
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ Server is not running!"
    echo ""
    echo "Please start it first:"
    echo "  ./scripts/start-bsc-testnet.sh"
    exit 1
fi

echo "✅ Server is running"
echo ""

# Test wallet_status tool
echo "📝 Getting wallet status..."
WALLET_STATUS=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "wallet_status",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "wallet_type": "local"
    }
  }')

echo "$WALLET_STATUS" | jq '.'
echo ""

# Extract address from response
ADDRESS=$(echo "$WALLET_STATUS" | jq -r '.content[0].text' | grep -oE '0x[a-fA-F0-9]{40}' | head -1)

if [ -n "$ADDRESS" ]; then
    echo "✅ Wallet address: $ADDRESS"
    echo ""

    # Test balance
    echo "💰 Checking balance..."
    BALANCE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"evm_get_balance\",
        \"arguments\": {
          \"chain\": \"bsc\",
          \"network\": \"testnet\",
          \"address\": \"$ADDRESS\"
        }
      }" | jq -r '.content[0].text')

    echo "Balance: $BALANCE wei"

    # Convert to BNB (wei / 10^18)
    if command -v bc &> /dev/null; then
        BNB=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc)
        echo "         $BNB tBNB"
    fi

    echo ""

    if [ "$BALANCE" = "0" ]; then
        echo "⚠️  Balance is 0. Get test BNB from:"
        echo "   https://testnet.bnbchain.org/faucet-smart"
    else
        echo "✅ Wallet is funded and ready to use!"
    fi
else
    echo "❌ Failed to get wallet address"
    echo ""
    echo "Please check your wallet configuration:"
    echo "  1. Environment variable: EVM_PRIVATE_KEY"
    echo "  2. Config file: ~/.config/evm/keyfile.json"
    echo ""
    echo "Run setup script: ./scripts/setup-wallet.sh"
fi

echo ""
echo "================================================"
echo "  Configuration Check"
echo "================================================"
echo ""

# Check keyfile
if [ -f ~/.config/evm/keyfile.json ]; then
    echo "✅ Keyfile: ~/.config/evm/keyfile.json"

    # Check permissions
    if [ "$(uname)" = "Darwin" ]; then
        PERMS=$(stat -f "%OLp" ~/.config/evm/keyfile.json)
    else
        PERMS=$(stat -c "%a" ~/.config/evm/keyfile.json)
    fi

    if [ "$PERMS" = "600" ]; then
        echo "   Permissions: ✅ 600 (secure)"
    else
        echo "   Permissions: ⚠️  $PERMS (should be 600)"
        echo "   Fix: chmod 600 ~/.config/evm/keyfile.json"
    fi
else
    echo "⚠️  Keyfile not found: ~/.config/evm/keyfile.json"
fi

echo ""

# Check environment variable
if [ -n "$EVM_PRIVATE_KEY" ]; then
    echo "✅ EVM_PRIVATE_KEY: Set (${#EVM_PRIVATE_KEY} chars)"
else
    echo "⚠️  EVM_PRIVATE_KEY: Not set"
fi

echo ""
echo "================================================"
echo ""
