# Claude Desktop集成设置指南

## 快速开始

### 1. 构建omniweb3-mcp服务器

```bash
cd /Users/davirian/dev/web3mcp/omniweb3-mcp

# 构建UI（如果有修改）
cd ui && npm run build && cd ..

# 复制UI产物到src目录
cp -r ui/dist/* src/ui/dist/

# 构建Zig服务器
zig build

# 验证构建
./zig-out/bin/omniweb3-mcp --help
```

### 2. 配置Claude Desktop

#### macOS

编辑配置文件:
```bash
nano ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

添加内容:
```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/Users/davirian/dev/web3mcp/omniweb3-mcp/zig-out/bin/omniweb3-mcp",
      "args": [],
      "env": {}
    }
  }
}
```

保存并退出 (Ctrl+O, Enter, Ctrl+X)

#### Windows

配置文件位置:
```
%APPDATA%\Claude\claude_desktop_config.json
```

内容相同，但路径需要改为Windows格式:
```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "C:\\path\\to\\omniweb3-mcp\\zig-out\\bin\\omniweb3-mcp.exe"
    }
  }
}
```

#### Linux

配置文件位置:
```
~/.config/Claude/claude_desktop_config.json
```

### 3. 重启Claude Desktop

完全退出Claude Desktop (⌘Q on macOS)，然后重新启动。

### 4. 验证集成

在Claude Desktop中输入:

```
List available MCP tools
```

应该看到omniweb3的工具列表:
- get_transaction
- get_balance
- transfer
- call_contract
- discover_contracts
- ...

### 5. 测试UI功能

#### 测试Transaction Viewer

```
Get transaction 0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa on BSC testnet
```

如果Claude Desktop支持MCP Apps，你应该看到:
1. 交易数据的文本输出
2. **交互式UI界面** (Transaction Viewer)

#### 测试Balance Dashboard

```
Check balance of address 0xc5208d5e7a946d4b9c4dc28747b4f685159e6a71 on BSC testnet
```

应该看到余额信息和交互式Balance Dashboard UI。

## 故障排查

### 问题1: Claude Desktop无法启动

**症状**: Claude Desktop启动后立即崩溃

**解决方案**:
1. 检查配置文件JSON格式是否正确
2. 验证服务器路径是否存在
   ```bash
   ls -la /Users/davirian/dev/web3mcp/omniweb3-mcp/zig-out/bin/omniweb3-mcp
   ```
3. 测试服务器是否可以独立运行
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ./zig-out/bin/omniweb3-mcp
   ```

### 问题2: 工具列表为空

**症状**: Claude说没有可用的工具

**解决方案**:
1. 查看Claude Desktop日志
   ```bash
   tail -f ~/Library/Logs/Claude/mcp*.log
   ```
2. 检查服务器stderr输出
   ```bash
   ./zig-out/bin/omniweb3-mcp 2>&1 | tee debug.log
   ```

### 问题3: UI不显示

**症状**: 工具可以调用，但没有UI

**可能原因**:
1. Claude Desktop版本不支持MCP Apps (需要最新版本)
2. `_meta.ui.resourceUri`字段未正确返回

**验证**:
```bash
# 测试_meta字段是否存在
./zig-out/bin/omniweb3-mcp <<EOF | grep "_meta"
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_transaction","arguments":{"chain":"bsc","tx_hash":"0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa","network":"testnet"}}}
EOF
```

应该看到:
```json
"_meta":{"ui":{"resourceUri":"ui://transaction?chain=bsc&txHash=..."}}
```

### 问题4: 权限错误

**症状**: Permission denied

**解决方案**:
```bash
chmod +x /Users/davirian/dev/web3mcp/omniweb3-mcp/zig-out/bin/omniweb3-mcp
```

## 高级配置

### 添加环境变量

```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/path/to/omniweb3-mcp",
      "env": {
        "LOG_LEVEL": "debug",
        "RPC_TIMEOUT": "30000"
      }
    }
  }
}
```

### 多网络配置

如果需要连接不同网络，可以创建多个MCP服务器实例:

```json
{
  "mcpServers": {
    "omniweb3-mainnet": {
      "command": "/path/to/omniweb3-mcp",
      "env": {
        "DEFAULT_NETWORK": "mainnet"
      }
    },
    "omniweb3-testnet": {
      "command": "/path/to/omniweb3-mcp",
      "env": {
        "DEFAULT_NETWORK": "testnet"
      }
    }
  }
}
```

## UI开发模式

如果你在开发UI，可以使用本地dev服务器:

```bash
# Terminal 1: 运行Vite dev server
cd ui && npm run dev

# Terminal 2: 测试MCP服务器
cd .. && ./zig-out/bin/omniweb3-mcp

# 访问 http://localhost:5175/src/transaction/?mock=true
```

Mock模式下，UI会使用模拟数据，无需真实的MCP Host。

## 日志和调试

### 查看MCP服务器日志

```bash
# macOS
tail -f ~/Library/Logs/Claude/mcp-server-omniweb3.log

# Linux
tail -f ~/.config/Claude/logs/mcp-server-omniweb3.log
```

### 启用详细日志

修改配置:
```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/path/to/omniweb3-mcp",
      "args": ["--verbose"],
      "env": {
        "DEBUG": "true"
      }
    }
  }
}
```

## 性能优化

### 减少启动时间

1. 使用Release构建:
   ```bash
   zig build -Doptimize=ReleaseFast
   ```

2. 预加载常用合约ABI

### 降低内存使用

修改环境变量:
```json
{
  "env": {
    "CACHE_SIZE": "100",
    "MAX_CONNECTIONS": "5"
  }
}
```

## 安全建议

1. **不要共享私钥**
   - 永远不要在Claude对话中输入私钥
   - 使用Privy或WalletConnect进行签名

2. **验证交易**
   - 在UI中仔细检查交易详情
   - 使用"Confirm"功能二次确认

3. **RPC端点**
   - 使用可信的RPC提供商
   - 考虑运行自己的节点

## 更新服务器

```bash
cd /Users/davirian/dev/web3mcp/omniweb3-mcp

# 拉取最新代码
git pull

# 重新构建UI
cd ui && npm run build && cd ..

# 复制UI产物
cp -r ui/dist/* src/ui/dist/

# 重新构建服务器
zig build

# 重启Claude Desktop
killall Claude && open -a Claude
```

## 支持和反馈

如果遇到问题:

1. 查看[INTEGRATION_STATUS.md](INTEGRATION_STATUS.md)了解已知问题
2. 查看[UI_INTEGRATION_COMPLETE.md](UI_INTEGRATION_COMPLETE.md)了解技术细节
3. 提交Issue到GitHub (如果开源)

---

**配置文件示例**: [claude-desktop-config.json](claude-desktop-config.json)
**测试脚本**: [ui/test-ui-integration.sh](ui/test-ui-integration.sh)
