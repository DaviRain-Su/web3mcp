# 测试和使用指南

## 📁 精简后的文件结构

### 脚本（3个）

1. **start-bsc-testnet.sh** - 启动 BSC Testnet 模式服务器
2. **test-bsc-testnet.sh** - 综合测试脚本（包含所有常用测试）
3. **setup-wallet.sh** - 钱包设置工具

### 文档（1个）

1. **BSC_TESTNET.md** - BSC Testnet 完整使用指南

## 🚀 快速开始

### 1. 启动服务器

```bash
./scripts/start-bsc-testnet.sh
```

### 2. 运行测试

```bash
# 在另一个终端
./scripts/test-bsc-testnet.sh
```

### 3. 查看文档

```bash
cat BSC_TESTNET.md
```

## 📊 服务器状态

- **工具总数**: 1057
  - 静态工具: 173
  - 动态合约工具: 884
- **支持链**: BSC, Ethereum, Polygon, Avalanche
- **支持网络**: mainnet, testnet
- **macOS**: 完全支持 ✅

## 🔑 关键信息

**链名称映射**:
- BSC/BNB Chain → `"bnb"`
- Ethereum → `"ethereum"`
- Polygon → `"polygon"`

**工具调用格式**: MCP JSON-RPC

**钱包位置**: `~/.config/evm/keyfile.json`

## 📝 文件清单

### 保留的文件

```
scripts/
├── start-bsc-testnet.sh     ✅ 启动服务器
├── test-bsc-testnet.sh      ✅ 综合测试
└── setup-wallet.sh          ✅ 钱包设置

BSC_TESTNET.md               ✅ 使用指南
README_TESTING.md            ✅ 本文档
```

### 已清理的文件

```
❌ complete-bsc-test.sh
❌ quick-test-bsc.sh
❌ test-bsc.sh
❌ test-wallet.sh
❌ simple-bsc-test.sh
❌ test-bsc-contracts.sh
❌ test-bsc-simple.sh
❌ test-bsc-wbnb.sh

❌ BSC_TESTNET_GUIDE.md
❌ BSC_TEST_README.md
❌ BSC_CONTRACT_TEST_GUIDE.md
❌ QUICK_START_BSC.md
❌ WALLET_CONFIG_GUIDE.md
```

---

简洁明了，所有必要功能都在 3 个脚本 + 1 个文档中！
