#!/bin/bash
# Download Solana program IDLs from various sources

set -e

IDL_DIR="idl_registry"
mkdir -p "$IDL_DIR"

echo "=================================================="
echo "  Downloading Solana Program IDLs"
echo "=================================================="
echo ""

# Function to download from Solana FM API
download_from_solanafm() {
    local program_id=$1
    local name=$2

    echo "📥 Downloading $name IDL from Solana FM..."
    curl -s "https://api.solanafm.com/v0/accounts/$program_id/idl" \
        -o "$IDL_DIR/${program_id}.json"

    if [ -s "$IDL_DIR/${program_id}.json" ]; then
        # Check if it's valid JSON
        if jq empty "$IDL_DIR/${program_id}.json" 2>/dev/null; then
            echo "✅ $name IDL downloaded successfully"
            return 0
        else
            echo "❌ $name: Invalid JSON, removing..."
            rm "$IDL_DIR/${program_id}.json"
            return 1
        fi
    else
        echo "❌ $name: Download failed (empty file)"
        rm "$IDL_DIR/${program_id}.json" 2>/dev/null || true
        return 1
    fi
}

# Function to download from Anchor registry
download_from_anchor() {
    local program_id=$1
    local name=$2

    echo "📥 Downloading $name IDL from Anchor registry..."
    curl -s "https://anchor.projectserum.com/api/idl/$program_id" \
        -o "$IDL_DIR/${program_id}.json"

    if [ -s "$IDL_DIR/${program_id}.json" ] && jq empty "$IDL_DIR/${program_id}.json" 2>/dev/null; then
        echo "✅ $name IDL downloaded successfully"
        return 0
    else
        rm "$IDL_DIR/${program_id}.json" 2>/dev/null || true
        return 1
    fi
}

echo "1️⃣ Jupiter v6"
echo "────────────────────────────────────────────────"
if [ -f "$IDL_DIR/JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4.json" ]; then
    echo "✅ Already exists, skipping..."
else
    download_from_solanafm "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4" "Jupiter v6" || \
    download_from_anchor "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4" "Jupiter v6" || \
    echo "⚠️  Failed to download Jupiter v6 IDL"
fi
echo ""

echo "2️⃣ Metaplex Token Metadata"
echo "────────────────────────────────────────────────"
if [ -f "$IDL_DIR/metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s.json" ]; then
    echo "✅ Already exists, skipping..."
else
    # Try Metaplex official GitHub
    echo "📥 Downloading from Metaplex GitHub..."
    curl -s "https://raw.githubusercontent.com/metaplex-foundation/mpl-token-metadata/main/programs/token-metadata/target/idl/mpl_token_metadata.json" \
        -o "$IDL_DIR/metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s.json"

    if [ -s "$IDL_DIR/metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s.json" ]; then
        echo "✅ Metaplex IDL downloaded successfully"
    else
        rm "$IDL_DIR/metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s.json" 2>/dev/null || true
        echo "⚠️  Failed to download Metaplex IDL"
    fi
fi
echo ""

echo "3️⃣ Raydium AMM v4"
echo "────────────────────────────────────────────────"
if [ -f "$IDL_DIR/675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8.json" ]; then
    echo "✅ Already exists, skipping..."
else
    download_from_solanafm "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8" "Raydium AMM v4" || \
    download_from_anchor "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8" "Raydium AMM v4" || \
    echo "⚠️  Failed to download Raydium IDL"
fi
echo ""

echo "4️⃣ Orca Whirlpool"
echo "────────────────────────────────────────────────"
if [ -f "$IDL_DIR/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json" ]; then
    echo "✅ Already exists, skipping..."
else
    # Try Orca official GitHub
    echo "📥 Downloading from Orca GitHub..."
    curl -s "https://raw.githubusercontent.com/orca-so/whirlpools/main/programs/whirlpool/target/idl/whirlpool.json" \
        -o "$IDL_DIR/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json"

    if [ -s "$IDL_DIR/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json" ]; then
        echo "✅ Orca Whirlpool IDL downloaded successfully"
    else
        rm "$IDL_DIR/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json" 2>/dev/null || true
        download_from_solanafm "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc" "Orca Whirlpool" || \
        download_from_anchor "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc" "Orca Whirlpool" || \
        echo "⚠️  Failed to download Orca Whirlpool IDL"
    fi
fi
echo ""

echo "5️⃣ Marinade Finance"
echo "────────────────────────────────────────────────"
if [ -f "$IDL_DIR/MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD.json" ]; then
    echo "✅ Already exists, skipping..."
else
    # Try Marinade official GitHub
    echo "📥 Downloading from Marinade GitHub..."
    curl -s "https://raw.githubusercontent.com/marinade-finance/liquid-staking-program/main/programs/marinade-finance/target/idl/marinade_finance.json" \
        -o "$IDL_DIR/MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD.json"

    if [ -s "$IDL_DIR/MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD.json" ]; then
        echo "✅ Marinade IDL downloaded successfully"
    else
        rm "$IDL_DIR/MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD.json" 2>/dev/null || true
        download_from_solanafm "MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD" "Marinade Finance" || \
        download_from_anchor "MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD" "Marinade Finance" || \
        echo "⚠️  Failed to download Marinade IDL"
    fi
fi
echo ""

echo "=================================================="
echo "  Summary"
echo "=================================================="
echo ""
echo "Downloaded IDLs:"
ls -lh "$IDL_DIR"/*.json 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "Total IDL files: $(ls "$IDL_DIR"/*.json 2>/dev/null | wc -l)"
echo ""
echo "✅ Done!"
