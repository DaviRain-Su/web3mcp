#!/usr/bin/env python3
"""
Solana Mainnet API Test Suite

Tests all Solana read-only APIs against mainnet using HTTP MCP transport.
Requires WEB3MCP_ACCESS_TOKEN environment variable for authentication.

Usage:
    export WEB3MCP_ACCESS_TOKEN="your-bearer-token"
    export WEB3MCP_API_URL="https://api.web3mcp.app"  # Optional
    export PRIVY_WALLET_ID="your-wallet-id"  # Optional
    python3 scripts/solana_mainnet_test.py
"""

import json
import os
import sys
import urllib.request
import urllib.error


def load_dotenv(path):
    """Load environment variables from .env file"""
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


# Configuration
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(ROOT_DIR, ".env"))

# Required: Access token for HTTP MCP
ACCESS_TOKEN = os.environ.get("WEB3MCP_ACCESS_TOKEN")
if not ACCESS_TOKEN:
    print("Error: WEB3MCP_ACCESS_TOKEN environment variable is required")
    print("Set it with: export WEB3MCP_ACCESS_TOKEN='your-token'")
    sys.exit(1)

# Configuration
API_URL = os.environ.get("WEB3MCP_API_URL", "https://api.web3mcp.app")
PRIVY_WALLET_ID = os.environ.get("PRIVY_WALLET_ID")
SOLANA_ADDRESS = os.environ.get("SOLANA_ADDRESS")

# Solana constants
SOL_MINT = "So11111111111111111111111111111111111111112"
USDT_MINT = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

# Test counters
tests_passed = 0
tests_failed = 0


