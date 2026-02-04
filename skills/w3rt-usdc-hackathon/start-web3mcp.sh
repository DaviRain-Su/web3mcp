#!/usr/bin/env bash
set -euo pipefail

# Simple launcher for the web3mcp W3RT server (hackathon demo)
# - Builds release
# - Runs the server

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR/web3mcp"

echo "[w3rt-usdc-hackathon] Building web3mcp (release)..."
cargo build --release

echo "[w3rt-usdc-hackathon] Starting web3mcp..."
./target/release/web3mcp
