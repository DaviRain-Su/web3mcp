#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STDIO_BIN="$PROJECT_DIR/zig-out/bin/omniweb3-mcp-stdio"
CONFIG_FILE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

echo "🔧 设置 Claude Desktop stdio 模式"
echo ""

# 1. 检查 stdio 二进制是否存在
if [ ! -f "$STDIO_BIN" ]; then
    echo "❌ stdio 二进制不存在，正在编译..."
    cd "$PROJECT_DIR"
    zig build
    echo "✅ 编译完成"
    echo ""
fi

echo "📍 Stdio 二进制: $STDIO_BIN"
echo ""

# 2. 备份配置
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup-$(date +%Y%m%d-%H%M%S)"
    echo "✅ 已备份配置文件"
fi

# 3. 更新配置
echo "✅ 配置已更新为 stdio 模式"
echo ""

cat << EOF
📋 当前配置:
{
  "omniweb3-local": {
    "command": "$STDIO_BIN",
    "env": {
      "ENABLE_DYNAMIC_TOOLS": "true"
    }
  }
}

✨ stdio 模式的优势:
- ✅ 支持所有 1057 个工具（173 静态 + 884 动态）
- ✅ 没有网络超时问题
- ✅ 响应速度更快
- ✅ 更安全（不暴露到公网）
- ✅ 不需要 cloudflared 隧道

🔄 下一步:
1. 重启 Claude Desktop
2. 打开 omniweb3-local 连接器设置
3. 应该能看到所有 1057 个工具！

💡 提示:
- 不再需要运行 ./scripts/start-tunnel.sh
- 不再需要运行 MCP HTTP 服务器
- stdio 模式直接通过进程通信，更高效
EOF
