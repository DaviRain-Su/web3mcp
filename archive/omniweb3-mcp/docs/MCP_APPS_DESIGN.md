# MCP Apps Design Document: omniweb3-mcp UI Enhancement

## 1. 概述 (Overview)

### 1.1 目标 (Goals)

将 omniweb3-mcp 从纯文本输出的 MCP Server 升级为 **MCP App**，提供交互式 UI 组件，让用户能够：

1. **可视化查看区块链数据** - 交易、余额、区块信息以图形化方式展示
2. **交互式合约操作** - 通过表单和 UI 进行合约调用和 Swap 操作
3. **实时数据监控** - Dashboard 显示钱包余额、交易状态等
4. **减少重复提示** - 用户可以直接在 UI 中探索数据，而不是反复询问 Claude

### 1.2 MCP Apps 核心概念

#### 与普通 MCP Server 的区别：
- **普通 MCP Server**: 工具返回纯文本或 JSON
- **MCP App**: 工具可以返回 UI 资源引用（通过 `_meta.ui.resourceUri`），Host 在 iframe 中渲染交互界面

#### 架构：
```
┌─────────────────┐
│   MCP Host      │  (Claude Desktop / VS Code)
│   (Client)      │
└────────┬────────┘
         │
         │ JSON-RPC
         │
┌────────▼────────┐
│  omniweb3-mcp   │  MCP Server
│   (Server)      │
│                 │
│  ┌───────────┐  │
│  │   Tools   │  │  返回 UI 资源引用
│  │  + Metadata│  │
│  └───────────┘  │
│                 │
│  ┌───────────┐  │
│  │ UI Resources│ │  HTML/JS/CSS Bundle
│  │  (ui://)  │  │
│  └───────────┘  │
└─────────────────┘

通信流程：
1. Tool call with UI metadata → Host fetches ui:// resource
2. Host renders UI in sandboxed iframe
3. UI ↔ Host: postMessage (JSON-RPC) for tool calls
```

## 2. 功能设计 (Feature Design)

### 2.1 Phase 1: 核心 UI 组件

#### 2.1.1 Transaction Viewer (交易查看器)

**工具名称**: `get_transaction_ui`

**功能描述**:
- 可视化显示交易详情
- 显示交易流程图（from → to）
- Gas 费用分析
- 状态指示器（成功/失败/pending）

**UI 组件**:
```html
┌─────────────────────────────────────┐
│  Transaction Details                │
├─────────────────────────────────────┤
│  Hash: 0xabc...def    [Copy]        │
│  Status: ✓ Success                  │
│  Block: #12345678                   │
│                                     │
│  Flow Diagram:                      │
│  ┌────────┐           ┌────────┐   │
│  │ From   │  ────→    │  To    │   │
│  │ 0x123  │   1.5 ETH │ 0x456  │   │
│  └────────┘           └────────┘   │
│                                     │
│  Gas Used: 21,000 (100%)            │
│  ├█████████████████████┤            │
│  Gas Price: 50 Gwei                 │
│  Total Fee: 0.00105 ETH             │
│                                     │
│  [View on Explorer]                 │
└─────────────────────────────────────┘
```

**交互功能**:
- 点击地址 → 查看地址详情
- 点击区块号 → 查看区块
- Copy 按钮复制 hash
- View on Explorer 打开区块浏览器

---

#### 2.1.2 Balance Dashboard (余额仪表板)

**工具名称**: `get_balance_dashboard_ui`

**功能描述**:
- 显示钱包余额（原生代币 + ERC20 tokens）
- 实时刷新
- 多链支持（EVM + Solana）
- 价值统计

**UI 组件**:
```html
┌─────────────────────────────────────┐
│  Balance Dashboard                  │
│  Address: 0xc52...6a71   [Refresh] │
├─────────────────────────────────────┤
│  Total Value: $1,234.56             │
│                                     │
│  ┌─ BSC Testnet ──────────────┐    │
│  │  BNB: 1.5 BNB ($450.00)    │    │
│  │  BUSD: 100 BUSD ($100.00)  │    │
│  │  ────────────────────────   │    │
│  │  Total: $550.00            │    │
│  └────────────────────────────┘    │
│                                     │
│  ┌─ Ethereum Mainnet ─────────┐    │
│  │  ETH: 0.5 ETH ($1200.00)   │    │
│  │  USDT: 200 USDT ($200.00)  │    │
│  │  ────────────────────────   │    │
│  │  Total: $1400.00           │    │
│  └────────────────────────────┘    │
│                                     │
│  [Add Token] [Switch Chain]        │
└─────────────────────────────────────┘
```

