#!/bin/bash
# Test BSC Testnet functionality via MCP Server

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo "================================================"
echo "  🧪 Testing BSC Testnet via MCP Server"
echo "================================================"
echo ""

# Test 1: Health Check
echo -e "${YELLOW}[1/5]${NC} Health Check..."
curl -s "${BASE_URL}/health" | jq '.' || {
    echo -e "${RED}❌ Server not responding${NC}"
    echo "Please start the server with: ./scripts/start-bsc-testnet.sh"
    exit 1
}
echo -e "${GREEN}✓ Server is healthy${NC}"
echo ""

# Test 2: List available tools
echo -e "${YELLOW}[2/5]${NC} Listing available EVM tools..."
curl -s "${BASE_URL}/mcp/v1/tools" | jq '.tools[] | select(.name | contains("evm"))' > /tmp/evm_tools.json
EVM_TOOLS_COUNT=$(jq length /tmp/evm_tools.json)
echo -e "${GREEN}✓ Found $EVM_TOOLS_COUNT EVM tools${NC}"
echo ""
echo "Available EVM tools:"
jq -r '.name' /tmp/evm_tools.json | head -10
echo ""

# Test 3: Get BSC Testnet Chain ID
echo -e "${YELLOW}[3/5]${NC} Getting BSC Testnet Chain ID..."
CHAIN_ID_RESULT=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_chain_id",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq '.')

echo "$CHAIN_ID_RESULT" | jq '.'

CHAIN_ID=$(echo "$CHAIN_ID_RESULT" | jq -r '.content[0].text' 2>/dev/null || echo "")
if [ "$CHAIN_ID" = "97" ]; then
    echo -e "${GREEN}✓ Chain ID is correct: 97 (BSC Testnet)${NC}"
else
    echo -e "${YELLOW}⚠ Chain ID: $CHAIN_ID${NC}"
fi
echo ""

# Test 4: Get latest block number
echo -e "${YELLOW}[4/5]${NC} Getting latest block number on BSC Testnet..."
BLOCK_RESULT=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_block_number",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq '.')

echo "$BLOCK_RESULT" | jq '.'

BLOCK_NUMBER=$(echo "$BLOCK_RESULT" | jq -r '.content[0].text' 2>/dev/null || echo "")
if [ -n "$BLOCK_NUMBER" ] && [ "$BLOCK_NUMBER" != "null" ]; then
    echo -e "${GREEN}✓ Latest block: $BLOCK_NUMBER${NC}"
else
    echo -e "${RED}❌ Failed to get block number${NC}"
fi
echo ""

# Test 5: Get gas price
echo -e "${YELLOW}[5/5]${NC} Getting current gas price on BSC Testnet..."
GAS_RESULT=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_gas_price",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq '.')

echo "$GAS_RESULT" | jq '.'

GAS_PRICE=$(echo "$GAS_RESULT" | jq -r '.content[0].text' 2>/dev/null || echo "")
if [ -n "$GAS_PRICE" ] && [ "$GAS_PRICE" != "null" ]; then
    echo -e "${GREEN}✓ Gas price: $GAS_PRICE Gwei${NC}"
else
    echo -e "${RED}❌ Failed to get gas price${NC}"
fi
echo ""

# Test 6: Check balance (example address - replace with your test address)
echo -e "${YELLOW}[Bonus]${NC} Checking balance of example address..."
echo "Note: Replace with your own address for real testing"
BALANCE_RESULT=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_balance",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "address": "0x0000000000000000000000000000000000000000"
    }
  }' | jq '.')

echo "$BALANCE_RESULT" | jq '.'
echo ""

echo "================================================"
echo -e "${GREEN}✓ BSC Testnet testing completed!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Get test BNB from faucet: https://testnet.bnbchain.org/faucet-smart"
echo "  2. Replace the example address with your test address"
echo "  3. Try more tools: evm_send_transfer, evm_estimate_gas, etc."
echo ""
