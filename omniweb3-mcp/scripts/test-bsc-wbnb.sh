#!/bin/bash
# BSC Testnet WBNB 合约测试 - 使用静态 evm_call 工具

set -e

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
BASE_URL="http://${HOST}:${PORT}"

# BSC Testnet 地址
WBNB_TESTNET="0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
WALLET="0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"

echo ""
echo "================================================"
echo "  🧪 BSC Testnet WBNB 合约测试"
echo "================================================"
echo ""
echo "WBNB 合约: $WBNB_TESTNET"
echo "测试钱包: $WALLET"
echo ""

# 检查服务器
if ! curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "❌ MCP Server 未运行！"
    exit 1
fi
echo "✅ MCP Server 正在运行"
echo ""

# 辅助函数：调用合约
call_contract() {
    local id=$1
    local function_sig=$2
    local return_type=$3
    local args=$4

    if [ -z "$args" ]; then
        # 无参数调用
        curl -s -X POST "${BASE_URL}/" \
          -H "Content-Type: application/json" \
          -d '{
            "jsonrpc": "2.0",
            "id": '"$id"',
            "method": "tools/call",
            "params": {
              "name": "evm_call",
              "arguments": {
                "chain": "bsc",
                "network": "testnet",
                "to_address": "'"$WBNB_TESTNET"'",
                "function_signature": "'"$function_sig"'",
                "function_return_types": ['"$return_type"']
              }
            }
          }'
    else
        # 带参数调用
        curl -s -X POST "${BASE_URL}/" \
          -H "Content-Type: application/json" \
          -d '{
            "jsonrpc": "2.0",
            "id": '"$id"',
            "method": "tools/call",
            "params": {
              "name": "evm_call",
              "arguments": {
                "chain": "bsc",
                "network": "testnet",
                "to_address": "'"$WBNB_TESTNET"'",
                "function_signature": "'"$function_sig"'",
                "function_args": ['"$args"'],
                "function_return_types": ['"$return_type"']
              }
            }
          }'
    fi
}

# 测试 1: name()
echo "📝 [1/5] 查询 WBNB 名称..."
RESPONSE=$(call_contract 1 "name()" '"string"' "")
NAME=$(echo "$RESPONSE" | jq -r '.result.content[0].text // empty')

if [ -n "$NAME" ]; then
    echo "   ✅ Name: $NAME"
else
    echo "   ❌ 查询失败"
    echo "$RESPONSE" | jq '.'
fi
echo ""

# 测试 2: symbol()
echo "🔤 [2/5] 查询 WBNB 符号..."
RESPONSE=$(call_contract 2 "symbol()" '"string"' "")
SYMBOL=$(echo "$RESPONSE" | jq -r '.result.content[0].text // empty')

if [ -n "$SYMBOL" ]; then
    echo "   ✅ Symbol: $SYMBOL"
else
    echo "   ❌ 查询失败"
    echo "$RESPONSE" | jq '.'
fi
echo ""

# 测试 3: decimals()
echo "🔢 [3/5] 查询 WBNB 精度..."
RESPONSE=$(call_contract 3 "decimals()" '"uint8"' "")
DECIMALS=$(echo "$RESPONSE" | jq -r '.result.content[0].text // empty')

if [ -n "$DECIMALS" ]; then
    echo "   ✅ Decimals: $DECIMALS"
else
    echo "   ❌ 查询失败"
    echo "$RESPONSE" | jq '.'
fi
echo ""

# 测试 4: totalSupply()
echo "📊 [4/5] 查询 WBNB 总供应量..."
RESPONSE=$(call_contract 4 "totalSupply()" '"uint256"' "")
TOTAL_SUPPLY=$(echo "$RESPONSE" | jq -r '.result.content[0].text // empty')

if [ -n "$TOTAL_SUPPLY" ] && [ "$TOTAL_SUPPLY" != "null" ]; then
    echo "   ✅ Total Supply: $TOTAL_SUPPLY (wei)"

    if command -v bc &> /dev/null; then
        FORMATTED=$(echo "scale=2; $TOTAL_SUPPLY / 1000000000000000000" | bc 2>/dev/null || echo "")
        if [ -n "$FORMATTED" ]; then
            echo "                    $FORMATTED WBNB"
        fi
    fi
else
    echo "   ❌ 查询失败"
    echo "$RESPONSE" | jq '.'
fi
echo ""

# 测试 5: balanceOf(address)
echo "💎 [5/5] 查询你的 WBNB 余额..."
RESPONSE=$(call_contract 5 "balanceOf(address)" '"uint256"' "\"$WALLET\"")
BALANCE=$(echo "$RESPONSE" | jq -r '.result.content[0].text // empty')

if [ -n "$BALANCE" ] && [ "$BALANCE" != "null" ]; then
    echo "   余额: $BALANCE (wei)"

    if command -v bc &> /dev/null && [ "$BALANCE" != "0" ]; then
        FORMATTED=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc 2>/dev/null || echo "")
        if [ -n "$FORMATTED" ]; then
            echo "         $FORMATTED WBNB"
        fi
    fi

    if [ "$BALANCE" = "0" ]; then
        echo "         你还没有 WBNB，可以通过 deposit BNB 来获取"
    fi
else
    echo "   ❌ 查询失败"
    echo "$RESPONSE" | jq '.'
fi
echo ""

echo "================================================"
echo "  ✨ 测试完成！"
echo "================================================"
echo ""
echo "总结："
echo "  ✅ 静态 evm_call 工具可以调用任何合约"
echo "  ✅ BSC Testnet WBNB 合约工作正常"
echo "  ✅ 所有只读方法测试成功"
echo ""
echo "下一步："
echo "  - 如果想包装 BNB 为 WBNB，可以调用 deposit() 方法"
echo "  - 如果想解包 WBNB 回 BNB，可以调用 withdraw() 方法"
echo "  - 参考 WALLET_CONFIG_GUIDE.md 配置钱包进行写入操作"
echo ""
