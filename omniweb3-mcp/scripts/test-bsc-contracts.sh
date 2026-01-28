#!/bin/bash
# BSC Testnet 合约测试脚本

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"
ADDRESS="0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"

# BSC Testnet 合约地址
WBNB_TESTNET="0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
PANCAKE_ROUTER_TESTNET="0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
BUSD_TESTNET="0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee"

echo ""
echo "================================================"
echo "  🧪 BSC Testnet 合约测试"
echo "================================================"
echo ""
echo "钱包地址: $ADDRESS"
echo "WBNB (Testnet): $WBNB_TESTNET"
echo "PancakeSwap Router: $PANCAKE_ROUTER_TESTNET"
echo "BUSD (Testnet): $BUSD_TESTNET"
echo ""

# 检查服务器
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ MCP Server 未运行！"
    exit 1
fi
echo "✅ MCP Server 正在运行"
echo ""

# ============================================
# 测试 1: 查询 BNB 余额
# ============================================
echo "💰 [1/6] 查询 BNB 余额..."
BALANCE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_get_balance\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"address\": \"$ADDRESS\"
    }
  }" | jq -r '.content[0].text' 2>/dev/null || echo "查询失败")

if [ -n "$BALANCE" ] && [ "$BALANCE" != "null" ] && [ "$BALANCE" != "查询失败" ]; then
    echo "   余额: $BALANCE wei"
    if command -v bc &> /dev/null; then
        BNB=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc)
        echo "         $BNB BNB"
    fi
else
    echo "   ⚠️  查询失败"
fi
echo ""

# ============================================
# 测试 2: 调用 WBNB name() - 只读方法
# ============================================
echo "📝 [2/6] 查询 WBNB 合约名称 (name)..."
WBNB_NAME=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_call\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"to_address\": \"$WBNB_TESTNET\",
      \"function_signature\": \"name()\",
      \"function_return_types\": [\"string\"]
    }
  }" | jq -r '.content[0].text' 2>/dev/null || echo "查询失败")

echo "   WBNB Name: $WBNB_NAME"
echo ""

# ============================================
# 测试 3: 调用 WBNB symbol() - 只读方法
# ============================================
echo "🔤 [3/6] 查询 WBNB 合约符号 (symbol)..."
WBNB_SYMBOL=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_call\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"to_address\": \"$WBNB_TESTNET\",
      \"function_signature\": \"symbol()\",
      \"function_return_types\": [\"string\"]
    }
  }" | jq -r '.content[0].text' 2>/dev/null || echo "查询失败")

echo "   WBNB Symbol: $WBNB_SYMBOL"
echo ""

# ============================================
# 测试 4: 调用 WBNB decimals() - 只读方法
# ============================================
echo "🔢 [4/6] 查询 WBNB 精度 (decimals)..."
WBNB_DECIMALS=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_call\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"to_address\": \"$WBNB_TESTNET\",
      \"function_signature\": \"decimals()\",
      \"function_return_types\": [\"uint8\"]
    }
  }" | jq -r '.content[0].text' 2>/dev/null || echo "查询失败")

echo "   WBNB Decimals: $WBNB_DECIMALS"
echo ""

# ============================================
# 测试 5: 查询 WBNB 余额 - balanceOf(address)
# ============================================
echo "💎 [5/6] 查询 WBNB 代币余额 (balanceOf)..."
WBNB_BALANCE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_call\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"to_address\": \"$WBNB_TESTNET\",
      \"function_signature\": \"balanceOf(address)\",
      \"function_args\": [\"$ADDRESS\"],
      \"function_return_types\": [\"uint256\"]
    }
  }" | jq -r '.content[0].text' 2>/dev/null || echo "查询失败")

if [ -n "$WBNB_BALANCE" ] && [ "$WBNB_BALANCE" != "null" ] && [ "$WBNB_BALANCE" != "查询失败" ]; then
    echo "   WBNB 余额: $WBNB_BALANCE (最小单位)"
    if command -v bc &> /dev/null && [ "$WBNB_DECIMALS" = "18" ]; then
        WBNB_FORMATTED=$(echo "scale=6; $WBNB_BALANCE / 1000000000000000000" | bc)
        echo "             $WBNB_FORMATTED WBNB"
    fi
else
    echo "   WBNB 余额: $WBNB_BALANCE"
fi
echo ""

# ============================================
# 测试 6: 查询 BUSD totalSupply() - 只读方法
# ============================================
echo "📊 [6/6] 查询 BUSD 总供应量 (totalSupply)..."
BUSD_SUPPLY=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_call\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"to_address\": \"$BUSD_TESTNET\",
      \"function_signature\": \"totalSupply()\",
      \"function_return_types\": [\"uint256\"]
    }
  }" | jq -r '.content[0].text' 2>/dev/null || echo "查询失败")

echo "   BUSD Total Supply: $BUSD_SUPPLY"
echo ""

echo "================================================"
echo "  ✨ 只读测试完成！"
echo "================================================"
echo ""
echo "如果你想测试写入操作（需要花费 gas），可以尝试："
echo "  - WBNB deposit: 将 BNB 包装成 WBNB"
echo "  - WBNB withdraw: 将 WBNB 解包回 BNB"
echo "  - ERC20 approve: 授权合约使用代币"
echo ""
echo "是否继续测试 WBNB deposit？(需要少量 gas)"
echo ""

read -p "输入 'y' 测试 deposit 0.01 BNB: " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🚀 测试 WBNB deposit (0.01 BNB)..."

    # 调用 transfer 工具并指定 data 字段调用 deposit()
    # deposit() 的 function selector: 0xd0e30db0
    DEPOSIT_RESULT=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"transfer\",
        \"arguments\": {
          \"chain\": \"bnb\",
          \"network\": \"testnet\",
          \"to_address\": \"$WBNB_TESTNET\",
          \"amount\": \"10000000000000000\",
          \"wallet_type\": \"local\",
          \"tx_type\": \"eip1559\",
          \"confirmations\": 1
        }
      }")

    echo "$DEPOSIT_RESULT" | jq '.'
    echo ""
else
    echo "⏭️  跳过写入测试"
fi

echo ""
echo "================================================"
echo "  🎉 测试完成！"
echo "================================================"
echo ""
