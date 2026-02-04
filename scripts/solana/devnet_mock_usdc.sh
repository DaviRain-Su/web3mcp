#!/usr/bin/env bash
set -euo pipefail

# Deploy or reuse a mock USDC SPL mint on Solana devnet and mint test tokens to your wallet.
# This is meant for demo/hackathon purposes where devnet USDC availability is uncertain.
#
# Requirements:
# - solana CLI installed
# - spl-token CLI installed
# - funded devnet SOL for fees
#
# Usage:
#   bash scripts/solana/devnet_mock_usdc.sh
#
# Outputs:
# - Prints the mint address
# - Mints MOCK_USDC_AMOUNT (default: 1000) to your associated token account

NETWORK="devnet"
DECIMALS="6"
SYMBOL="MOCKUSDC"
NAME="Mock USDC"
AMOUNT_UI="${MOCK_USDC_AMOUNT:-1000}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT_DIR/.cache/solana"
STATE_FILE="$STATE_DIR/mock_usdc_mint_${NETWORK}.txt"

mkdir -p "$STATE_DIR"

solana config set --url "$NETWORK" >/dev/null

OWNER="$(solana address)"

if [[ -f "$STATE_FILE" ]]; then
  MINT="$(cat "$STATE_FILE" | tr -d '\n' | tr -d ' ')"
else
  echo "[mock-usdc] Creating SPL token mint on $NETWORK (decimals=$DECIMALS)..."
  # Create mint; parse output like: "Creating token ..." + "Address: <mint>"
  OUT="$(spl-token create-token --decimals "$DECIMALS")"
  MINT="$(echo "$OUT" | awk '/Address:/{print $2}' | tail -n 1)"
  if [[ -z "$MINT" ]]; then
    echo "$OUT"
    echo "Failed to parse mint address from spl-token output" >&2
    exit 1
  fi
  echo "$MINT" > "$STATE_FILE"
fi

echo "[mock-usdc] Mint: $MINT"

# Create ATA if needed
spl-token create-account "$MINT" >/dev/null 2>&1 || true

echo "[mock-usdc] Minting $AMOUNT_UI to owner=$OWNER ..."
spl-token mint "$MINT" "$AMOUNT_UI" >/dev/null

echo "[mock-usdc] Done."
echo "MINT=$MINT"
