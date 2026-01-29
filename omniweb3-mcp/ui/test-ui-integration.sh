#!/bin/bash
# Test UI integration with MCP server

set -e

echo "=== Testing omniweb3-mcp UI Integration ==="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Build Zig server
echo -e "${BLUE}1. Building Zig MCP server...${NC}"
cd "$(dirname "$0")/.."
zig build
echo -e "${GREEN}✓ Build successful${NC}"
echo ""

# Test get_transaction with UI metadata
echo -e "${BLUE}2. Testing get_transaction tool...${NC}"
./zig-out/bin/omniweb3-mcp <<'EOF' 2>&1 | tee /tmp/mcp-test-output.json | grep -o '"_meta":{[^}]*"resourceUri":"[^"]*"[^}]*}' && echo -e "${GREEN}✓ UI metadata found!${NC}" || echo "✗ No UI metadata"
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_transaction","arguments":{"chain":"bsc","tx_hash":"0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa","network":"testnet"}}}
EOF
echo ""

# Extract and display UI resource URI
echo -e "${BLUE}3. Extracted UI Resource URI:${NC}"
grep -o '"resourceUri":"[^"]*"' /tmp/mcp-test-output.json | sed 's/"resourceUri":"//; s/"$//' || echo "Not found"
echo ""

# Check UI build artifacts
echo -e "${BLUE}4. Checking UI build artifacts...${NC}"
if [ -f "ui/dist/src/transaction/index.html" ]; then
    echo -e "${GREEN}✓ Transaction Viewer HTML exists${NC}"
else
    echo "✗ Transaction Viewer HTML missing"
fi

if [ -f "ui/dist/src/swap/index.html" ]; then
    echo -e "${GREEN}✓ Swap Interface HTML exists${NC}"
else
    echo "✗ Swap Interface HTML missing"
fi

if [ -f "ui/dist/src/balance/index.html" ]; then
    echo -e "${GREEN}✓ Balance Dashboard HTML exists${NC}"
else
    echo "✗ Balance Dashboard HTML missing"
fi
echo ""

# Check UI bundle sizes
echo -e "${BLUE}5. UI Bundle Sizes:${NC}"
echo "Transaction Viewer:"
du -h ui/dist/src/transaction/index.html ui/dist/assets/transaction-*.js 2>/dev/null | awk '{print "  " $0}'
echo "Swap Interface:"
du -h ui/dist/src/swap/index.html ui/dist/assets/swap-*.js 2>/dev/null | awk '{print "  " $0}'
echo "Balance Dashboard:"
du -h ui/dist/src/balance/index.html ui/dist/assets/balance-*.js 2>/dev/null | awk '{print "  " $0}'
echo "Shared Styles:"
du -h ui/dist/assets/styles-*.{css,js} 2>/dev/null | awk '{print "  " $0}'
echo ""

# Summary
echo -e "${GREEN}=== Integration Test Complete ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Start UI dev server: cd ui && npm run dev"
echo "  2. View Transaction UI: http://localhost:5175/src/transaction/?mock=true"
echo "  3. View Swap UI: http://localhost:5175/src/swap/?mock=true"
echo "  4. View Balance UI: http://localhost:5175/src/balance/?mock=true"
echo "  5. Configure Claude Desktop with omniweb3-mcp server"
echo ""
