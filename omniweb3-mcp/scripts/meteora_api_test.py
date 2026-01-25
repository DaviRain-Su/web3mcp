#!/usr/bin/env python3
"""
Meteora REST API Test Script

Tests the new Meteora REST API tools that provide accurate pool data
via Meteora's official HTTP endpoints.

Usage:
    export WEB3MCP_ACCESS_TOKEN="your-bearer-token"
    python3 scripts/meteora_api_test.py
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

# Test pool addresses
SOL_USDC_DLMM = "BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y"

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


def test_list_dlmm_pools():
    """Test listing all DLMM pools via REST API"""
    print("\n" + "="*60)
    print("🌊 METEORA REST API - List DLMM Pools")
    print("="*60)
    print("\nThis test fetches all DLMM pools from Meteora's official API.")
    print("Unlike on-chain parsing, this returns ACCURATE data including:")
    print("- Current prices")
    print("- TVL and reserves")
    print("- 24h volume and fees")
    print("- APR/APY metrics")

    print("\n1. Get All DLMM Pools")
    result = call_mcp("meteora_api_list_dlmm_pools", {})

    if result:
        print(f"\n   Response summary:")
        if "count" in result:
            print(f"   - Pool count: {result['count']}")
        if "endpoint" in result:
            print(f"   - API endpoint: {result['endpoint']}")

        # Show first pool as example
        pools = result.get("pools", {})
        if isinstance(pools, dict) and "groups" in pools:
            groups = pools["groups"]
            if groups:
                first_group = list(groups.values())[0]
                if first_group:
                    first_pool = first_group[0] if isinstance(first_group, list) else first_pool
                    print(f"\n   Example pool data:")
                    print(f"   - Address: {first_pool.get('address', 'N/A')}")
                    print(f"   - Name: {first_pool.get('name', 'N/A')}")
                    print(f"   - Current Price: {first_pool.get('current_price', 'N/A')}")
                    print(f"   - TVL: ${first_pool.get('liquidity', 'N/A')}")
                    print(f"   - 24h Volume: ${first_pool.get('trade_volume_24h', 'N/A')}")
                    print(f"   - APR: {first_pool.get('apr', 'N/A')}%")


def test_get_dlmm_pool():
    """Test getting specific DLMM pool via REST API"""
    print("\n" + "="*60)
    print("🎯 METEORA REST API - Get Specific DLMM Pool")
    print("="*60)
    print(f"\nFetching detailed info for SOL-USDC pool:")
    print(f"Pool Address: {SOL_USDC_DLMM}")

    print("\n1. Get Pool Info")
    result = call_mcp("meteora_api_get_dlmm_pool", {
        "pool_address": SOL_USDC_DLMM
    })

    if result:
        print(f"\n   Pool data retrieved successfully!")
        pool_data = result.get("pool_data", {})
        if pool_data:
            print(f"\n   Key metrics:")
            print(f"   - Address: {pool_data.get('address', 'N/A')}")
            print(f"   - Name: {pool_data.get('name', 'N/A')}")
            print(f"   - Current Price: {pool_data.get('current_price', 'N/A')}")
            print(f"   - Bin Step: {pool_data.get('bin_step', 'N/A')}")
            print(f"   - Fee %: {pool_data.get('base_fee_percentage', 'N/A')}")
            print(f"   - TVL: ${pool_data.get('liquidity', 'N/A')}")
            print(f"   - 24h Volume: ${pool_data.get('trade_volume_24h', 'N/A')}")
            print(f"   - 24h Fees: ${pool_data.get('fees_24h', 'N/A')}")
            print(f"   - APR: {pool_data.get('apr', 'N/A')}%")


def test_list_damm_pools():
    """Test listing all DAMM pools via REST API"""
    print("\n" + "="*60)
    print("🔄 METEORA REST API - List DAMM Pools")
    print("="*60)
    print("\nFetching all DAMM V2 pools from Meteora API...")

    print("\n1. Get All DAMM Pools")
    result = call_mcp("meteora_api_list_damm_pools", {})

    if result:
        print(f"\n   Response summary:")
        if "count" in result:
            print(f"   - Pool count: {result['count']}")
        if "endpoint" in result:
            print(f"   - API endpoint: {result['endpoint']}")


def main():
    """Run all tests"""
    global tests_passed, tests_failed

    print("="*60)
    print("🚀 METEORA REST API TOOLS TEST")
    print("="*60)
    print(f"API URL: {API_URL}")
    print(f"Access Token: {'✓ Set' if ACCESS_TOKEN else '✗ Not set'}")

    print("\n⚠️  NOTE:")
    print("These new tools use Meteora's official REST API instead of")
    print("parsing on-chain data, providing ACCURATE pool information.")

    # Run tests
    test_list_dlmm_pools()
    test_get_dlmm_pool()
    test_list_damm_pools()

    # Print summary
    print("\n" + "="*60)
    print(f"Test Summary:")
    print(f"  ✅ Passed: {tests_passed}")
    print(f"  ❌ Failed: {tests_failed}")
    print(f"  Total:  {tests_passed + tests_failed}")
    print("="*60)

    print("\n✅ Benefits of REST API tools:")
    print("  1. Accurate data (no parsing errors)")
    print("  2. Includes computed metrics (APR, TVL)")
    print("  3. Fast response times")
    print("  4. No RPC rate limits")
    print("\n📚 Compare with on-chain tools in:")
    print("  docs/METEORA_INTEGRATION.md")

    if tests_failed > 0:
        print(f"\n⚠️  {tests_failed} test(s) failed")
        sys.exit(1)
    else:
        print(f"\n✅ All {tests_passed} tests passed!")
        sys.exit(0)


if __name__ == "__main__":
    main()
