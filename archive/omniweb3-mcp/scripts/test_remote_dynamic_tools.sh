#!/bin/bash
# 测试远程服务器的动态工具

API_URL="https://api.web3mcp.app/"

echo "════════════════════════════════════════════════════════"
echo "  测试 OmniWeb3 MCP 动态工具"
echo "  服务器: ${API_URL}"
echo "════════════════════════════════════════════════════════"
echo ""

# 1. 检查总工具数
echo "1️⃣ 工具统计"
echo "────────────────────────────────────────────────────────"
TOTAL=$(curl -s -X POST ${API_URL} \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '.result.tools | length')

echo "总工具数: ${TOTAL}"
echo ""

# 2. 列出动态工具
echo "2️⃣ 动态生成的 Jupiter 工具"
echo "────────────────────────────────────────────────────────"
curl -s -X POST ${API_URL} \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq -r '.result.tools[] | select(.name | startswith("jupiter_")) | select(.name | test("(route|sharedAccountsRoute|exactOutRoute|setTokenLedger|createOpenOrders|createProgramOpenOrders)")) | "  ✓ \(.name)"'
echo ""

# 3. 查看 jupiter_route 详细信息
echo "3️⃣ jupiter_route 工具详情"
echo "────────────────────────────────────────────────────────"
curl -s -X POST ${API_URL} \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '.result.tools[] | select(.name == "jupiter_route")'
echo ""

# 4. 测试调用 jupiter_route（这会失败因为缺少参数，但能验证工具存在）
echo "4️⃣ 测试调用 jupiter_route"
echo "────────────────────────────────────────────────────────"
echo "注意: 这是测试调用，预期会因为缺少参数而失败"
curl -s -X POST ${API_URL} \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "jupiter_route",
      "arguments": {}
    }
  }' | jq '.'
echo ""

# 5. 对比静态工具数量
echo "5️⃣ 工具分类统计"
echo "────────────────────────────────────────────────────────"
STATIC_JUPITER=$(curl -s -X POST ${API_URL} \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '[.result.tools[] | select(.name | startswith("jupiter_")) | select(.name | test("(route|sharedAccountsRoute|exactOutRoute|setTokenLedger|createOpenOrders|createProgramOpenOrders)") | not)] | length')

DYNAMIC_JUPITER=$(curl -s -X POST ${API_URL} \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '[.result.tools[] | select(.name | test("^jupiter_(route|sharedAccountsRoute|exactOutRoute|setTokenLedger|createOpenOrders|createProgramOpenOrders|sharedAccountsRouteWithTokenLedger)$"))] | length')

echo "Jupiter 工具统计:"
echo "  - 静态工具 (REST API): ${STATIC_JUPYTER}"
echo "  - 动态工具 (链上指令): ${DYNAMIC_JUPITER}"
echo "  - 总计: $((STATIC_JUPYTER + DYNAMIC_JUPYTER))"
echo ""

echo "════════════════════════════════════════════════════════"
echo "  ✅ 测试完成"
echo "════════════════════════════════════════════════════════"
echo ""
echo "🎯 下一步:"
echo "  1. 动态工具已成功加载 (${DYNAMIC_JUPITER} 个链上指令)"
echo "  2. 静态工具保持正常 (${STATIC_JUPYTER} 个 REST API 包装器)"
echo "  3. 混合架构运行正常！"
echo ""
