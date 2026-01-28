#!/bin/bash
# 一键启动本地开发环境并配置 Claude Desktop

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 启动 omniweb3-mcp 本地开发环境"
echo ""

# 1. 检查 MCP 服务器是否运行
echo "1️⃣ 检查 MCP 服务器..."
if ! curl -s http://127.0.0.1:8765/health > /dev/null 2>&1; then
    echo "❌ MCP 服务器未运行"
    echo ""
    echo "请先启动服务器："
    echo "  ./scripts/start-bsc-testnet.sh"
    exit 1
fi
echo "   ✅ MCP 服务器运行中 (http://127.0.0.1:8765)"
echo ""

# 2. 启动或检查隧道
echo "2️⃣ 启动 HTTPS 隧道..."
"$SCRIPT_DIR/tunnel-manager.sh" start 2>&1 | grep -v "^$" || {
    # 隧道已经在运行
    echo "   ✅ 隧道已运行"
    "$SCRIPT_DIR/tunnel-manager.sh" status
}
echo ""

# 3. 更新 Claude Desktop 配置
echo "3️⃣ 更新 Claude Desktop 配置..."
"$SCRIPT_DIR/update-claude-config.sh"
echo ""

# 4. 显示完成信息
echo "======================================"
echo "✅ 开发环境准备完成！"
echo "======================================"
echo ""
echo "📋 下一步："
echo "   1. 重启 Claude Desktop"
echo "   2. 使用 'omniweb3-local' 连接器"
echo "   3. 测试: '查询 BSC Testnet 的链 ID'"
echo ""
echo "🛠️  管理命令："
echo "   查看隧道状态: ./scripts/tunnel-manager.sh status"
echo "   停止隧道:     ./scripts/tunnel-manager.sh stop"
echo "   重启隧道:     ./scripts/tunnel-manager.sh restart"
echo "   更新配置:     ./scripts/update-claude-config.sh"
echo ""