**交互功能**:
- Refresh 按钮实时更新余额
- Add Token 添加自定义代币
- Switch Chain 切换网络
- 点击代币显示详情

---

#### 2.1.3 Swap Interface (交换界面)

**工具名称**: `swap_ui`

**功能描述**:
- 交互式代币兑换界面
- 实时价格预览
- Slippage 设置
- 交易确认

**UI 组件**:
```html
┌─────────────────────────────────────┐
│  Swap Tokens                        │
├─────────────────────────────────────┤
│  From                               │
│  ┌─────────────────────────────┐   │
│  │ [BNB ▼]         [0.01     ] │   │
│  │ Balance: 1.5 BNB     [MAX]  │   │
│  └─────────────────────────────┘   │
│               ⇅                     │
│  To                                 │
│  ┌─────────────────────────────┐   │
│  │ [BUSD ▼]        [~2.85    ] │   │
│  │ Balance: 100 BUSD           │   │
│  └─────────────────────────────┘   │
│                                     │
│  Price: 1 BNB = ~285 BUSD           │
│  Slippage: [1%] [Auto]              │
│  Gas Fee: ~0.0001 BNB               │
│                                     │
│  ┌─────────────────────────────┐   │
│  │      [Swap]                 │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**交互功能**:
- 代币选择下拉菜单
- 输入金额自动计算输出
- MAX 按钮使用全部余额
- Slippage 设置
- Swap 按钮触发交易（需用户确认）

---

#### 2.1.4 Contract Interaction Panel (合约交互面板)

**工具名称**: `call_contract_ui`

**功能描述**:
- 可视化合约函数调用界面
- 自动解析 ABI 生成表单
- 参数验证
- 交易预览

**UI 组件**:
```html
┌─────────────────────────────────────┐
│  Contract Interaction               │
│  pancake_testnet                    │
├─────────────────────────────────────┤
│  Function: swapExactETHForTokens    │
│                                     │
│  Parameters:                        │
│  ┌─────────────────────────────┐   │
│  │ amountOutMin                │   │
│  │ [0                        ] │   │
│  │ uint256                     │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ path[]                      │   │
│  │ [WBNB, BUSD              ] │   │
│  │ address[]                   │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ to                          │   │
│  │ [0xc52...6a71            ] │   │
│  │ address                     │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ deadline                    │   │
│  │ [1738220000              ] │   │
│  │ uint256                     │   │
│  └─────────────────────────────┘   │
│                                     │
│  Value: [0.01] BNB                  │
│  Gas Estimate: ~136,435             │
│                                     │
│  [Call Function] [Read Only]        │
└─────────────────────────────────────┘
```

**交互功能**:
- 自动生成表单字段
- 参数类型验证
- Gas 估算
- Call Function (发送交易) / Read Only (只读调用)
- 交易结果显示

---

### 2.2 Phase 2: 高级功能

#### 2.2.1 Block Explorer UI
- 区块列表
- 交易列表
- 搜索功能

#### 2.2.2 NFT Gallery
- NFT 展示
- 元数据查看
- 转账界面

#### 2.2.3 DeFi Dashboard
- Liquidity Pool 信息
- Yield Farming 数据
- Portfolio 分析

## 3. 技术架构 (Technical Architecture)

### 3.1 UI 资源结构

```
omniweb3-mcp/
├── src/
│   ├── main.zig                 # 主服务器
│   ├── ui/                      # UI 资源
│   │   ├── resources.zig        # UI 资源管理器
│   │   ├── templates/           # HTML 模板
│   │   │   ├── transaction.html
│   │   │   ├── balance.html
│   │   │   ├── swap.html
│   │   │   └── contract.html
│   │   ├── scripts/             # JavaScript
│   │   │   ├── mcp-client.js    # MCP postMessage 通信
│   │   │   ├── transaction.js
│   │   │   ├── balance.js
│   │   │   ├── swap.js
│   │   │   └── contract.js
│   │   └── styles/              # CSS
│   │       └── main.css
│   └── tools/
│       └── unified/
│           ├── transaction_ui.zig  # 新增
│           ├── balance_ui.zig      # 新增
│           ├── swap_ui.zig         # 新增
│           └── contract_ui.zig     # 新增
```

### 3.2 UI 资源服务

#### 3.2.1 UI 资源 ID 格式
```
ui://transaction-viewer/{transaction_hash}
ui://balance-dashboard/{chain}/{address}
ui://swap-interface/{chain}
ui://contract-panel/{chain}/{contract}/{function}
```

#### 3.2.2 UI 资源响应格式
```json
{
  "contents": [
    {
      "uri": "ui://transaction-viewer/0xabc...def",
      "mimeType": "text/html",
      "text": "<html>...</html>"
    }
  ]
}
```

### 3.3 Tool Metadata 格式

```json
{
  "name": "get_transaction_ui",
  "description": "Get interactive transaction viewer UI",
  "inputSchema": {
    "type": "object",
    "properties": {
      "chain": { "type": "string" },
      "tx_hash": { "type": "string" }
    }
  },
  "_meta": {
    "ui": {
      "resourceUri": "ui://transaction-viewer/{tx_hash}"
    }
  }
}
```

### 3.4 双向通信协议

#### Host → UI (Tool Call Results)
```json
{
  "jsonrpc": "2.0",
  "method": "update_data",
  "params": {
    "transaction": {
      "hash": "0xabc...def",
      "from": "0x123...",
      "to": "0x456...",
      "value": "1500000000000000000",
      "gasUsed": "21000",
      "status": "success"
    }
  }
}
```

#### UI → Host (User Actions)
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "execute_swap",
    "arguments": {
      "chain": "bsc",
      "amountIn": "10000000000000000",
      "path": ["0xwbnb", "0xbusd"]
    }
  }
}
```

