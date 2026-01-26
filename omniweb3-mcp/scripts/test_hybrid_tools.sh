#!/bin/bash
# Test script for hybrid architecture (static + dynamic tools)
# Tests both old REST API tools and new dynamically generated tools

set -e

echo "════════════════════════════════════════════════════════"
echo "  Testing Hybrid MCP Architecture"
echo "  Static Tools (REST API) + Dynamic Tools (IDL)"
echo "════════════════════════════════════════════════════════"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
HOST="${HOST:-localhost}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"

# Check if server is running
check_server() {
    echo -n "Checking if MCP server is running... "
    if curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Server is running${NC}"
        return 0
    else
        echo -e "${RED}✗ Server is not running${NC}"
        echo ""
        echo "Please start the server with:"
        echo "  zig build run"
        echo ""
        echo "Or with dynamic tools enabled:"
        echo "  ENABLE_DYNAMIC_TOOLS=true zig build run"
        return 1
    fi
}

# Test static tools
test_static_tools() {
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "1. Testing Static Tools (Old REST API Wrappers)"
    echo "────────────────────────────────────────────────────────"

    echo -n "Counting static tools... "
    STATIC_COUNT=$(curl -s "${BASE_URL}/tools" | jq '[.tools[] | select(.name | startswith("get_") or startswith("submit_") or startswith("fetch_"))] | length' 2>/dev/null || echo "0")

    if [ "$STATIC_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found ${STATIC_COUNT} static tools${NC}"
    else
        echo -e "${YELLOW}⚠ No static tools found${NC}"
    fi

    # List some example static tools
    echo ""
    echo "Example static tools:"
    curl -s "${BASE_URL}/tools" | jq -r '.tools[] | select(.name | startswith("get_jupiter") or startswith("submit_jupiter")) | "  - \(.name)"' 2>/dev/null | head -10
}

# Test dynamic tools
test_dynamic_tools() {
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "2. Testing Dynamic Tools (Jupiter IDL-generated)"
    echo "────────────────────────────────────────────────────────"

    echo -n "Counting dynamic tools... "
    DYNAMIC_COUNT=$(curl -s "${BASE_URL}/tools" | jq '[.tools[] | select(.name | startswith("jupiter_") and (.name | startswith("jupiter_v6") | not))] | length' 2>/dev/null || echo "0")

    if [ "$DYNAMIC_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found ${DYNAMIC_COUNT} dynamic tools${NC}"
    else
        echo -e "${YELLOW}⚠ No dynamic tools found${NC}"
        echo ""
        echo "Dynamic tools may be disabled. Try:"
        echo "  ENABLE_DYNAMIC_TOOLS=true zig build run"
        return 1
    fi

    # List dynamic tools
    echo ""
    echo "Dynamic tools from Jupiter v6 IDL:"
    curl -s "${BASE_URL}/tools" | jq -r '.tools[] | select(.name | startswith("jupiter_") and (.name | startswith("jupiter_v6") | not)) | "  ✓ \(.name) - \(.description)"' 2>/dev/null
}

# Test tool execution
test_tool_execution() {
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "3. Testing Tool Execution"
    echo "────────────────────────────────────────────────────────"

    # Test a static tool (ping)
    echo ""
    echo -n "Testing static tool (ping)... "
    PING_RESULT=$(curl -s -X POST "${BASE_URL}/tool/ping" -H "Content-Type: application/json" -d '{}' 2>/dev/null)

    if echo "$PING_RESULT" | jq -e '.content[0].text' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Success${NC}"
        echo "  Response: $(echo "$PING_RESULT" | jq -r '.content[0].text' | head -1)"
    else
        echo -e "${RED}✗ Failed${NC}"
        echo "$PING_RESULT" | jq '.' 2>/dev/null || echo "$PING_RESULT"
    fi

    # Check if dynamic tools are available
    if [ "$DYNAMIC_COUNT" -gt 0 ]; then
        echo ""
        echo "Testing dynamic tool (requires proper parameters)..."
        echo "Note: Dynamic tools generate unsigned transactions"
        echo "      Full testing requires valid Solana addresses"
    fi
}

# Summary
show_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  Summary"
    echo "════════════════════════════════════════════════════════"

    TOTAL_COUNT=$(curl -s "${BASE_URL}/tools" | jq '.tools | length' 2>/dev/null || echo "0")

    echo "Total tools registered: ${TOTAL_COUNT}"
    echo "  - Static tools:  ${STATIC_COUNT}"
    echo "  - Dynamic tools: ${DYNAMIC_COUNT}"
    echo ""

    if [ "$DYNAMIC_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Hybrid architecture is working!${NC}"
        echo ""
        echo "Both static (REST API) and dynamic (IDL-generated) tools"
        echo "are available for AI agents to use."
    else
        echo -e "${YELLOW}⚠ Only static tools are active${NC}"
        echo ""
        echo "To enable dynamic tools:"
        echo "  ENABLE_DYNAMIC_TOOLS=true zig build run"
    fi

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "Next steps:"
    echo "  1. View all tools: curl ${BASE_URL}/tools | jq"
    echo "  2. Call a tool:    curl -X POST ${BASE_URL}/tool/<name> -d '{...}'"
    echo "  3. Check logs:     Look for 'Hybrid Tool Registry' in server output"
    echo "════════════════════════════════════════════════════════"
}

# Main execution
main() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
        exit 1
    fi

    if ! check_server; then
        exit 1
    fi

    test_static_tools
    test_dynamic_tools
    test_tool_execution
    show_summary
}

main
