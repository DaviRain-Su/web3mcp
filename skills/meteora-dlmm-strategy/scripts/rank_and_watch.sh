#!/usr/bin/env bash
set -euo pipefail

# Placeholder script for future automation.
# Intentionally minimal: strategy layer should live outside the Rust server.
#
# Expected usage (conceptual):
#   - call web3mcp via your MCP client
#   - or use whatever harness you have to call the tool JSON-RPC

echo "TODO: wire this script to your MCP client harness (Claude Desktop / custom runner)."
echo "Suggested loop: rank_pairs(limit=50) -> pick candidates -> fill_template -> build_tx(create_pending=true)"
