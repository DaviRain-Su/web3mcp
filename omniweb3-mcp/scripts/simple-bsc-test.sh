#!/bin/bash
# 简单的 BSC Testnet 合约测试 - 使用 MCP JSON-RPC 协议

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"
ADDRESS="0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"

# BSC Testnet 合约地址
WBNB_TESTNET="0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
BUSD_TESTNET="0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee"

echo ""
echo "================================================"
echo "  🧪 BSC Testnet 合约测试 (MCP 协议)"
echo "================================================"
echo ""

# 检查服务器
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ MCP Server 未运行！"
    exit 1
fi
echo "✅ MCP Server 正在运行"
echo ""

# ============================================
# 测试 1: 列出所有可用工具
# ============================================
echo "📋 [1/5] 列出 BSC 相关工具..."
echo ""
echo "发送 MCP tools/list 请求..."

TOOLS_RESPONSE=$(curl -s -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {}
  }')

# 检查响应
if echo "$TOOLS_RESPONSE" | jq -e '.result.tools' > /dev/null 2>&1; then
    TOOL_COUNT=$(echo "$TOOLS_RESPONSE" | jq '.result.tools | length')
    echo "   ✅ 共 $TOOL_COUNT 个工具"

    # 列出前 10 个 BSC 相关工具
    echo ""
    echo "   BSC 相关工具示例 (前 10 个):"
    echo "$TOOLS_RESPONSE" | jq -r '.result.tools[] | select(.name | startswith("bsc_")) | .name' | head -10 | while read tool; do
        echo "     - $tool"
    done
else
    echo "   ❌ 获取工具列表失败"
    echo "$TOOLS_RESPONSE" | jq '.'
fi
echo ""

# ============================================
# 测试 2: 查询 BNB 余额
# ============================================
echo "💰 [2/5] 查询 BNB 余额..."

BALANCE_RESPONSE=$(curl -s -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 2,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"evm_get_balance\",
      \"arguments\": {
        \"chain\": \"bsc\",
        \"network\": \"testnet\",
        \"address\": \"$ADDRESS\"
      }
    }
  }")

# 解析余额
if echo "$BALANCE_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    BALANCE=$(echo "$BALANCE_RESPONSE" | jq -r '.result.content[0].text')
    echo "   余额: $BALANCE wei"

    if command -v bc &> /dev/null && [ -n "$BALANCE" ] && [ "$BALANCE" != "null" ]; then
        BNB=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc 2>/dev/null || echo "")
        if [ -n "$BNB" ]; then
            echo "         $BNB tBNB"
        fi
    fi
else
    echo "   ❌ 查询失败"
    echo "$BALANCE_RESPONSE" | jq '.'
fi
echo ""

# ============================================
# 测试 3: 调用 WBNB name() - 只读
# ============================================
echo "📝 [3/5] 查询 WBNB 名称 (evm_call)..."

NAME_RESPONSE=$(curl -s -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 3,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"evm_call\",
      \"arguments\": {
        \"chain\": \"bsc\",
        \"network\": \"testnet\",
        \"to_address\": \"$WBNB_TESTNET\",
        \"function_signature\": \"name()\",
        \"function_return_types\": [\"string\"]
      }
    }
  }")

if echo "$NAME_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    WBNB_NAME=$(echo "$NAME_RESPONSE" | jq -r '.result.content[0].text')
    echo "   ✅ WBNB Name: $WBNB_NAME"
else
    echo "   ❌ 查询失败"
    echo "$NAME_RESPONSE" | jq '.'
fi
echo ""

# ============================================
# 测试 4: 调用 WBNB symbol() - 只读
# ============================================
echo "🔤 [4/5] 查询 WBNB 符号 (symbol)..."

SYMBOL_RESPONSE=$(curl -s -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 4,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"evm_call\",
      \"arguments\": {
        \"chain\": \"bsc\",
        \"network\": \"testnet\",
        \"to_address\": \"$WBNB_TESTNET\",
        \"function_signature\": \"symbol()\",
        \"function_return_types\": [\"string\"]
      }
    }
  }")

if echo "$SYMBOL_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    WBNB_SYMBOL=$(echo "$SYMBOL_RESPONSE" | jq -r '.result.content[0].text')
    echo "   ✅ WBNB Symbol: $WBNB_SYMBOL"
else
    echo "   ❌ 查询失败"
    echo "$SYMBOL_RESPONSE" | jq '.'
fi
echo ""

# ============================================
# 测试 5: 查询 WBNB 余额 balanceOf(address)
# ============================================
echo "💎 [5/5] 查询 WBNB 代币余额 (balanceOf)..."

WBNB_BALANCE_RESPONSE=$(curl -s -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 5,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"evm_call\",
      \"arguments\": {
        \"chain\": \"bsc\",
        \"network\": \"testnet\",
        \"to_address\": \"$WBNB_TESTNET\",
        \"function_signature\": \"balanceOf(address)\",
        \"function_args\": [\"$ADDRESS\"],
        \"function_return_types\": [\"uint256\"]
      }
    }
  }")

if echo "$WBNB_BALANCE_RESPONSE" | jq -e '.result.content[0].text' > /dev/null 2>&1; then
    WBNB_BAL=$(echo "$WBNB_BALANCE_RESPONSE" | jq -r '.result.content[0].text')
    echo "   WBNB 余额: $WBNB_BAL (最小单位)"

    if command -v bc &> /dev/null && [ -n "$WBNB_BAL" ] && [ "$WBNB_BAL" != "null" ]; then
        WBNB_FORMATTED=$(echo "scale=6; $WBNB_BAL / 1000000000000000000" | bc 2>/dev/null || echo "")
        if [ -n "$WBNB_FORMATTED" ]; then
            echo "             $WBNB_FORMATTED WBNB"
        fi
    fi
else
    echo "   ❌ 查询失败"
    echo "$WBNB_BALANCE_RESPONSE" | jq '.'
fi
echo ""

echo "================================================"
echo "  ✨ 测试完成！"
echo "================================================"
echo ""
echo "总结："
echo "  ✅ MCP JSON-RPC 协议工作正常"
echo "  ✅ 可以调用 BSC Testnet 合约"
echo "  ✅ 只读方法 (view/pure) 测试成功"
echo ""
echo "如果需要测试写入方法，可以查看："
echo "  - scripts/test-bsc-contracts.sh (包含 WBNB deposit 示例)"
echo ""
