#!/usr/bin/env bash
set -euo pipefail

: "${JUPITER_API_KEY:?Please set JUPITER_API_KEY}"
QUOTE_ENDPOINT="${JUPITER_API_ENDPOINT:-https://api.jup.ag/swap/v1/quote}"
PRICE_ENDPOINT="${JUPITER_PRICE_ENDPOINT:-https://api.jup.ag/price/v3}"
QUOTE_URL="${QUOTE_ENDPOINT}?inputMint=So11111111111111111111111111111111111111112&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&amount=1000000"
PRICE_URL="${PRICE_ENDPOINT}?ids=So11111111111111111111111111111111111111112"
CURL_INSECURE=""
if [ "${JUPITER_INSECURE:-0}" = "1" ]; then
  CURL_INSECURE="-k"
fi

echo "Quote response:"
QUOTE_BODY=$(mktemp)
QUOTE_STATUS=$(curl -sS -L ${CURL_INSECURE} -w "%{http_code}" -o "${QUOTE_BODY}" -H "x-api-key: ${JUPITER_API_KEY}" "${QUOTE_URL}") || true
echo "HTTP status: ${QUOTE_STATUS}"
if [ -s "${QUOTE_BODY}" ]; then
  cat "${QUOTE_BODY}"
else
  echo "(empty body)"
fi
rm -f "${QUOTE_BODY}"

echo
echo "Price response:"
PRICE_BODY=$(mktemp)
PRICE_STATUS=$(curl -sS -L ${CURL_INSECURE} -w "%{http_code}" -o "${PRICE_BODY}" -H "x-api-key: ${JUPITER_API_KEY}" "${PRICE_URL}") || true
echo "HTTP status: ${PRICE_STATUS}"
if [ -s "${PRICE_BODY}" ]; then
  cat "${PRICE_BODY}"
else
  echo "(empty body)"
fi
rm -f "${PRICE_BODY}"
echo