def call_mcp(tool_name, arguments=None):
    """Call MCP tool via HTTP"""
    global tests_passed, tests_failed

    body = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": arguments or {}
        }
    }

    req = urllib.request.Request(
        API_URL + "/",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {ACCESS_TOKEN}"
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read().decode("utf-8")
            result = json.loads(data)

            # Check for errors
            if "error" in result:
                print(f"  ❌ {tool_name}: {result['error'].get('message', 'Unknown error')}")
                tests_failed += 1
                return None

            # Extract tool result
            content = result.get("result", {}).get("content", [])
            if not content:
                print(f"  ❌ {tool_name}: No content in response")
                tests_failed += 1
                return None

            text = content[0].get("text", "")
            is_error = result.get("result", {}).get("isError", False)

            if is_error:
                print(f"  ❌ {tool_name}: {text}")
                tests_failed += 1
                return None

            # Try to parse as JSON
            try:
                parsed = json.loads(text)
                print(f"  ✅ {tool_name}")
                tests_passed += 1
                return parsed
            except json.JSONDecodeError:
                print(f"  ✅ {tool_name}: {text[:100]}")
                tests_passed += 1
                return text

    except urllib.error.HTTPError as e:
        print(f"  ❌ {tool_name}: HTTP {e.code} - {e.reason}")
        tests_failed += 1
        return None
    except Exception as e:
        print(f"  ❌ {tool_name}: {str(e)}")
        tests_failed += 1
        return None


def test_network_apis():
    """Test Solana network status APIs"""
    print("\n=== Network Status APIs ===")

    call_mcp("get_slot", {"chain": "solana"})
    call_mcp("get_block_height", {"chain": "solana"})
    call_mcp("get_epoch_info", {"chain": "solana"})
    call_mcp("get_latest_blockhash", {"chain": "solana"})
    call_mcp("get_tps", {"chain": "solana", "limit": 5})
    call_mcp("get_version", {"chain": "solana"})
    call_mcp("get_supply", {"chain": "solana"})


def test_account_apis():
    """Test Solana account and transaction APIs"""
    print("\n=== Account & Transaction APIs ===")

    # Use Privy wallet address if available
    address = SOLANA_ADDRESS
    if PRIVY_WALLET_ID and not address:
        # Try to get wallet address from Privy
        result = call_mcp("privy_list_wallets")
        if result and "wallets" in result:
            for wallet in result["wallets"]:
                if wallet.get("id") == PRIVY_WALLET_ID and wallet.get("chain_type") == "solana":
                    address = wallet.get("address")
                    break

    if not address:
        print("  ⚠️  Skipping account tests: No SOLANA_ADDRESS or PRIVY_WALLET_ID")
        return

    print(f"  Using address: {address}")

    # Balance
    call_mcp("get_balance", {
        "chain": "solana",
        "address": address
    })

    # Transaction history
    sigs_result = call_mcp("get_signatures_for_address", {
        "chain": "solana",
        "address": address,
        "limit": 5
    })

    # Get transaction details if we have signatures
    if sigs_result and "signatures" in sigs_result:
        if sigs_result["signatures"]:
            first_sig = sigs_result["signatures"][0]["signature"]
            call_mcp("get_transaction", {
                "chain": "solana",
                "signature": first_sig
            })

    # Rent exemption
    call_mcp("get_minimum_balance_for_rent_exemption", {
        "chain": "solana",
        "data_len": 165
    })


def test_token_apis():
    """Test SPL token APIs"""
    print("\n=== Token APIs ===")

    # USDT supply
    call_mcp("get_token_supply", {
        "chain": "solana",
        "mint": USDT_MINT
    })

    # USDT largest holders (limit to avoid huge response)
    call_mcp("get_token_largest_accounts", {
        "chain": "solana",
        "mint": USDT_MINT
    })


def test_jupiter_price_apis():
    """Test Jupiter price and quote APIs"""
    print("\n=== Jupiter Price & Quote APIs ===")

    # SOL price
    call_mcp("get_jupiter_price", {
        "chain": "solana",
        "mint": SOL_MINT
    })

    # USDT price
    call_mcp("get_jupiter_price", {
        "chain": "solana",
        "mint": USDT_MINT
    })

    # Get quote for 0.1 SOL -> USDT
    call_mcp("get_jupiter_quote", {
        "chain": "solana",
        "input_mint": SOL_MINT,
        "output_mint": USDT_MINT,
        "amount": "100000000",
        "slippage_bps": 50
    })


def test_jupiter_defi_apis():
    """Test Jupiter DeFi APIs"""
    print("\n=== Jupiter DeFi APIs ===")

    # Search tokens
    call_mcp("search_jupiter_tokens", {
        "query": "USDT",
        "limit": 3
    })

    # Lend tokens
    call_mcp("get_jupiter_lend_tokens")

    # These require an account address
    if SOLANA_ADDRESS or PRIVY_WALLET_ID:
        address = SOLANA_ADDRESS
        if not address and PRIVY_WALLET_ID:
            # Get from Privy wallet
            result = call_mcp("privy_list_wallets")
            if result and "wallets" in result:
                for wallet in result["wallets"]:
                    if wallet.get("id") == PRIVY_WALLET_ID:
                        address = wallet.get("address")
                        break

        if address:
            # Lend positions
            call_mcp("get_jupiter_lend_positions", {
                "account": address
            })

            # Lend earnings
            call_mcp("get_jupiter_lend_earnings", {
                "account": address
            })

            # Trigger orders
            call_mcp("get_jupiter_trigger_orders", {
                "account": address,
                "status": "active"
            })


def test_privy_apis():
    """Test Privy wallet APIs"""
    print("\n=== Privy Wallet APIs ===")

    if not PRIVY_WALLET_ID:
        print("  ⚠️  Skipping Privy tests: No PRIVY_WALLET_ID set")
        return

    # List wallets
    result = call_mcp("privy_list_wallets")

    if result and "wallets" in result:
        for wallet in result["wallets"]:
            if wallet.get("chain_type") == "solana":
                wallet_id = wallet.get("id")
                address = wallet.get("address")
                print(f"  Found Solana wallet: {wallet_id} ({address})")

                # Get balance via Privy API
                call_mcp("privy_get_wallet_balance", {
                    "wallet_id": wallet_id,
                    "chain": "solana",
                    "asset": "sol"
                })


def test_block_apis():
    """Test block-related APIs"""
    print("\n=== Block APIs ===")

    # Get current slot first
    result = call_mcp("get_slot", {"chain": "solana"})

    if result and "slot" in result:
        slot = result["slot"]

        # Get block time
        call_mcp("get_block_time", {
            "chain": "solana",
            "slot": slot
        })

        # Get block (this can be large, so we skip it for now)
        # call_mcp("get_block", {
        #     "chain": "solana",
        #     "slot": slot,
        #     "include_transactions": False
        # })


def main():
    """Run all tests"""
    global tests_passed, tests_failed

    print(f"Testing Solana Mainnet APIs")
    print(f"API URL: {API_URL}")
    print(f"Access Token: {'✓ Set' if ACCESS_TOKEN else '✗ Not set'}")
    print(f"Privy Wallet ID: {PRIVY_WALLET_ID or 'Not set'}")
    print(f"Solana Address: {SOLANA_ADDRESS or 'Not set'}")

    # Run test suites
    test_network_apis()
    test_account_apis()
    test_token_apis()
    test_jupiter_price_apis()
    test_jupiter_defi_apis()
    test_privy_apis()
    test_block_apis()

    # Print summary
    print("\n" + "=" * 50)
    print(f"Test Summary:")
    print(f"  ✅ Passed: {tests_passed}")
    print(f"  ❌ Failed: {tests_failed}")
    print(f"  Total:  {tests_passed + tests_failed}")

    if tests_failed > 0:
        print(f"\n⚠️  {tests_failed} test(s) failed")
        sys.exit(1)
    else:
        print(f"\n✅ All {tests_passed} tests passed!")
        sys.exit(0)


if __name__ == "__main__":
    main()
