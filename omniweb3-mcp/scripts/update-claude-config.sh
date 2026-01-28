#!/bin/bash

CONFIG_FILE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
TUNNEL_LOG="/tmp/omniweb3-tunnel.log"

# 获取当前隧道 URL
TUNNEL_URL=$(grep -oE "https://[^[:space:]]+" "$TUNNEL_LOG" | grep trycloudflare | head -1)

if [ -z "$TUNNEL_URL" ]; then
    echo "❌ 无法找到隧道 URL"
    echo "请确保隧道正在运行："
    echo "  ./scripts/tunnel-manager.sh status"
    exit 1
fi

echo "🔗 当前隧道 URL: $TUNNEL_URL"
echo ""

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Claude Desktop 配置文件不存在"
    echo "   路径: $CONFIG_FILE"
    exit 1
fi

# 备份配置文件
cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
echo "✅ 已备份配置文件"

# 使用 jq 更新配置
if command -v jq &> /dev/null; then
    # 更新 omniweb3-local 的 URL
    jq --arg url "$TUNNEL_URL/" \
       '.mcpServers["omniweb3-local"].args[2] = $url' \
       "$CONFIG_FILE.backup" > "$CONFIG_FILE"

    echo "✅ 已更新 Claude Desktop 配置"
    echo ""
    echo "新配置："
    jq '.mcpServers["omniweb3-local"]' "$CONFIG_FILE"
    echo ""
    echo "⚠️  请重启 Claude Desktop 使配置生效"
else
    echo "❌ 需要安装 jq 工具："
    echo "   brew install jq"
    exit 1
fi
