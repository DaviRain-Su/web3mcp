#!/bin/bash
# Jupiter 工具对比脚本
# 对比旧版（REST API）与 Phase 1（动态生成）

set -e

echo "════════════════════════════════════════════════════════"
echo "  Jupiter MCP 工具对比：旧版 vs Phase 1"
echo "════════════════════════════════════════════════════════"
echo ""

# 1. 统计旧版手动实现的工具
echo "📊 旧版实现（手动编码 REST API 包装器）"
echo "─────────────────────────────────────────────────────────"
OLD_TOOLS=$(find src/tools/solana/defi/jupiter -name "*.zig" ! -name "helpers.zig" | wc -l)
echo "总计: ${OLD_TOOLS} 个手动实现的工具"
echo ""

echo "分类统计:"
for category in swap lend trigger recurring studio ultra send tokens portfolio price; do
    count=$(find src/tools/solana/defi/jupiter/${category} -name "*.zig" 2>/dev/null | wc -l || echo 0)
    if [ "$count" -gt 0 ]; then
        printf "  %-12s : %2d 个工具\n" "${category}" "${count}"
    fi
done
echo ""

# 2. 检查 IDL
echo "📦 Phase 1 实现（动态从 IDL 生成）"
echo "─────────────────────────────────────────────────────────"

IDL_FILE="idl_registry/JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4.json"

if [ ! -f "$IDL_FILE" ]; then
    echo "❌ IDL 文件不存在: $IDL_FILE"
    echo "请先获取 Jupiter IDL"
    exit 1
fi

# 统计 IDL 中的指令数量
INSTRUCTION_COUNT=$(jq '.instructions | length' "$IDL_FILE" 2>/dev/null || echo "0")
echo "Jupiter v6 IDL 包含: ${INSTRUCTION_COUNT} 个链上指令"
echo ""

echo "指令列表:"
jq -r '.instructions[].name' "$IDL_FILE" 2>/dev/null | while read -r name; do
    echo "  ✓ jupiter_${name}"
done
echo ""

# 3. 类型统计
TYPE_COUNT=$(jq '.types | length' "$IDL_FILE" 2>/dev/null || echo "0")
ACCOUNT_COUNT=$(jq '.accounts | length' "$IDL_FILE" 2>/dev/null || echo "0")
ERROR_COUNT=$(jq '.errors | length' "$IDL_FILE" 2>/dev/null || echo "0")

echo "IDL 元数据:"
echo "  - 自定义类型: ${TYPE_COUNT}"
echo "  - 账户类型: ${ACCOUNT_COUNT}"
echo "  - 错误定义: ${ERROR_COUNT}"
echo ""

# 4. 对比分析
echo "🔍 对比分析"
echo "─────────────────────────────────────────────────────────"
echo "旧版（REST API）:"
echo "  ✓ 覆盖 ${OLD_TOOLS} 个功能"
echo "  ✓ 包括查询类 API（代币、价格、投资组合）"
echo "  ✓ 包括高级功能（Ultra、DBC Studio）"
echo "  ✗ 每个功能需手动编码"
echo "  ✗ 依赖 Jupiter 中心化服务"
echo ""

echo "Phase 1（链上指令）:"
echo "  ✓ 自动生成 ${INSTRUCTION_COUNT} 个工具（零手动编码）"
echo "  ✓ 完全去中心化（直接与链交互）"
echo "  ✓ 可扩展到任何 Anchor 程序"
echo "  ✗ 不支持纯 REST API 功能"
echo "  ✗ 需要用户自己处理路由优化"
echo ""

# 5. 功能覆盖分析
echo "📋 功能覆盖分析"
echo "─────────────────────────────────────────────────────────"

cat << 'EOF'
| 功能类别           | 旧版 | Phase 1 | 说明                    |
|--------------------|------|---------|-------------------------|
| Swap 基础指令      | ✓    | ✓       | 从 Jupiter v6 IDL 生成  |
| 路由优化           | ✓    | ✗       | 需要 REST API           |
| Limit Order        | ✓    | ✓       | 单独程序（如有 IDL）    |
| DCA/Recurring      | ✓    | ✓       | 单独程序（如有 IDL）    |
| 代币信息查询       | ✓    | ✗       | 纯 REST API             |
| 价格查询           | ✓    | ✗       | 纯 REST API             |
| 投资组合统计       | ✓    | ✗       | 纯 REST API             |
| DBC Studio         | ✓    | ?       | 可能是混合架构          |
| Ultra 高级功能     | ✓    | ✗       | 高级 REST API           |
EOF

echo ""

# 6. 推荐方案
echo "💡 推荐方案：混合架构"
echo "─────────────────────────────────────────────────────────"
echo "Phase 1 负责:"
echo "  - Jupiter Aggregator 链上 swap 指令 (${INSTRUCTION_COUNT} 个)"
echo "  - Limit Order 程序指令（如有 IDL）"
echo "  - DCA 程序指令（如有 IDL）"
echo ""

QUERY_TOOLS=$((OLD_TOOLS - INSTRUCTION_COUNT))
echo "保留旧版工具（约 ${QUERY_TOOLS} 个）:"
echo "  - 代币信息查询 (tokens/*)"
echo "  - 价格查询 (price)"
echo "  - 投资组合统计 (portfolio/*)"
echo "  - 高级功能 (ultra/*, studio/*)"
echo ""

echo "════════════════════════════════════════════════════════"
echo "  总结"
echo "════════════════════════════════════════════════════════"
echo "旧版: ${OLD_TOOLS} 个手动工具 → Phase 1: ${INSTRUCTION_COUNT} 个自动生成"
echo "建议：双轨并行，链上指令用 Phase 1，REST API 保留旧版"
echo ""
