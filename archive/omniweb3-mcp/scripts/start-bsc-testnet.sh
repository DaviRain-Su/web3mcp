#!/bin/bash
# Start MCP Server for BSC Testnet Testing

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load environment variables
if [ -f .env.bsc-testnet ]; then
    export $(cat .env.bsc-testnet | grep -v '^#' | xargs)
    echo "✓ Loaded BSC testnet configuration"
else
    echo "⚠ Warning: .env.bsc-testnet not found, using defaults"
fi

# Build the project
echo "Building omniweb3-mcp..."
zig build || {
    echo "❌ Build failed"
    exit 1
}

# Display info to stderr (in case used with MCP)
{
    echo ""
    echo "=========================================================="
    echo "  🚀 Starting Omniweb3 MCP - Multi-Chain Mode"
    echo "=========================================================="
    echo ""
    echo "Configuration:"
    echo "  Host: ${HOST:-127.0.0.1}"
    echo "  Port: ${PORT:-8765}"
    echo "  Workers: ${MCP_WORKERS:-4}"
    echo "  Dynamic Tools: Smart Mode (discover + call)"
    echo ""
    echo "📊 Supported Networks:"
    echo ""
    echo "  🔷 EVM Chains (Primary: BSC Testnet)"
    echo "    • BSC Testnet (Chain ID: 97)"
    echo "      RPC: https://data-seed-prebsc-1-s1.binance.org:8545"
    echo "      Explorer: https://testnet.bscscan.com"
    echo "      Faucet: https://testnet.bnbchain.org/faucet-smart"
    echo "    • Ethereum (mainnet/testnet)"
    echo "    • Polygon (mainnet/testnet)"
    echo "    • Avalanche (mainnet/testnet)"
    echo ""
    echo "  🌞 Solana Networks (All Available)"
    echo "    • Mainnet-beta (default)"
    echo "    • Devnet"
    echo "    • Testnet"
    echo ""
    echo "🔧 Dynamic Features:"
    echo "  • EVM: discover_contracts + call_contract"
    echo "  • Solana: discover_programs + call_program"
    echo ""
    echo "Server URL: http://${HOST:-127.0.0.1}:${PORT:-8765}"
    echo "Press Ctrl+C to stop the server"
    echo "=========================================================="
    echo ""
} >&2

# Run the server
./zig-out/bin/omniweb3-mcp
