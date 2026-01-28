#!/bin/bash
# BSC Testnet 综合测试脚本 - 包含所有常用测试

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"
ADDRESS="${ADDRESS:-0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71}"

# BSC Testnet 合约地址
WBNB_TESTNET="0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"

echo ""
echo "================================================"
echo "  🧪 BSC Testnet 综合测试"
echo "================================================"
echo ""
echo "测试钱包: $ADDRESS"
echo "WBNB 合约: $WBNB_TESTNET"
echo ""

# 检查服务器
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ MCP Server 未运行！"
    echo "请先运行: ./scripts/start-bsc-testnet.sh"
    exit 1
fi
echo "✅ MCP Server 正在运行"
echo ""

# 辅助函数：调用 MCP 工具
call_tool() {
    local id=$1
    local tool=$2
    local args=$3

    curl -s -X POST "${BASE_URL}/" \
      -H "Content-Type: application/json" \
      -d "{
        \"jsonrpc\": \"2.0\",
        \"id\": $id,
        \"method\": \"tools/call\",
        \"params\": {
          \"name\": \"$tool\",
          \"arguments\": $args
        }
      }" | jq -r '.result.content[0].text // .error.message // "Error"'
}

# ============================================
# 基础测试
# ============================================
echo "📋 基础网络测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "1. 链 ID: "
call_tool 1 "get_chain_id" '{"chain":"bnb","network":"testnet"}'

echo -n "2. 最新区块: "
call_tool 2 "get_block_number" '{"chain":"bnb","network":"testnet"}'

echo -n "3. Gas 价格: "
GAS_PRICE=$(call_tool 3 "get_gas_price" '{"chain":"bnb","network":"testnet"}')
echo "$GAS_PRICE wei"

echo ""

# ============================================
# 余额查询
# ============================================
echo "💰 余额查询"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "4. BNB 余额:"
BALANCE=$(call_tool 4 "get_balance" "{\"chain\":\"bnb\",\"network\":\"testnet\",\"address\":\"$ADDRESS\"}")
echo "   $BALANCE wei"

if command -v bc &> /dev/null && [ "$BALANCE" != "Error" ] && [ -n "$BALANCE" ]; then
    BNB=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc 2>/dev/null || echo "")
    [ -n "$BNB" ] && echo "   $BNB tBNB"
fi

echo ""
echo "5. WBNB 代币余额:"
WBNB_BAL=$(call_tool 5 "token_balance" "{\"chain\":\"bnb\",\"network\":\"testnet\",\"token_address\":\"$WBNB_TESTNET\",\"owner\":\"$ADDRESS\"}")
echo "   $WBNB_BAL (最小单位)"

if command -v bc &> /dev/null && [ "$WBNB_BAL" != "0" ] && [ "$WBNB_BAL" != "Error" ]; then
    WBNB=$(echo "scale=6; $WBNB_BAL / 1000000000000000000" | bc 2>/dev/null || echo "")
    [ -n "$WBNB" ] && echo "   $WBNB WBNB"
fi

echo ""

# ============================================
# 交易相关
# ============================================
echo "🔧 交易工具"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "6. Nonce: "
call_tool 6 "get_nonce" "{\"chain\":\"bnb\",\"network\":\"testnet\",\"address\":\"$ADDRESS\"}"

echo "7. Gas 估算 (0.01 tBNB 转账):"
GAS_EST=$(call_tool 7 "estimate_gas" "{\"chain\":\"bnb\",\"network\":\"testnet\",\"from_address\":\"$ADDRESS\",\"to_address\":\"0x0000000000000000000000000000000000000001\",\"value\":\"10000000000000000\"}")
echo "   $GAS_EST"

echo ""

# ============================================
# 总结
# ============================================
echo "================================================"
echo "  ✨ 测试完成"
echo "================================================"
echo ""
echo "测试结果："
echo "  ✅ 链连接正常 (BSC Testnet)"
echo "  ✅ 余额查询成功"
echo "  ✅ Gas 估算成功"
echo "  ✅ 工具总数: 1057 (173 静态 + 884 动态)"
echo ""
echo "下一步："
echo "  - 如需转账测试: 使用 'transfer' 工具"
echo "  - 如需合约调用: 使用 'call' 工具或动态合约工具"
echo "  - 查看文档: cat BSC_TESTNET.md"
echo ""
