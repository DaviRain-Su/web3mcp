# MCP Apps Integration Guide

✅ UI组件已成功集成到Zig MCP服务器！

## 功能概述

omniweb3-mcp服务器现在支持MCP Apps，为以下工具提供交互式UI：

1. **get_transaction** - 交易查看器
2. **get_swap_quote / execute_swap** - 交换界面（未来）
3. **get_wallet_balance** - 余额仪表板（未来）

## 工作原理

### 1. 工具响应包含UI元数据

当调用`get_transaction`工具时，响应JSON包含`_meta`字段：

```json
{
  "chain": "bsc",
  "network": "testnet",
  "transaction": { ... },
  "_meta": {
    "ui": {
      "resourceUri": "ui://transaction?chain=bsc&txHash=0x...&network=testnet"
    }
  }
}
```

### 2. MCP Host渲染UI

支持MCP Apps的Host（如Claude Desktop）会：
- 检测响应中的`_meta.ui.resourceUri`字段
- 请求`ui://transaction`资源
- 在iframe中渲染HTML/CSS/JS
- 通过postMessage建立双向通信

### 3. UI与MCP服务器通信

UI组件通过postMessage发送JSON-RPC请求：

```javascript
// UI发送
window.parent.postMessage({
  jsonrpc: '2.0',
  id: 1,
  method: 'tools/call',
  params: {
    name: 'get_transaction',
    arguments: { chain: 'bsc', tx_hash: '0x...' }
  }
}, '*');

// 接收响应
window.addEventListener('message', (event) => {
  const response = event.data; // JSON-RPC响应
});
```

## 实现细节

### Zig端实现

#### 1. UI资源嵌入 (`src/ui/resources.zig`)

```zig
pub const Resources = struct {
    pub const transaction_html = @embedFile("../../ui/dist/src/transaction/index.html");
    pub const transaction_js = @embedFile("../../ui/dist/assets/transaction-405npdBf.js");
    // ... 其他资源文件
};
```

#### 2. UI元数据生成 (`src/ui/meta.zig`)

```zig
pub const UiMeta = struct {
    /// 为交易查看器创建UI元数据
    pub fn transaction(allocator, chain, tx_hash, network) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            "ui://transaction?chain={s}&txHash={s}&network={s}",
            .{ chain, tx_hash, network },
        );
    }
};

/// 在JSON响应中添加_meta字段
pub fn createUiResult(allocator, data_json, ui_resource_uri) ![]const u8 {
    // 在JSON末尾添加: ,"_meta":{"ui":{"resourceUri":"ui://..."}}
}
```

#### 3. 工具响应修改 (`src/tools/unified/transaction.zig`)

```zig
const ui_meta = @import("../../ui/meta.zig");

pub fn handle(allocator, args) !mcp.tools.ToolResult {
    // ... 获取交易数据 ...

    // 创建基础响应JSON
    const response = std.fmt.allocPrint(...);

    // 添加UI元数据
    const ui_resource_uri = ui_meta.UiMeta.transaction(
        allocator, chain_name, tx_hash_str, network
    );
    const response_with_ui = ui_meta.createUiResult(
        allocator, response, ui_resource_uri
    );

    return mcp.tools.textResult(allocator, response_with_ui);
}
```

### JavaScript端实现

#### MCP Client (`ui/src/lib/mcp-client.ts`)

```typescript
export class MCPClient {
  async callTool<T>(name: string, args: Record<string, any>): Promise<ToolCallResult<T>> {
    const request: MCPRequest = {
      jsonrpc: '2.0',
      id: ++this.requestId,
      method: 'tools/call',
      params: { name, arguments: args },
    };

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      window.parent.postMessage(request, '*');

      setTimeout(() => {
        if (this.pending.has(id)) {
          reject(new Error('Request timeout'));
        }
      }, 30000);
    });
  }
}
```

#### React Hook (`ui/src/hooks/useMCP.ts`)

```typescript
export function useMCP(): MCPClient | null {
  const [client, setClient] = useState<MCPClient | null>(null);

  useEffect(() => {
    getMCPClient().then((c) => {
      setClient(c);
    });
  }, []);

  return client;
}
```

## 测试

### 1. 命令行测试

