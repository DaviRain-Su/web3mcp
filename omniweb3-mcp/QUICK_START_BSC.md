# 🚀 BSC Testnet 快速开始

## 一键启动和测试

### 步骤 1: 启动服务器

```bash
./scripts/start-bsc-testnet.sh
```

服务器会在 `http://127.0.0.1:8765` 启动。

### 步骤 2: 快速测试（新终端）

```bash
./scripts/quick-test-bsc.sh
```

你会看到：
```
🧪 Quick BSC Testnet Test

✅ Server is running

📡 Getting BSC Testnet Chain ID...
✅ Chain ID: 97 (BSC Testnet)

📦 Getting latest block number...
✅ Latest block: 45678901

⛽ Getting current gas price...
✅ Gas price: 3 Gwei

✨ All basic tests passed!
```

## 测试你的地址

获取测试 BNB：https://testnet.bnbchain.org/faucet-smart

查询余额：

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
  }' | jq '.content[0].text'
```

## 可用工具列表

查看所有 EVM 工具：

```bash
curl http://127.0.0.1:8765/mcp/v1/tools | \
  jq '.tools[] | select(.name | startswith("evm_")) | .name'
```

常用工具：
- `evm_get_balance` - 查询余额
- `evm_get_chain_id` - 获取链 ID
- `evm_get_block_number` - 获取区块高度
- `evm_get_gas_price` - 获取 gas 价格
- `evm_get_transaction_count` - 获取 nonce
- `evm_estimate_gas` - 估算 gas
- `evm_send_transfer` - 发送转账
- `evm_get_transaction` - 查询交易
- `evm_get_block_by_number` - 查询区块

## 完整文档

更多详情请查看：[BSC_TESTNET_GUIDE.md](./BSC_TESTNET_GUIDE.md)

## 支持的链

除了 BSC，还支持：
- ✅ Ethereum (mainnet, sepolia)
- ✅ Polygon (mainnet, mumbai)
- ✅ Avalanche (mainnet, fuji)
- ✅ Arbitrum (mainnet, sepolia)
- ✅ Optimism (mainnet, sepolia)
- ✅ Base (mainnet, sepolia)

使用方法相同，只需修改 `chain` 和 `network` 参数。

## 故障排除

### 服务器无法启动？

```bash
# 检查端口是否被占用
lsof -i :8765

# 或者使用其他端口
HOST=127.0.0.1 PORT=8766 ./scripts/start-bsc-testnet.sh
```

### 连接超时？

尝试其他 RPC 端点：

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_chain_id",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "endpoint_override": "https://bsc-testnet.public.blastapi.io"
    }
  }'
```

## 下一步

1. ✅ 测试基本查询功能
2. ✅ 获取测试 BNB
3. ✅ 测试发送交易
4. ✅ 集成到 Claude Desktop
5. ✅ 测试智能合约交互

---

**Happy Testing! 🎉**
