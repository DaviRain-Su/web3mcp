# BSC Testnet 使用指南

omniweb3-mcp 在 BSC Testnet 上的完整使用指南。

## 快速开始

### 1. 启动服务器

```bash
./scripts/start-bsc-testnet.sh
```

服务器配置：
- Host: 127.0.0.1
- Port: 8765
- Workers: 4
- 工具: 1057 个 (173 静态 + 884 动态)

### 2. 运行测试

```bash
# 在另一个终端
./scripts/test-bsc-testnet.sh
```

## 钱包配置

### 方法 1: 使用脚本生成（推荐）

```bash
./scripts/setup-wallet.sh
```

这会使用 Foundry 的 `cast` 工具生成新钱包并保存到 `~/.config/evm/keyfile.json`。

### 方法 2: 手动配置

创建文件 `~/.config/evm/keyfile.json`：

```json
{
  "private_key": "0x...",
  "address": "0x...",
  "description": "BSC Testnet Wallet"
}
```

**安全提示**: 文件权限应为 600 (仅所有者可读写)

## BSC Testnet 资源

### 水龙头
- https://testnet.bnbchain.org/faucet-smart

### 区块浏览器
- https://testnet.bscscan.com

### RPC 端点
- https://data-seed-prebsc-1-s1.binance.org:8545

### 测试网合约地址
- **WBNB**: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
- **BUSD**: 0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee
- **PancakeSwap Router V2**: 0xD99D1c33F9fC3444f8101754aBC46c52416550D1

## 工具使用

### 重要: 链名称

**BSC/BNB Chain 必须使用 `"bnb"` 作为链名称**，不是 "bsc"！

```json
{
  "chain": "bnb",      // ✅ 正确
  "network": "testnet"
}
```

### 常用静态工具

**查询余额**
```bash
curl -s -X POST http://127.0.0.1:8765/ -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_balance",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "address": "0xYOUR_ADDRESS"
    }
  }
}' | jq '.result.content[0].text'
```

**获取链 ID**
```bash
curl -s -X POST http://127.0.0.1:8765/ -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_chain_id",
    "arguments": {
      "chain": "bnb",
      "network": "testnet"
    }
  }
}' | jq '.result.content[0].text'
```

**查询代币余额**
```bash
curl -s -X POST http://127.0.0.1:8765/ -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "token_balance",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "token_address": "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
      "owner": "0xYOUR_ADDRESS"
    }
  }
}' | jq '.result.content[0].text'
```

**转账 BNB**
```bash
curl -s -X POST http://127.0.0.1:8765/ -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "transfer",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "to_address": "0xRECIPIENT_ADDRESS",
      "amount": "10000000000000000",
      "wallet_type": "local",
      "tx_type": "eip1559",
      "confirmations": 1
    }
  }
}' | jq '.'
```

### 可用工具列表

**Unified (跨链工具)**
- `get_balance` - 查询余额
- `get_block_number` - 获取区块号
- `get_block` - 获取区块详情
- `get_transaction` - 获取交易详情
- `token_balance` - 查询代币余额
- `transfer` - 转账
- `sign_and_send` - 签名并发送交易

**EVM 专用工具**
- `get_chain_id` - 获取链 ID
- `get_gas_price` - 获取 Gas 价格
- `get_nonce` - 获取地址 nonce
- `estimate_gas` - 估算 Gas
- `call` - 合约调用
- `get_receipt` - 获取交易收据
- `get_logs` - 获取事件日志
- `get_fee_history` - 获取 fee 历史

**动态合约工具 (884 个)**

从 `abi_registry/contracts.json` 自动生成，例如：
- `bsc_wbnb_*` - WBNB 合约方法 (主网)
- `bsc_pancakeswap_router_v2_*` - PancakeSwap 路由
- `bsc_busd_*`, `bsc_usdt_*` - 稳定币操作
- `ethereum_uniswap_*`, `ethereum_aave_*` - 以太坊 DeFi
- `polygon_quickswap_*`, `polygon_wmatic_*` - Polygon DeFi

**注意**: 动态工具配置的是主网地址。测试网建议使用静态工具。

## 工具参数说明

### 通用参数
- `chain`: 链名称 ("bnb", "ethereum", "polygon")
- `network`: 网络 ("mainnet", "testnet", "sepolia", etc.)
- `endpoint`: 自定义 RPC 端点 (可选)

### 地址和金额
- `address`: 以太坊地址 (0x 开头)
- `amount`: 金额字符串，以 wei 为单位
  - 1 BNB = 1000000000000000000 wei (18位小数)
  - 0.01 BNB = 10000000000000000 wei

### 钱包参数
- `wallet_type`: "local" 或 "privy"
- `tx_type`: "legacy" 或 "eip1559" (推荐)
- `confirmations`: 等待确认数 (1-12)

## 常见问题

**Q: 工具返回 "Unsupported chain: bsc"**
A: 使用 `"bnb"` 而不是 `"bsc"` 作为链名称

**Q: 如何查看所有可用工具？**
A:
```bash
curl -s -X POST http://127.0.0.1:8765/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | \
  jq -r '.result.tools[].name' | head -20
```

**Q: 动态工具需要 signer 参数？**
A: 是的。动态工具主要用于构建交易。对于只读查询，建议使用静态工具。

**Q: 如何测试网转账？**
A: 使用 `transfer` 工具，配置 `chain: "bnb"`, `network: "testnet"`，并确保钱包已配置。

**Q: 服务器启动慢？**
A: 服务器需要加载 884 个动态工具，大约需要 30 秒。耐心等待 "HTTP MCP listening" 消息。

## macOS 注意事项

本项目已完全支持 macOS：
- ✅ Socket 兼容性已修复
- ✅ SOCK_CLOEXEC/SOCK_NONBLOCK 通过 fcntl 实现
- ✅ 所有 4 个 workers 正常运行

如遇到问题，查看 `.claude/skills/zig-0.16/errors.md` 中的记录。

## 文件结构

```
omniweb3-mcp/
├── scripts/
│   ├── start-bsc-testnet.sh    # 启动服务器
│   ├── test-bsc-testnet.sh     # 运行测试
│   └── setup-wallet.sh         # 配置钱包
├── abi_registry/
│   ├── contracts.json          # 合约配置
│   ├── bsc/                    # BSC 合约 ABI
│   ├── ethereum/               # 以太坊合约 ABI
│   └── polygon/                # Polygon 合约 ABI
├── .env.bsc-testnet           # BSC Testnet 配置
└── BSC_TESTNET.md             # 本文档
```

## 相关命令

```bash
# 启动服务器
./scripts/start-bsc-testnet.sh

# 测试
./scripts/test-bsc-testnet.sh

# 检查健康状态
curl http://127.0.0.1:8765/health

# 停止服务器
pkill -f omniweb3-mcp

# 重新编译
zig build

# 查看配置
cat .env.bsc-testnet
```

## 成就

✅ macOS 完全兼容
✅ 1057 个工具可用
✅ BSC Testnet 连接成功
✅ 钱包配置完成
✅ 动态合约工具加载完成

你的 MCP 服务器已准备好进行 Web3 开发！🚀