```bash
# 编译Zig服务器
zig build

# 测试get_transaction工具
./zig-out/bin/omniweb3-mcp <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_transaction","arguments":{"chain":"bsc","tx_hash":"0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa","network":"testnet"}}}
EOF
```

预期输出包含：
```json
"_meta": {
  "ui": {
    "resourceUri": "ui://transaction?chain=bsc&txHash=0x...&network=testnet"
  }
}
```

### 2. UI本地开发

```bash
cd ui
npm run dev
```

访问: http://localhost:5175/src/transaction/?mock=true

### 3. Claude Desktop集成

1. 配置Claude Desktop MCP服务器：

```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/path/to/omniweb3-mcp/zig-out/bin/omniweb3-mcp"
    }
  }
}
```

2. 重启Claude Desktop

3. 测试命令：
```
Get transaction 0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa on bsc testnet
```

4. 查看交互式UI（如果Claude Desktop支持MCP Apps）

## 构建产物

```bash
# UI构建
cd ui && npm run build

# 输出位置
ui/dist/src/transaction/index.html    # Transaction Viewer
ui/dist/src/swap/index.html           # Swap Interface
ui/dist/src/balance/index.html        # Balance Dashboard
ui/dist/assets/*.js                   # JavaScript bundles
ui/dist/assets/*.css                  # CSS styles
```

所有文件通过`@embedFile()`嵌入到Zig二进制中，无需部署额外文件。

## 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      MCP Host (Claude Desktop)               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Main UI                                                │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │  iframe: ui://transaction?chain=bsc&txHash=...   │  │ │
│  │  │                                                    │  │ │
│  │  │  ┌──────────────────────────────────────────┐    │  │ │
│  │  │  │  React App (Transaction Viewer)          │    │  │ │
│  │  │  │  - Display transaction details           │    │  │ │
│  │  │  │  - Gas analysis chart                    │    │  │ │
│  │  │  │  - Copy/share buttons                    │    │  │ │
│  │  │  └──────────────────────────────────────────┘    │  │ │
│  │  │              ↕ postMessage (JSON-RPC)            │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ↕ stdio (JSON-RPC)                 │
└─────────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────────┐
│              omniweb3-mcp (Zig MCP Server)                  │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │ Tool Handlers    │  │ UI Resources     │                │
│  │ - get_transaction│→ │ @embedFile(...)  │                │
│  │ - get_balance    │  │ - HTML/CSS/JS    │                │
│  │ - execute_swap   │  │ - Assets         │                │
│  └──────────────────┘  └──────────────────┘                │
│            ↓                                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Response with _meta.ui.resourceUri                   │  │
│  │ {"transaction":{...},"_meta":{"ui":{"resourceUri":""│  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                    Blockchain Networks                      │
│  - BSC Testnet/Mainnet                                      │
│  - Ethereum                                                  │
│  - Polygon                                                   │
│  - Solana                                                    │
└─────────────────────────────────────────────────────────────┘
```

## 下一步

### 已完成 ✅
- [x] UI组件开发 (Transaction, Swap, Balance)
- [x] Mock模式本地开发
- [x] UI资源嵌入到Zig二进制
- [x] `_meta.ui.resourceUri`字段支持
- [x] get_transaction工具集成

### 待完成 ⏭️
- [ ] MCP Resources支持 (`ui://` 协议处理)
- [ ] get_swap_quote / execute_swap UI集成
- [ ] get_wallet_balance UI集成
- [ ] Claude Desktop实际测试
- [ ] 性能优化（bundle size reduction）
- [ ] 错误处理完善

## 注意事项

1. **MCP Apps支持**: 目前MCP Apps仍在实验阶段，并非所有MCP Host都支持
2. **资源大小**: UI bundles总计~500KB，通过gzip可压缩到~120KB
3. **浏览器兼容性**: 需要现代浏览器支持ES2020+
4. **安全性**: iframe sandbox隔离，仅通过postMessage通信

## 参考资料

- [MCP Apps Documentation](https://spec.modelcontextprotocol.io/specification/basic/ui/)
- [MCP Protocol Specification](https://spec.modelcontextprotocol.io/)
- [React Documentation](https://react.dev/)
- [Mantine UI Components](https://mantine.dev/)
