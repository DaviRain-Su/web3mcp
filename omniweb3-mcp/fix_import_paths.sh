#!/bin/bash

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

for file in "${files[@]}"; do
  echo "Fixing $file..."
  
  # Fix import path - use 6 ../ not 7
  sed -i '' 's|../../../../../../core/secure_http.zig|../../../../../core/secure_http.zig|g' "$file"
  
  # Fix any remaining fetchHttp calls
  sed -i '' 's/fetchHttp(allocator, /secure_http.secureGet(allocator, /g' "$file"
  sed -i '' 's/, api_key, insecure)/, use_api_key, insecure)/g' "$file"
done

echo "Done!"
