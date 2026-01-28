# Omniweb3 MCP - Smart Web3 MCP Server

**一个配置，175 工具，无限可能！**

Cross-chain Web3 MCP server with smart contract discovery and unified interfaces.

---

## 🎯 核心特性

### Smart Architecture
- **单一配置**：只需要一个 MCP 服务器
- **工具数量少**：175 个工具（不会超限）
- **功能完整**：支持所有区块链和无限合约
- **自然体验**：发现 → 调用的直观流程

### 支持的区块链
- **EVM**: BSC, Ethereum, Polygon, Avalanche
- **Solana**: Mainnet, Testnet, Devnet

### 核心能力
- 🔍 **合约发现**：`discover_contracts` - 列出可用智能合约
- 🌐 **链发现**：`discover_chains` - 列出支持的区块链
- 💰 **统一接口**：`get_balance`, `transfer`, `call_contract` - 跨链操作
- 🔧 **链特定工具**：Gas 估算、区块查询、交易构建等

---

## 🚀 快速开始

### 1. 编译

```bash
git clone <repo-url>
cd omniweb3-mcp
zig build
```

### 2. 配置 Claude Desktop

编辑 `~/Library/Application Support/Claude/claude_desktop_config.json`：

```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/path/to/omniweb3-mcp/scripts/run.sh"
    }
  }
}
```

### 3. 配置钱包（可选）

如果需要签名交易：

```bash
# EVM wallet
mkdir -p ~/.config/evm
cat > ~/.config/evm/keyfile.json << EOF
{
  "private_key": "your_private_key_here"
}
EOF

# Solana wallet
mkdir -p ~/.config/solana
cat > ~/.config/solana/id.json << EOF
[your,keypair,array,here]
EOF
```

### 4. 重启 Claude Desktop

配置修改后重启 Claude Desktop 即可使用。

---

## 💡 使用示例

### 发现可用合约

```
你：有哪些智能合约可用？

AI 调用: discover_contracts()
返回: BSC 测试网的 PancakeSwap, WBNB, BUSD...
```

### 查询余额

```
你：查询我的 BSC 测试网 BNB 余额

AI 调用: get_balance(chain="bsc", chain_id=97)
返回: 0.3 BNB
```

### 交换代币

```
你：在 BSC 测试网上用 PancakeSwap 交换 0.1 WBNB 为 BUSD

AI:
1. discover_contracts() → 找到 PancakeSwap
2. call_contract(...) → 执行 swap
```

---

## 🏗️ 架构设计

### 工具组成

```
omniweb3-mcp (175 tools)
├── 静态工具 (173 个)
│   ├── common: wallet, sign, encode/decode
│   ├── unified: get_balance, transfer, call_contract
│   ├── evm: estimate_gas, get_block, get_transaction
│   └── solana: get_slot, get_epoch, get_signatures
└── 发现工具 (2 个)
    ├── discover_contracts
    └── discover_chains
```

### 工作流程

```
用户提问
  ↓
AI 调用 discover_contracts() 发现可用合约
  ↓
AI 调用 call_contract() 执行操作
  ↓
返回结果
```

---

## 📊 对比

| 特性 | 传统方案 | Smart MCP |
|------|---------|-----------|
| MCP 服务器数量 | 1 (超限) or 3-5 (复杂) | **1** ✅ |
| 工具数量 | 1034+ | **175** ✅ |
| 上下文占用 | ~206K tokens | **~35K tokens** ✅ |
| 配置复杂度 | 简单 or 复杂 | **最简单** ✅ |
| 功能完整性 | 完整 | **完整** ✅ |

---

## 🔧 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `BSC_RPC_URL` | `https://bsc-dataseed1.binance.org` | BSC RPC 端点 |
| `ETH_RPC_URL` | `https://eth.llamarpc.com` | Ethereum RPC 端点 |
| `SOLANA_RPC_URL` | `https://api.mainnet-beta.solana.com` | Solana RPC 端点 |

---

## 📚 文档

- **[START_HERE.md](./START_HERE.md)** - 快速开始指南
- **[SMART_MCP.md](./SMART_MCP.md)** - Smart MCP 设计详解
- **[BSC_TESTNET.md](./BSC_TESTNET.md)** - BSC 测试网配置

---

## 🧪 测试

### BSC 测试网

1. 获取测试币：https://testnet.binance.org/faucet-smart
2. 配置钱包（见上方）
3. 在 Claude Desktop 中测试：
   - "查询我的 BSC 测试网余额"
   - "在 BSC 测试网上交换代币"

---

## 🛠️ 开发

### 编译

```bash
zig build                 # Debug build
zig build -Doptimize=ReleaseFast  # Release build
```

### 测试

```bash
zig build test
```

### 项目结构

```
omniweb3-mcp/
├── src/
│   ├── main.zig          # 主入口（Smart MCP）
│   ├── core/             # 核心功能
│   ├── tools/            # MCP 工具
│   │   ├── common/       # 通用工具
│   │   ├── unified/      # 统一接口
│   │   ├── evm/          # EVM 工具
│   │   └── solana/       # Solana 工具
│   └── providers/        # 区块链提供者
├── abi_registry/         # EVM 合约 ABI
├── scripts/              # 启动脚本
└── build.zig             # 构建配置
```

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 📄 License

MIT License

---

## 🎉 总结

**Omniweb3 MCP = 简单 + 强大 + 优雅**

- ✅ 只需要配置 1 个服务器
- ✅ 只有 175 个工具（不会超限）
- ✅ 支持所有区块链和无限合约
- ✅ 自然的发现 → 调用流程

**这才是真正优雅的系统设计！** 🎨✨
