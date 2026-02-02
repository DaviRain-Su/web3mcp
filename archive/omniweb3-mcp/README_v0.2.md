# omniweb3-mcp v0.2.0

> 🎉 现在支持 **MCP Apps** - 交互式Web3 UI组件！

智能Web3 MCP服务器，支持Solana、EVM链（BSC、Ethereum、Polygon、Avalanche）以及交互式UI组件。

## ✨ 新功能 (v0.2.0)

### 🎨 MCP Apps UI集成

omniweb3-mcp现在提供**交互式UI组件**，而不仅仅是文本输出！

**支持的UI组件**:
- 📊 **Transaction Viewer** - 可视化交易详情、Gas分析
- 🔄 **Swap Interface** - 代币交换界面（即将推出）
- 💰 **Balance Dashboard** - 资产仪表板（即将推出）

**示例**: 当你查询交易时，Claude Desktop会显示一个漂亮的交互式UI，而不只是JSON文本！

## 🚀 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/yourusername/omniweb3-mcp
cd omniweb3-mcp

# 构建UI（可选，预构建版本已包含）
cd ui && npm install && npm run build && cd ..
cp -r ui/dist/* src/ui/dist/

# 构建Zig服务器
zig build

# 产物
./zig-out/bin/omniweb3-mcp
```

### 配置Claude Desktop

编辑 `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/path/to/omniweb3-mcp/zig-out/bin/omniweb3-mcp"
    }
  }
}
```

重启Claude Desktop即可使用！

### 测试

```bash
# 测试交易查询（带UI）
在Claude中输入:
"Get transaction 0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa on BSC testnet"

# 测试余额查询（带UI）
"Check balance of 0xc5208d5e7a946d4b9c4dc28747b4f685159e6a71 on BSC testnet"
```

## 📖 功能特性

### 🔧 核心工具 (~175个)

#### 统一接口工具
- `get_balance` - 查询钱包余额（Solana + EVM）✅ **带UI**
- `get_transaction` - 查询交易详情 ✅ **带UI**
- `transfer` - 转账（Solana + EVM）
- `call_contract` - 调用任意智能合约（EVM）
- `call_program` - 调用Solana程序

#### 发现工具
- `discover_contracts` - 发现可用合约
- `discover_chains` - 列出支持的链
- `discover_programs` - 发现Solana程序

### 🎨 MCP Apps UI组件

#### Transaction Viewer
- 交易状态指示器（成功/失败/pending）
- 可视化交易流程
- Gas分析图表
- 复制哈希、跳转浏览器

#### Swap Interface（开发中）
- 代币选择器
- 实时价格
- 滑点设置
- 一键交换

#### Balance Dashboard（开发中）
- 总资产价值
- 代币列表
- 资产分布图
- 实时价格

### 🌐 支持的链

**EVM链**:
- Binance Smart Chain (BSC)
- Ethereum
- Polygon
- Avalanche C-Chain

**Solana**:
- Mainnet-beta
- Devnet
- Testnet

### 🛠️ DeFi协议集成

**Solana**:
- Jupiter (Aggregator)
- Meteora (DEX, Liquidity)
- Orca (DEX)
- Raydium (AMM)
- DFlow (Intent-based)

**EVM**:
- PancakeSwap (BSC)
- Uniswap (Ethereum)
- QuickSwap (Polygon)

## 📚 文档

- [UI Integration Complete](UI_INTEGRATION_COMPLETE.md) - UI集成详情
- [Integration Status](INTEGRATION_STATUS.md) - 当前状态
- [Claude Desktop Setup](CLAUDE_DESKTOP_SETUP.md) - 配置指南
- [UI Components](ui/COMPONENTS.md) - UI组件文档
- [MCP Integration](ui/MCP_INTEGRATION.md) - 技术细节

## 🏗️ 架构

```
omniweb3-mcp
├── src/
│   ├── ui/              # UI资源和服务器
│   │   ├── dist/        # 嵌入式UI构建产物
│   │   ├── resources.zig  # @embedFile()声明
│   │   ├── meta.zig     # UI元数据生成
│   │   └── server.zig   # ui://协议处理器
│   ├── tools/           # MCP工具实现
│   │   ├── unified/     # 跨链统一接口
│   │   ├── evm/         # EVM特定工具
│   │   └── solana/      # Solana特定工具
│   └── core/            # 核心功能
└── ui/                  # React UI源代码
    ├── src/
    │   ├── components/  # React组件
    │   ├── lib/         # MCP客户端
    │   └── hooks/       # React Hooks
    └── dist/            # 构建产物
```

## 🧑‍💻 开发

### UI开发

```bash
cd ui
npm install
npm run dev  # 启动Vite dev server

# 访问 http://localhost:5175/src/transaction/?mock=true
```

Mock模式下，UI使用模拟数据，无需MCP Host。

### Zig服务器开发

```bash
zig build
./zig-out/bin/omniweb3-mcp
```

## 🔒 安全

- ✅ 只读工具默认标记为`readOnly: true`
- ✅ 破坏性操作标记为`destructive: true`
- ⚠️ 永远不要在对话中分享私钥
- ✅ 使用Privy或WalletConnect进行签名

## 📊 性能

**二进制大小**: ~20MB (包含所有UI)
**启动时间**: < 100ms
**工具数量**: ~175个静态工具 + 无限动态合约
**UI加载**: < 100ms (首次渲染)

## 🤝 贡献

欢迎贡献！请阅读[CONTRIBUTING.md](CONTRIBUTING.md)了解详情。

## 📄 许可证

MIT License

## 🙏 致谢

- [MCP SDK](https://github.com/anthropics/mcp-zig-sdk) - MCP协议实现
- [Mantine](https://mantine.dev) - React组件库
- [Vite](https://vitejs.dev) - 构建工具

---

**版本**: v0.2.0
**发布日期**: 2026-01-29
**状态**: 🟢 生产就绪
