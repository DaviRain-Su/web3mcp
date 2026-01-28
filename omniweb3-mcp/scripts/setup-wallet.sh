#!/bin/bash
# Interactive wallet setup script

set -e

echo ""
echo "================================================"
echo "  🔐 EVM Wallet Configuration Setup"
echo "================================================"
echo ""

# Check if config already exists
if [ -f ~/.config/evm/keyfile.json ]; then
    echo "⚠️  Existing wallet configuration found!"
    echo "   Location: ~/.config/evm/keyfile.json"
    echo ""
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""
fi

echo "Choose configuration method:"
echo ""
echo "  1. Create new keyfile (recommended)"
echo "  2. Use environment variable"
echo "  3. Exit"
echo ""

read -p "Enter choice (1-3): " -n 1 -r
echo ""

case $REPLY in
    1)
        echo ""
        echo "📝 Creating keyfile configuration..."
        echo ""

        # Get private key
        read -sp "Enter your EVM private key (with 0x prefix): " PRIVATE_KEY
        echo ""

        # Validate private key format
        if [[ ! $PRIVATE_KEY =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            echo ""
            echo "❌ Invalid private key format!"
            echo "   Format: 0x + 64 hex characters"
            echo "   Example: 0x1234...abcd (66 chars total)"
            exit 1
        fi

        # Optional: Get address
        read -p "Enter your wallet address (optional, for documentation): " ADDRESS

        # Optional: Get description
        read -p "Enter wallet description (optional): " DESCRIPTION

        # Create directory
        mkdir -p ~/.config/evm

        # Create keyfile
        if [ -n "$ADDRESS" ] || [ -n "$DESCRIPTION" ]; then
            cat > ~/.config/evm/keyfile.json << EOF
{
  "private_key": "$PRIVATE_KEY",
  "address": "$ADDRESS",
  "description": "$DESCRIPTION"
}
EOF
        else
            cat > ~/.config/evm/keyfile.json << EOF
{
  "private_key": "$PRIVATE_KEY"
}
EOF
        fi

        # Set permissions
        chmod 600 ~/.config/evm/keyfile.json

        echo ""
        echo "✅ Keyfile created successfully!"
        echo "   Location: ~/.config/evm/keyfile.json"
        echo "   Permissions: 600 (read/write for owner only)"
        echo ""
        echo "⚠️  IMPORTANT: Keep this file secure and never share it!"
        ;;

    2)
        echo ""
        echo "📝 Setting up environment variable..."
        echo ""

        # Get private key
        read -sp "Enter your EVM private key (with 0x prefix): " PRIVATE_KEY
        echo ""

        # Validate private key format
        if [[ ! $PRIVATE_KEY =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            echo ""
            echo "❌ Invalid private key format!"
            echo "   Format: 0x + 64 hex characters"
            echo "   Example: 0x1234...abcd (66 chars total)"
            exit 1
        fi

        # Add to .env file
        if [ ! -f .env.bsc-testnet ]; then
            cp .env.example .env.bsc-testnet
        fi

        # Check if EVM_PRIVATE_KEY already exists
        if grep -q "^EVM_PRIVATE_KEY=" .env.bsc-testnet; then
            # Update existing line
            sed -i.bak "s|^EVM_PRIVATE_KEY=.*|EVM_PRIVATE_KEY=\"$PRIVATE_KEY\"|" .env.bsc-testnet
            rm .env.bsc-testnet.bak 2>/dev/null || true
        else
            # Add new line
            echo "" >> .env.bsc-testnet
            echo "# EVM Wallet Configuration" >> .env.bsc-testnet
            echo "EVM_PRIVATE_KEY=\"$PRIVATE_KEY\"" >> .env.bsc-testnet
        fi

        echo ""
        echo "✅ Environment variable added to .env.bsc-testnet"
        echo ""
        echo "To use it, run:"
        echo "  source .env.bsc-testnet"
        echo "  ./scripts/start-bsc-testnet.sh"
        ;;

    3)
        echo "Cancelled."
        exit 0
        ;;

    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

echo ""
echo "================================================"
echo "  ✨ Configuration Complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Get test BNB: https://testnet.bnbchain.org/faucet-smart"
echo "  2. Start server: ./scripts/start-bsc-testnet.sh"
echo "  3. Test wallet: ./scripts/test-wallet.sh"
echo ""
