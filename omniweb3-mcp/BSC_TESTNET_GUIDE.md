# BSC Testnet 测试指南

本指南将帮助你快速测试 MCP Server 在 BSC（Binance Smart Chain）测试网上的功能。

## 📋 前置准备

### 1. 获取测试 BNB

访问 BSC 测试网水龙头获取测试 BNB：
- **官方水龙头**: https://testnet.bnbchain.org/faucet-smart
- 需要 GitHub 或 Twitter 账号
- 每次可获得 0.5 tBNB

### 2. 准备测试钱包地址

你需要一个 BSC 测试网地址和私钥（用于发送交易）：

```bash
# 生成新的测试钱包（使用 MetaMask 或其他工具）
# 或者使用现有的测试钱包
```

### 3. BSC Testnet 信息

- **Network Name**: BSC Testnet
- **Chain ID**: 97
- **RPC URL**: https://data-seed-prebsc-1-s1.binance.org:8545
- **Block Explorer**: https://testnet.bscscan.com
- **Symbol**: tBNB

## 🚀 快速开始

### 第 1 步：启动 MCP Server

```bash
# 从项目根目录运行
./scripts/start-bsc-testnet.sh
```

服务器将在 `http://127.0.0.1:8765` 启动。

### 第 2 步：运行测试脚本

打开**新的终端窗口**，运行测试：

```bash
./scripts/test-bsc.sh
```

测试脚本会验证：
- ✅ 服务器健康状态
- ✅ EVM 工具可用性
- ✅ BSC Testnet Chain ID (应该是 97)
- ✅ 获取最新区块号
- ✅ 获取当前 gas 价格
- ✅ 查询地址余额

## 🧪 可用的 EVM 工具

运行服务器后，可以使用以下工具与 BSC Testnet 交互：

### 查询类工具

#### 1. 获取链 ID
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_chain_id",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }'
```

#### 2. 获取账户余额
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_balance",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "address": "YOUR_ADDRESS_HERE"
    }
  }'
```

#### 3. 获取最新区块号
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_block_number",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }'
```

#### 4. 获取 Gas 价格
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_gas_price",
    "arguments": {
      "chain": "bsc",
      "network": "testnet"
    }
  }'
```

#### 5. 获取交易数量（nonce）
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_transaction_count",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "address": "YOUR_ADDRESS_HERE"
    }
  }'
```

#### 6. 获取区块信息
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_block_by_number",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "block_number": "latest"
    }
  }'
```

#### 7. 获取交易详情
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_transaction",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "tx_hash": "TRANSACTION_HASH_HERE"
    }
  }'
```

### 交易类工具

#### 8. 估算 Gas
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_estimate_gas",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "from": "YOUR_ADDRESS",
      "to": "RECIPIENT_ADDRESS",
      "value": "1000000000000000"
    }
  }'
```

#### 9. 发送转账
```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_send_transfer",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "private_key": "YOUR_PRIVATE_KEY",
      "from": "YOUR_ADDRESS",
      "to": "RECIPIENT_ADDRESS",
      "amount": "10000000000000000",
      "tx_type": "london",
      "confirmations": 1
    }
  }'
```

**⚠️ 注意**:
- 永远不要在主网使用测试私钥
- 不要提交包含真实私钥的代码到 git
- 建议使用环境变量存储私钥

## 📝 示例场景

### 场景 1: 查询账户信息

```bash
# 1. 检查余额
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_balance",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
    }
  }'

# 2. 检查交易计数
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_transaction_count",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
    }
  }'
```

### 场景 2: 发送测试交易

```bash
# 1. 估算 gas
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_estimate_gas",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "from": "YOUR_ADDRESS",
      "to": "0x0000000000000000000000000000000000000001",
      "value": "10000000000000000"
    }
  }'

# 2. 发送交易
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_send_transfer",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "private_key": "YOUR_PRIVATE_KEY",
      "from": "YOUR_ADDRESS",
      "to": "0x0000000000000000000000000000000000000001",
      "amount": "10000000000000000",
      "tx_type": "london",
      "confirmations": 1
    }
  }'

# 3. 在区块浏览器查看交易
# https://testnet.bscscan.com/tx/TRANSACTION_HASH
```

## 🔧 配置说明

### 环境变量配置

编辑 `.env.bsc-testnet` 文件：

```bash
# 服务器配置
HOST=127.0.0.1          # 监听地址
PORT=8765               # 监听端口
MCP_WORKERS=4           # 工作线程数

# 禁用动态工具以加快启动
ENABLE_DYNAMIC_TOOLS=false
```

### 自定义 RPC 端点

如果你想使用自己的 BSC RPC 节点：

```bash
# 通过工具参数传递 endpoint_override
{
  "name": "evm_get_balance",
  "arguments": {
    "chain": "bsc",
    "network": "testnet",
    "endpoint_override": "https://your-custom-rpc-url.com",
    "address": "YOUR_ADDRESS"
  }
}
```

## 📊 监控和调试

### 查看服务器日志

服务器日志会显示所有请求和响应：

```
[INFO] EVM runtime initialized
[INFO] Server listening on 127.0.0.1:8765
[INFO] Tool call: evm_get_chain_id (chain=bsc, network=testnet)
[INFO] Response: 97
```

### 健康检查

```bash
curl http://127.0.0.1:8765/health
```

### 列出所有工具

```bash
curl http://127.0.0.1:8765/mcp/v1/tools | jq '.tools[] | select(.name | startswith("evm_"))'
```

## 🐛 常见问题

### 1. 连接超时

**问题**: 连接 BSC testnet 超时

**解决方案**:
- 检查网络连接
- 尝试其他 RPC 端点：
  - https://bsc-testnet.public.blastapi.io
  - https://bsc-testnet-rpc.publicnode.com

### 2. Gas 价格过高

**问题**: 交易 gas 费用太高

**解决方案**:
- BSC testnet 的 gas 价格通常很低（~3 Gwei）
- 检查是否误用了主网配置

### 3. 交易失败

**问题**: 交易被 revert

**解决方案**:
- 检查账户余额是否足够
- 确认 nonce 值正确
- 在 https://testnet.bscscan.com 查看详细错误信息

## 🎯 下一步

1. **集成到 Claude Desktop**
   - 配置 MCP client 连接到服务器
   - 通过自然语言与 BSC testnet 交互

2. **测试智能合约交互**
   - 部署测试合约到 BSC testnet
   - 使用 `evm_call` 工具调用合约函数

3. **多链测试**
   - 测试其他 EVM 链（Ethereum, Polygon, Avalanche 等）
   - 使用相同的工具接口

## 📚 相关资源

- [BSC 官方文档](https://docs.bnbchain.org/)
- [BSC Testnet 浏览器](https://testnet.bscscan.com)
- [BSC Testnet 水龙头](https://testnet.bnbchain.org/faucet-smart)
- [MetaMask 配置指南](https://academy.binance.com/en/articles/connecting-metamask-to-binance-smart-chain)

---

**需要帮助？** 查看日志或在项目 GitHub 提 issue。
