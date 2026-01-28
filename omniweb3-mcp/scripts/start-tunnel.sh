#!/bin/bash
set -e

echo "🌐 Starting cloudflared tunnel for omniweb3-mcp..."
echo ""
echo "This will create a temporary HTTPS URL that forwards to http://127.0.0.1:8765"
echo "The tunnel will run until you press Ctrl+C"
echo ""
echo "============================================"
echo ""

# Start cloudflared tunnel (temporary, no login required)
cloudflared tunnel --url http://127.0.0.1:8765

# When stopped:
echo ""
echo "Tunnel stopped."
