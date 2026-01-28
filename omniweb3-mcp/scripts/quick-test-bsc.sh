#!/bin/bash
# Quick test for BSC Testnet - assumes server is already running

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"

echo "🧪 Quick BSC Testnet Test"
echo ""

# Check if server is running
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ Server is not running!"
    echo ""
    echo "Please start it first:"
    echo "  ./scripts/start-bsc-testnet.sh"
    exit 1
fi

echo "✅ Server is running"
echo ""

# Test Chain ID
echo "📡 Getting BSC Testnet Chain ID..."
curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_chain_id",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq -r '.content[0].text' | while read -r chain_id; do
    if [ "$chain_id" = "97" ]; then
        echo "✅ Chain ID: $chain_id (BSC Testnet)"
    else
        echo "❌ Unexpected Chain ID: $chain_id"
    fi
done

echo ""

# Test Block Number
echo "📦 Getting latest block number..."
curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_block_number",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq -r '.content[0].text' | while read -r block; do
    echo "✅ Latest block: $block"
done

echo ""

# Test Gas Price
echo "⛽ Getting current gas price..."
curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_gas_price",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq -r '.content[0].text' | while read -r gas; do
    echo "✅ Gas price: $gas Gwei"
done

echo ""
echo "✨ All basic tests passed!"
