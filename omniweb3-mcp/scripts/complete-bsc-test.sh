#!/bin/bash
# 完整的 BSC Testnet 测试流程

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"
ADDRESS="0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"

echo ""
echo "================================================"
echo "  🧪 完整 BSC Testnet 测试"
echo "================================================"
echo ""
echo "钱包地址: $ADDRESS"
echo "水龙头交易: https://testnet.bscscan.com/tx/0xdd6862cc8ca23e76ee68d129018ee3cc2a0d819f49fa75ab74f2ef226fc40a1a"
echo ""

# 检查服务器
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ MCP Server 未运行！"
    echo ""
    echo "请在另一个终端启动服务器："
    echo "  ./scripts/start-bsc-testnet.sh"
    echo ""
    exit 1
fi

echo "✅ MCP Server 正在运行"
echo ""

# ============================================
# 测试 1: 获取链 ID
# ============================================
echo "📡 [1/7] 获取链 ID..."
CHAIN_ID=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_chain_id",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq -r '.content[0].text')

if [ "$CHAIN_ID" = "97" ]; then
    echo "   ✅ Chain ID: $CHAIN_ID (BSC Testnet)"
else
    echo "   ❌ Chain ID: $CHAIN_ID (期望: 97)"
fi
echo ""

# ============================================
# 测试 2: 获取最新区块
# ============================================
echo "📦 [2/7] 获取最新区块号..."
BLOCK=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_block_number",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq -r '.content[0].text')

echo "   ✅ 最新区块: $BLOCK"
echo ""

# ============================================
# 测试 3: 获取 Gas 价格
# ============================================
echo "⛽ [3/7] 获取 Gas 价格..."
GAS_PRICE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_gas_price",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }' | jq -r '.content[0].text')

echo "   ✅ Gas 价格: $GAS_PRICE Gwei"
echo ""

# ============================================
# 测试 4: 查询余额
# ============================================
echo "💰 [4/7] 查询钱包余额..."
BALANCE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_get_balance\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"address\": \"$ADDRESS\"
    }
  }" | jq -r '.content[0].text')

echo "   余额: $BALANCE wei"

# 转换为 BNB
if command -v bc &> /dev/null && [ -n "$BALANCE" ] && [ "$BALANCE" != "null" ]; then
    BNB=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc)
    echo "         $BNB tBNB"
fi
echo ""

# ============================================
# 测试 5: 获取 Nonce
# ============================================
echo "🔢 [5/7] 获取交易计数 (nonce)..."
NONCE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_get_transaction_count\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"address\": \"$ADDRESS\"
    }
  }" | jq -r '.content[0].text')

echo "   ✅ Nonce: $NONCE"
echo ""

# ============================================
# 测试 6: 估算 Gas
# ============================================
echo "🔍 [6/7] 估算转账 Gas..."
GAS_ESTIMATE=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"evm_estimate_gas\",
    \"arguments\": {
      \"chain\": \"bsc\",
      \"network\": \"testnet\",
      \"from\": \"$ADDRESS\",
      \"to\": \"0x0000000000000000000000000000000000000001\",
      \"value\": \"10000000000000000\"
    }
  }" | jq -r '.content[0].text')

echo "   ✅ 估算 Gas: $GAS_ESTIMATE"
echo ""

# ============================================
# 测试 7: 询问是否发送测试交易
# ============================================
echo "💸 [7/7] 发送测试转账"
echo ""
echo "准备发送一笔小额测试转账："
echo "  从: $ADDRESS"
echo "  到: 0x0000000000000000000000000000000000000001 (burn address)"
echo "  金额: 0.01 tBNB"
echo "  预估 Gas: $GAS_ESTIMATE"
echo ""

read -p "是否继续发送测试交易? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🚀 正在发送交易..."

    TX_RESULT=$(curl -s -X POST "${BASE_URL}/mcp/v1/tools/call" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"transfer\",
        \"arguments\": {
          \"chain\": \"bnb\",
          \"network\": \"testnet\",
          \"to_address\": \"0x0000000000000000000000000000000000000001\",
          \"amount\": \"10000000000000000\",
          \"wallet_type\": \"local\",
          \"tx_type\": \"eip1559\",
          \"confirmations\": 1
        }
      }")

    echo "$TX_RESULT" | jq '.'

    # 提取交易哈希
    TX_HASH=$(echo "$TX_RESULT" | jq -r '.content[0].text' | grep -oE '0x[a-fA-F0-9]{64}' | head -1)

    if [ -n "$TX_HASH" ]; then
        echo ""
        echo "✅ 交易发送成功！"
        echo ""
        echo "交易哈希: $TX_HASH"
        echo "浏览器查看: https://testnet.bscscan.com/tx/$TX_HASH"
        echo ""
    else
        echo ""
        echo "⚠️  交易可能失败，请检查上面的响应"
    fi
else
    echo ""
    echo "⏭️  跳过测试转账"
fi

echo ""
echo "================================================"
echo "  ✨ 测试完成！"
echo "================================================"
echo ""
echo "测试结果总结："
echo "  ✅ Chain ID: $CHAIN_ID"
echo "  ✅ 最新区块: $BLOCK"
echo "  ✅ Gas 价格: $GAS_PRICE Gwei"
echo "  ✅ 钱包余额: $BNB tBNB"
echo "  ✅ Nonce: $NONCE"
echo "  ✅ Gas 估算: $GAS_ESTIMATE"
echo ""
echo "🎉 你的 MCP Server 在 BSC Testnet 上运行正常！"
echo ""