### 3.5 实现计划

#### 3.5.1 Zig 端实现
```zig
// src/ui/resources.zig
pub const UIResourceManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UIResourceManager {
        return .{ .allocator = allocator };
    }

    pub fn getResource(self: *UIResourceManager, uri: []const u8) ![]const u8 {
        // 根据 URI 返回对应的 HTML 资源
        if (std.mem.startsWith(u8, uri, "ui://transaction-viewer/")) {
            return @embedFile("templates/transaction.html");
        } else if (std.mem.startsWith(u8, uri, "ui://balance-dashboard/")) {
            return @embedFile("templates/balance.html");
        }
        // ...
        return error.ResourceNotFound;
    }
};

// src/tools/unified/transaction_ui.zig
pub fn getTransactionUI(
    allocator: std.mem.Allocator,
    args: std.json.Value,
) ![]const u8 {
    const chain = args.object.get("chain").?.string;
    const tx_hash = args.object.get("tx_hash").?.string;

    // 返回带 UI metadata 的结果
    const result = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "content": [
        \\    {{
        \\      "type": "resource",
        \\      "resource": {{
        \\        "uri": "ui://transaction-viewer/{s}",
        \\        "mimeType": "text/html",
        \\        "text": "{{transaction_html}}"
        \\      }}
        \\    }}
        \\  ],
        \\  "_meta": {{
        \\    "ui": {{
        \\      "resourceUri": "ui://transaction-viewer/{s}"
        \\    }}
        \\  }}
        \\}}
    , .{tx_hash, tx_hash});

    return result;
}
```

