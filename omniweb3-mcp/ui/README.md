# omniweb3-mcp UI Components

MCP Apps UI components for omniweb3-mcp server.

## 📦 项目结构

```
ui/
├── src/
│   ├── lib/
│   │   └── mcp-client.ts          # MCP postMessage 通信层
│   ├── hooks/
│   │   └── useMCP.ts               # React hooks for MCP
│   ├── types/
│   │   └── transaction.ts          # TypeScript 类型定义
│   ├── components/
│   │   └── TransactionViewer/      # ✅ Transaction Viewer 组件
│   │       └── index.tsx
│   ├── transaction/
│   │   ├── index.html              # Transaction Viewer 入口
│   │   └── main.tsx
│   ├── swap/
│   │   └── index.html              # Swap Interface (待实现)
│   └── balance/
│       └── index.html              # Balance Dashboard (待实现)
├── dist/                            # 构建输出
│   ├── assets/
│   │   ├── transaction-*.js
│   │   └── transaction-*.css
│   └── src/
│       ├── transaction/index.html
│       ├── swap/index.html
│       └── balance/index.html
├── package.json
├── vite.config.ts
└── tsconfig.json
```

## 🛠️ 技术栈

- **框架**: React 18.2 (原计划 Preact，改用 React for Mantine 兼容性)
- **UI 库**: Mantine 7.4 (现代化组件库)
- **图标**: Tabler Icons
- **构建工具**: Vite 5.0
- **语言**: TypeScript

## ✅ 已完成

### 1. **MCP Client 通信层** (`src/lib/mcp-client.ts`)
- ✅ postMessage 双向通信
- ✅ JSON-RPC 2.0 协议
- ✅ 请求超时处理
- ✅ 错误处理

### 2. **React Hooks** (`src/hooks/useMCP.ts`)
- ✅ `useMCP()`: 获取 MCP 客户端实例
- ✅ `useMCPTool()`: 调用 MCP 工具并管理加载状态

### 3. **Transaction Viewer** (`src/components/TransactionViewer/`)
- ✅ 交易头部（Hash + 状态徽章）
- ✅ 交易流程图（From → Value → To）
- ✅ 详细信息表格（Block、Timestamp、Network 等）
- ✅ Gas 分析（Gas Limit、Gas Used、Gas Price、Total Fee）
- ✅ 操作按钮（Refresh、View on Explorer）
- ✅ 自动刷新（Pending 交易每 10 秒刷新）
- ✅ 复制功能（Copy Hash）
- ✅ 错误处理

## 🚧 待实现

### 2. **Swap Interface**
- [ ] Token 选择器
- [ ] 金额输入
- [ ] 实时价格查询
- [ ] Slippage 设置
- [ ] 交易执行

### 3. **Balance Dashboard**
- [ ] 多链余额展示
- [ ] Token 列表
- [ ] 实时刷新
- [ ] Add Token 功能

## 📦 安装

```bash
npm install
```

## 🏗️ 构建

```bash
npm run build
```

构建输出在 `dist/` 目录：
- `dist/src/transaction/index.html` - Transaction Viewer
- `dist/src/swap/index.html` - Swap Interface (占位符)
- `dist/src/balance/index.html` - Balance Dashboard (占位符)

## 🚀 开发

```bash
npm run dev
```

然后访问：
- http://localhost:5173/src/transaction/index.html?chain=bsc&tx_hash=0x...&network=testnet

## 📝 URL 参数

### Transaction Viewer
- `chain`: 链名称 (e.g., `bsc`, `eth`, `polygon`)
- `tx_hash`: 交易 hash
- `network`: 网络 (e.g., `mainnet`, `testnet`)

示例:
```
transaction/index.html?chain=bsc&tx_hash=0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa&network=testnet
```

## 🔌 MCP 集成

UI 通过 `postMessage` 与 MCP Host 通信：

### UI → Host (Tool Call)
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_transaction",
    "arguments": {
      "chain": "bsc",
      "tx_hash": "0x...",
      "network": "testnet"
    }
  }
}
```

### Host → UI (Response)
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"transaction\":{...},\"receipt\":{...}}"
      }
    ]
  }
}
```

## 📊 构建大小

```
dist/src/transaction/index.html         0.77 kB │ gzip:  0.44 kB
dist/assets/transaction-*.css         201.49 kB │ gzip: 29.28 kB
dist/assets/transaction-*.js          288.37 kB │ gzip: 90.41 kB
```

总计: ~490 kB (未压缩) / ~120 kB (gzip)

## 🎨 UI 设计

参考 **Uniswap 简洁现代风格**：
- 色彩: Mantine 默认主题 (蓝色主题)
- 字体: Inter, -apple-system, BlinkMacSystemFont
- 圆角: 12px (medium)
- 间距: 8px grid system

## 🔧 下一步

1. **单文件打包**: 实现 single-file bundling (vite-plugin-singlefile)
2. **Swap Interface**: 实现完整的 Swap 界面
3. **Balance Dashboard**: 实现余额仪表板
4. **Zig 集成**: 在 Zig 端集成 UI 资源

---

**构建时间**: 2026-01-29
**构建者**: Davirian & Claude Sonnet 4.5
