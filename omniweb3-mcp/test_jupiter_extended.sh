#!/usr/bin/env bash
set -euo pipefail

API_KEY="${JUPITER_API_KEY:-}"
CURL_INSECURE=""
if [ "${JUPITER_INSECURE:-0}" = "1" ]; then
  CURL_INSECURE="-k"
fi

BASE_URL="https://api.jup.ag"
AUTH_HEADER=""
if [ -n "$API_KEY" ]; then
  AUTH_HEADER="-H x-api-key:${API_KEY}"
fi

echo "=== Extended Jupiter API Tests (Direct curl) ==="
echo ""

echo "1. Tokens Search (SOL)..."
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/tokens/v2/search?query=SOL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(f'   Found: {len(data)} tokens')
    for t in data[:3]:
        print(f'   - {t.get(\"symbol\",\"?\")} ({t.get(\"address\",\"?\")[:16]}...)')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "2. Tokens by Tag (verified)..."
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/tokens/v2/tag/verified" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(f'   Found: {len(data)} verified tokens')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "3. Recent Tokens..."
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/tokens/v2/recent" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(f'   Found: {len(data)} recent tokens')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "4. Program Labels..."
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/swap/v1/program-id-to-label" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, dict):
    print(f'   Found: {len(data)} DEX programs')
    for k, v in list(data.items())[:3]:
        print(f'   - {k[:16]}... = {v}')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "5. Ultra Shield (USDC safety)..."
USDC="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/ultra/v1/shield?mints=${USDC}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'   Response keys: {list(data.keys()) if isinstance(data, dict) else type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "6. Lend Tokens..."
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/lend/v1/earn/tokens" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(f'   Found: {len(data)} lend tokens')
elif isinstance(data, dict):
    print(f'   Response keys: {list(data.keys())}')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "7. Portfolio Platforms..."
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/portfolio/v1/platforms" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(f'   Found: {len(data)} platforms')
    for p in data[:3]:
        print(f'   - {p.get(\"name\",p.get(\"id\",\"?\"))}')
elif isinstance(data, dict):
    print(f'   Response keys: {list(data.keys())}')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "8. Ultra Balances (sample wallet)..."
WALLET="DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK"
curl -sS -L $CURL_INSECURE $AUTH_HEADER "${BASE_URL}/ultra/v1/balances?account=${WALLET}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(f'   Found: {len(data)} token balances')
elif isinstance(data, dict):
    print(f'   Response keys: {list(data.keys())}')
else:
    print(f'   Response type: {type(data).__name__}')
" 2>/dev/null || echo "   ERROR"
echo ""

echo "=== Tests Complete ==="