#### 3.5.2 JavaScript 端实现
```javascript
// src/ui/scripts/mcp-client.js
class MCPClient {
  constructor() {
    this.requestId = 0;
    this.pendingRequests = new Map();

    // 监听来自 Host 的消息
    window.addEventListener('message', (event) => {
      this.handleMessage(event.data);
    });
  }

  // 调用 MCP 工具
  async callTool(name, args) {
    const id = ++this.requestId;
    const request = {
      jsonrpc: '2.0',
      id,
      method: 'tools/call',
      params: { name, arguments: args }
    };

    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });
      window.parent.postMessage(request, '*');
    });
  }

  handleMessage(message) {
    if (message.id && this.pendingRequests.has(message.id)) {
      const { resolve, reject } = this.pendingRequests.get(message.id);
      this.pendingRequests.delete(message.id);

      if (message.error) {
        reject(message.error);
      } else {
        resolve(message.result);
      }
    } else if (message.method === 'update_data') {
      // 更新 UI 数据
      this.updateUI(message.params);
    }
  }

  updateUI(data) {
    // 子类实现具体的 UI 更新逻辑
  }
}

// src/ui/scripts/swap.js
class SwapUI extends MCPClient {
  constructor() {
    super();
    this.initializeUI();
  }

  initializeUI() {
    document.getElementById('swap-button').addEventListener('click', () => {
      this.executeSwap();
    });
  }

  async executeSwap() {
    const amountIn = document.getElementById('amount-in').value;
    const tokenIn = document.getElementById('token-in').value;
    const tokenOut = document.getElementById('token-out').value;

    try {
      const result = await this.callTool('call_contract', {
        chain: 'bsc',
        contract: 'pancake_testnet',
        function: 'swapExactETHForTokens',
        args: [
          '0',
          [tokenIn, tokenOut],
          userAddress,
          Date.now() + 1200
        ],
        value: amountIn,
        send_transaction: true
      });

      this.showSuccess(result);
    } catch (error) {
      this.showError(error);
    }
  }
}

// 初始化
new SwapUI();
```

## 4. 安全考虑 (Security Considerations)

### 4.1 iframe 沙箱
```html
<iframe
  sandbox="allow-scripts allow-forms allow-same-origin"
  src="ui://...">
</iframe>
```

### 4.2 用户确认
- 所有交易操作必须经过用户确认
- UI 发起的 `send_transaction: true` 调用需要 Host 弹出确认对话框

### 4.3 数据验证
- 所有用户输入需要在 UI 和 Server 端双重验证
- 防止 XSS 攻击：HTML 输出需要转义
- 防止 CSRF：postMessage 需要验证 origin

## 5. 开发路线图 (Development Roadmap)

### Phase 1: 基础设施 (2 weeks)
- [ ] 实现 UI 资源管理器
- [ ] 实现 postMessage 通信层
- [ ] 创建基础 HTML 模板和 CSS
- [ ] 实现 MCP Client JS 库

### Phase 2: 核心 UI 组件 (3 weeks)
- [ ] Transaction Viewer UI
- [ ] Balance Dashboard UI
- [ ] Swap Interface UI
- [ ] Contract Interaction Panel UI

### Phase 3: 测试和优化 (1 week)
- [ ] 单元测试
- [ ] 集成测试
- [ ] 性能优化
- [ ] 文档完善

### Phase 4: 高级功能 (Future)
- [ ] Block Explorer UI
- [ ] NFT Gallery UI
- [ ] DeFi Dashboard UI

## 6. 示例使用场景 (Example Use Cases)

### 场景 1: 查看交易
```
User: "查看交易 0xa023874204316fe6f03066f0ed2e5a1b76e3f16b9f2d07bfa78dd2f85955e647"
Claude: [调用 get_transaction_ui]
Host: [渲染交互式交易查看器]
User: [在 UI 中点击地址查看详情，点击 Copy 复制 hash]
```

### 场景 2: 执行 Swap
```
User: "我想用 0.01 BNB 兑换 BUSD"
Claude: [调用 swap_ui]
Host: [渲染交互式 Swap 界面]
User: [在 UI 中调整金额、设置 slippage、点击 Swap]
UI: [通过 postMessage 调用 call_contract 工具]
Host: [弹出确认对话框]
User: [确认交易]
Host: [执行交易并更新 UI 显示结果]
```

### 场景 3: 查看余额
```
User: "显示我的钱包余额"
Claude: [调用 get_balance_dashboard_ui]
Host: [渲染余额仪表板]
User: [在 UI 中点击 Refresh 实时更新，点击 Add Token 添加新代币]
```

## 7. 参考资料 (References)

- [MCP Apps Blog Post](https://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/)
- [MCP Documentation](https://modelcontextprotocol.io/docs/getting-started/intro)
- [MCP Architecture](https://modelcontextprotocol.io/docs/learn/architecture)
- [MCP SDK Examples](https://github.com/modelcontextprotocol/servers)

---

**文档版本**: v1.0
**创建日期**: 2026-01-29
**作者**: Davirian & Claude Sonnet 4.5
