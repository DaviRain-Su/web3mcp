#!/bin/bash
# Omniweb3 Smart MCP Launcher

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Display startup info to stderr (MCP uses stdout for JSON-RPC)
{
    echo ""
    echo "=========================================================="
    echo "  🚀 Starting Omniweb3 Smart MCP Server"
    echo "=========================================================="
    echo ""
    echo "📊 Multi-Chain Support:"
    echo ""
    echo "  🔷 EVM Chains:"
    echo "    • Ethereum (mainnet/testnet)"
    echo "    • BSC (mainnet/testnet)"
    echo "    • Polygon (mainnet/testnet)"
    echo "    • Avalanche (mainnet/testnet)"
    echo ""
    echo "  🌞 Solana Networks:"
    echo "    • Mainnet-beta"
    echo "    • Devnet"
    echo "    • Testnet"
    echo ""
    echo "🔧 Smart Features:"
    echo "  • 178 built-in tools"
    echo "  • Dynamic contract discovery (EVM)"
    echo "  • Dynamic program discovery (Solana)"
    echo "  • Unified call interface"
    echo ""
    echo "=========================================================="
    echo ""
} >&2

exec "$PROJECT_DIR/zig-out/bin/omniweb3-mcp"
