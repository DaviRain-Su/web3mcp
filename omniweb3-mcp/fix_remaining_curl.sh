#!/bin/bash

# List of files that still use curl
files=(
  "src/tools/solana/defi/jupiter/ultra/get_routers.zig"
  "src/tools/solana/defi/jupiter/ultra/ultra_search.zig"
  "src/tools/solana/defi/jupiter/ultra/get_holdings.zig"
  "src/tools/solana/defi/jupiter/ultra/get_balances.zig"
  "src/tools/solana/defi/jupiter/ultra/get_shield.zig"
  "src/tools/solana/defi/jupiter/swap/get_program_labels.zig"
  "src/tools/solana/defi/jupiter/portfolio/get_platforms.zig"
  "src/tools/solana/defi/jupiter/portfolio/get_positions.zig"
  "src/tools/solana/defi/jupiter/portfolio/get_staked_jup.zig"
  "src/tools/solana/defi/jupiter/tokens/get_tokens_by_tag.zig"
  "src/tools/solana/defi/jupiter/tokens/get_tokens_by_category.zig"
  "src/tools/solana/defi/jupiter/tokens/get_recent_tokens.zig"
  "src/tools/solana/defi/jupiter/recurring/get_recurring_orders.zig"
)

echo "Found ${#files[@]} files with curl dependencies"
for file in "${files[@]}"; do
  echo "  - $file"
done
