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
  echo "Processing $file..."
  
  # 1. Replace process import with secure_http
  sed -i '' 's/const process = std.process;/const secure_http = @import("..\/..\/..\/..\/..\/..\/core\/secure_http.zig");/' "$file"
  
  # 2. Replace api_key parameter with use_api_key
  sed -i '' 's/const api_key = mcp.tools.getString(args, "api_key");/const use_api_key = true; \/\/ Always use API key from environment variable/' "$file"
  
  # 3. Replace fetchHttp call with secure_http.secureGet
  sed -i '' 's/fetchHttp(allocator, url, api_key, insecure)/secure_http.secureGet(allocator, url, use_api_key, insecure)/' "$file"
  
  # 4. Find line number where fn fetchHttp starts
  line_num=$(grep -n "^fn fetchHttp" "$file" | cut -d: -f1)
  
  if [ -n "$line_num" ]; then
    # Delete from "fn fetchHttp" to end of file
    sed -i '' "${line_num},\$d" "$file"
    echo "  ✓ Removed fetchHttp and fetchViaCurl functions"
  fi
done

echo ""
echo "Done! Fixed ${#files[@]} files"
