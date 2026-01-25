#!/usr/bin/env python3
"""
Meteora DeFi Demo Script

Demonstrates all Meteora protocol features on Solana mainnet.
Meteora is a DeFi protocol offering multiple liquidity solutions.

⚠️  KNOWN LIMITATIONS:
The current implementation parses on-chain account data at hardcoded byte offsets,
which don't match the actual Meteora program account structures. This results in:
- Incorrect bin_id, bin_step, and price values
- Tools return data but values are garbage from wrong memory locations

See docs/METEORA_INTEGRATION.md for details and recommended solutions.

Features tested:
- DLMM (Dynamic Liquidity Market Maker) - ⚠️  Returns data but values incorrect
- DAMM V1/V2 (Dynamic AMM) - ⚠️  Returns data but values incorrect
- Alpha Vault (Auto-compounding vaults)
- DBC (Dynamic Bonding Curve)
- M3M3 (Stake-for-Fee)
- Vault (Liquidity vaults)

Usage:
    export WEB3MCP_ACCESS_TOKEN="your-bearer-token"
    python3 scripts/meteora_demo.py
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

ACCESS_TOKEN = os.environ.get("WEB3MCP_ACCESS_TOKEN")
if not ACCESS_TOKEN:
    print("Error: WEB3MCP_ACCESS_TOKEN environment variable is required")
    sys.exit(1)

API_URL = os.environ.get("WEB3MCP_API_URL", "https://api.web3mcp.app")
WALLET_ADDRESS = os.environ.get("SOLANA_ADDRESS")

# Popular Meteora pools (verified on mainnet)
# SOL-USDC DLMM pool (verified: https://www.meteora.ag/dlmm/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y)
SOL_USDC_DLMM = "BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y"
# SOL-USDT DAMM pool (example - may need verification)
SOL_USDT_DAMM = "9WbGQFmSSt5cZqLFYoRWv2uZw7s8wqe2RoGmPgCFAGJz"

# Meteora token
METEORA_TOKEN = "METADDFL6wWMWEoKTFJwcThTbUmtarRJZjRpzUvkxhr"
SOL_MINT = "So11111111111111111111111111111111111111112"
USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

tests_passed = 0
tests_failed = 0


def call_mcp(tool_name, arguments=None, silent=False):
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

            if "error" in result:
                if not silent:
                    print(f"  ❌ {tool_name}: {result['error'].get('message', 'Unknown error')}")
                tests_failed += 1
                return None

            content = result.get("result", {}).get("content", [])
            if not content:
                if not silent:
                    print(f"  ❌ {tool_name}: No content")
                tests_failed += 1
                return None

            text = content[0].get("text", "")
            is_error = result.get("result", {}).get("isError", False)

            if is_error:
                if not silent:
                    print(f"  ❌ {tool_name}: {text}")
                tests_failed += 1
                return None

            try:
                parsed = json.loads(text)
                if not silent:
                    print(f"  ✅ {tool_name}")
                tests_passed += 1
                return parsed
            except json.JSONDecodeError:
                if not silent:
                    print(f"  ✅ {tool_name}: {text[:100]}")
                tests_passed += 1
                return text

    except Exception as e:
        if not silent:
            print(f"  ❌ {tool_name}: {str(e)}")
        tests_failed += 1
        return None


def demo_dlmm():
    """Demo DLMM (Dynamic Liquidity Market Maker)"""
    print("\n" + "="*60)
    print("🌊 METEORA DLMM - Dynamic Liquidity Market Maker")
    print("="*60)
    print("\nDLMM is Meteora's flagship product offering:")
    print("- Dynamic fee tiers based on volatility")
    print("- Concentrated liquidity with bins")
    print("- Auto-compounding rewards")
    print("- Lower impermanent loss")

    print("\n1. Get Pool Info")
    pool = call_mcp("meteora_dlmm_get_pool", {
        "pool_address": SOL_USDC_DLMM
    })

    if pool:
        print(f"   Pool: {pool.get('token_x_mint', 'N/A')[:8]}... / {pool.get('token_y_mint', 'N/A')[:8]}...")
        print(f"   Fee BPS: {pool.get('fee_bps', 'N/A')}")

    print("\n2. Get Active Bin (Current Price)")
    active_bin = call_mcp("meteora_dlmm_get_active_bin", {
        "pool_address": SOL_USDC_DLMM
    })

    if active_bin:
        print(f"   Active Bin ID: {active_bin.get('active_bin_id', 'N/A')}")
        print(f"   Price: {active_bin.get('price', 'N/A')}")

    print("\n3. Get Bins (Liquidity Distribution)")
    bins = call_mcp("meteora_dlmm_get_bins", {
        "pool_address": SOL_USDC_DLMM,
        "min_bin_id": active_bin.get('active_bin_id', 0) - 5 if active_bin else 0,
        "max_bin_id": active_bin.get('active_bin_id', 0) + 5 if active_bin else 10,
    })

    print("\n4. Get Swap Quote (0.1 SOL -> USDC)")
    quote = call_mcp("meteora_dlmm_swap_quote", {
        "pool_address": SOL_USDC_DLMM,
        "amount": "100000000",  # 0.1 SOL
        "swap_for_y": True  # SOL -> USDC
    })

    if quote:
        out_amount = int(quote.get('out_amount', 0)) / 1_000_000  # USDC has 6 decimals
        print(f"   Input: 0.1 SOL")
        print(f"   Output: ~{out_amount:.2f} USDC")
        print(f"   Fee: {quote.get('fee', 'N/A')}")

    if WALLET_ADDRESS:
        print(f"\n5. Get Your Positions (Address: {WALLET_ADDRESS[:8]}...)")
        positions = call_mcp("meteora_dlmm_get_positions", {
            "user_address": WALLET_ADDRESS,
            "pool_address": SOL_USDC_DLMM
        })


def demo_damm():
    """Demo DAMM (Dynamic AMM)"""
    print("\n" + "="*60)
    print("🔄 METEORA DAMM - Dynamic AMM")
    print("="*60)
    print("\nDAMM offers:")
    print("- Traditional AMM experience with dynamic fees")
    print("- Multiple pool types (Stable, Weighted)")
    print("- V1: Simple constant product AMM")
    print("- V2: Advanced with custom curves")

    print("\n--- DAMM V2 (Latest) ---")

    print("\n1. Get Pool Info")
    pool = call_mcp("meteora_damm_v2_get_pool", {
        "pool_address": SOL_USDT_DAMM
    })

    print("\n2. Get Swap Quote")
    quote = call_mcp("meteora_damm_v2_swap_quote", {
        "pool_address": SOL_USDT_DAMM,
        "amount_in": "50000000",  # 0.05 SOL
        "token_in": SOL_MINT
    })

    if WALLET_ADDRESS:
        print(f"\n3. Get Your Position")
        position = call_mcp("meteora_damm_v2_get_position", {
            "pool_address": SOL_USDT_DAMM,
            "user_address": WALLET_ADDRESS
        })


def demo_alpha_vault():
    """Demo Alpha Vault"""
    print("\n" + "="*60)
    print("🏦 METEORA ALPHA VAULT - Auto-Compounding Vaults")
    print("="*60)
    print("\nAlpha Vault features:")
    print("- Automated liquidity management")
    print("- Auto-compounding of fees and rewards")
    print("- Professional market making strategies")
    print("- Single-sided deposits supported")

    # Note: Need actual vault address
    print("\n1. Get Vault Info")
    print("   (Requires specific vault address)")
    # vault_info = call_mcp("meteora_alpha_vault_get_info", {
    #     "vault_address": "VAULT_ADDRESS_HERE"
    # })


def demo_dbc():
    """Demo Dynamic Bonding Curve"""
    print("\n" + "="*60)
    print("📈 METEORA DBC - Dynamic Bonding Curve")
    print("="*60)
    print("\nDBC is for token launches:")
    print("- Fair launch mechanism")
    print("- Dynamic pricing based on supply")
    print("- Auto-graduation to DEX when target reached")
    print("- Protection against rug pulls")

    print("\n1. Get Pool Info")
    print("   (Requires specific DBC pool address)")
    # pool = call_mcp("meteora_dbc_get_pool", {
    #     "pool_address": "DBC_POOL_ADDRESS"
    # })


def demo_m3m3():
    """Demo M3M3 (Stake-for-Fee)"""
    print("\n" + "="*60)
    print("💰 METEORA M3M3 - Stake for Fee Sharing")
    print("="*60)
    print("\nM3M3 allows you to:")
    print("- Stake MET tokens")
    print("- Earn protocol fees")
    print("- Participate in governance")

    print("\n1. Get Pool Info")
    pool = call_mcp("meteora_m3m3_get_pool", {})

    if WALLET_ADDRESS:
        print(f"\n2. Get Your Balance")
        balance = call_mcp("meteora_m3m3_get_user_balance", {
            "user_address": WALLET_ADDRESS
        })


def demo_vault():
    """Demo Vault"""
    print("\n" + "="*60)
    print("🏛️ METEORA VAULT - Liquidity Vaults")
    print("="*60)
    print("\nVault features:")
    print("- Deposit single or dual tokens")
    print("- Automated rebalancing")
    print("- Earn trading fees")
    print("- Withdraw anytime")

    print("\n1. Get Vault Info")
    print("   (Requires specific vault address)")
    # info = call_mcp("meteora_vault_get_info", {
    #     "vault_address": "VAULT_ADDRESS"
    # })


def list_all_tools():
    """List all available Meteora tools"""
    print("\n" + "="*60)
    print("📋 ALL METEORA TOOLS (42 total)")
    print("="*60)

    tools = {
        "DLMM (9 tools)": [
            "meteora_dlmm_get_pool", "meteora_dlmm_get_active_bin",
            "meteora_dlmm_get_bins", "meteora_dlmm_get_positions",
            "meteora_dlmm_swap_quote", "meteora_dlmm_swap",
            "meteora_dlmm_add_liquidity", "meteora_dlmm_remove_liquidity",
            "meteora_dlmm_claim_fees", "meteora_dlmm_claim_rewards"
        ],
        "DAMM V2 (7 tools)": [
            "meteora_damm_v2_get_pool", "meteora_damm_v2_get_position",
            "meteora_damm_v2_swap_quote", "meteora_damm_v2_swap",
            "meteora_damm_v2_add_liquidity", "meteora_damm_v2_remove_liquidity",
            "meteora_damm_v2_claim_fee", "meteora_damm_v2_create_pool"
        ],
        "DBC (7 tools)": [
            "meteora_dbc_get_pool", "meteora_dbc_get_quote",
            "meteora_dbc_create_pool", "meteora_dbc_buy", "meteora_dbc_sell",
            "meteora_dbc_check_graduation", "meteora_dbc_migrate"
        ],
        "Alpha Vault (4 tools)": [
            "meteora_alpha_vault_get_info", "meteora_alpha_vault_deposit",
            "meteora_alpha_vault_withdraw", "meteora_alpha_vault_claim"
        ],
        "M3M3 (5 tools)": [
            "meteora_m3m3_get_pool", "meteora_m3m3_get_user_balance",
            "meteora_m3m3_stake", "meteora_m3m3_unstake",
            "meteora_m3m3_claim_fee"
        ],
        "Vault (4 tools)": [
            "meteora_vault_get_info", "meteora_vault_get_user_balance",
            "meteora_vault_deposit", "meteora_vault_withdraw"
        ],
        "DAMM V1 (4 tools)": [
            "meteora_damm_v1_get_pool", "meteora_damm_v1_swap_quote",
            "meteora_damm_v1_swap", "meteora_damm_v1_deposit",
            "meteora_damm_v1_withdraw"
        ]
    }

    for category, tool_list in tools.items():
        print(f"\n{category}:")
        for tool in tool_list:
            print(f"  - {tool}")


def main():
    """Run all demos"""
    global tests_passed, tests_failed

    print("="*60)
    print("🌟 METEORA PROTOCOL DEMO")
    print("="*60)
    print(f"API URL: {API_URL}")
    print(f"Wallet: {WALLET_ADDRESS or 'Not set (read-only mode)'}")

    # List all available tools
    list_all_tools()

    # Run demos
    demo_dlmm()
    demo_damm()
    demo_alpha_vault()
    demo_dbc()
    demo_m3m3()
    demo_vault()

    # Print summary
    print("\n" + "="*60)
    print(f"Test Summary:")
    print(f"  ✅ Passed: {tests_passed}")
    print(f"  ❌ Failed: {tests_failed}")
    print(f"  Total:  {tests_passed + tests_failed}")
    print("="*60)

    print("\n⚠️  IMPORTANT FINDINGS:")
    print("  The tools successfully connect and fetch on-chain data,")
    print("  but the account parsing is incorrect (wrong byte offsets).")
    print("  This causes bin_id, bin_step, and price values to be wrong.")
    print("")
    print("  See: docs/METEORA_INTEGRATION.md for full analysis")
    print("")
    print("\n💡 Recommended Solutions:")
    print("  1. Use Meteora REST API: https://dlmm-api.meteora.ag/pair/all")
    print("  2. Implement proper Borsh deserialization")
    print("  3. Use official TypeScript SDK via Node.js bridge")
    print("")
    print("💡 Next Steps:")
    print("  1. Review docs/METEORA_INTEGRATION.md for technical details")
    print("  2. Choose implementation approach (REST API recommended)")
    print("  3. Check Meteora docs: https://docs.meteora.ag")
    print("  4. Test pool: https://www.meteora.ag/dlmm/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y")


if __name__ == "__main__":
    main()
