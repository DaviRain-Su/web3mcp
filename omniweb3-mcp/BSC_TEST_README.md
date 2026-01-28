# BSC Testnet 测试总结

## 🎉 成功完成

你的 omniweb3-mcp 服务器现在已经：

✅ **在 macOS 上成功运行** - 修复了所有 socket 兼容性问题
✅ **加载了 1057 个工具** - 173 个静态 + 884 个动态合约工具
✅ **支持 BSC Testnet** - 可以查询和交互
✅ **钱包已配置** - 地址: `0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71`
✅ **有测试 BNB** - 从水龙头获得

## 快速测试

### 方法 1: 使用脚本

```bash
# 启动服务器（如果未运行）
./scripts/start-bsc-testnet.sh

# 在另一个终端运行测试
./scripts/test-bsc-simple.sh
```

### 方法 2: 直接调用 MCP 工具

**重要**: 链名称使用 `"bnb"` 而不是 `"bsc"`

```bash
# 获取链 ID (应该返回 97)
curl -s -X POST http://127.0.0.1:8765/ \
  -H 'Content-Type: application/json' \
  -d '{
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

# 获取 BNB 余额
curl -s -X POST http://127.0.0.1:8765/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "get_balance",
      "arguments": {
        "chain": "bnb",
        "network": "testnet",
        "address": "0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"
      }
    }
  }' | jq '.result.content[0].text'
```

## 可用的工具

### 静态工具 (Unified - 跨链)
- `get_balance` - 查询余额
- `get_block_number` - 获取区块号
- `get_block` - 获取区块信息
- `get_transaction` - 获取交易信息
- `token_balance` - 查询代币余额
- `transfer` - 转账

### 静态工具 (EVM 专用)
- `get_chain_id` - 获取链 ID
- `get_gas_price` - 获取 Gas 价格
- `get_nonce` - 获取 nonce
- `estimate_gas` - 估算 Gas
- `call` - 合约调用 (需要编码的 data)
- `get_receipt` - 获取交易收据
- `get_fee_history` - 获取 fee 历史
- `get_logs` - 获取事件日志

### 动态合约工具 (884 个)

**BSC 主网合约** (从 contracts.json 加载):
- `bsc_wbnb_name`, `bsc_wbnb_symbol`, `bsc_wbnb_balanceOf`, ...
- `bsc_pancakeswap_router_v2_swapExactTokensForTokens`, ...
- `bsc_busd_*`, `bsc_usdt_*`, `bsc_cake_token_*`, ...
- `bsc_venus_comptroller_*`, ...

**Ethereum 合约**:
- `ethereum_uniswap_router_v2_*`, `ethereum_uniswap_factory_v2_*`
- `ethereum_aave_pool_v3_*`
- `ethereum_weth_*`, `ethereum_usdc_*`, `ethereum_usdt_*`
- 等等...

**Polygon 合约**:
- `polygon_quickswap_*`
- `polygon_wmatic_*`, `polygon_usdc_polygon_*`
- 等等...

## 测试 BSC Testnet

**注意**: 动态合约工具配置的是主网地址，测试网需要使用静态工具。

### 示例 1: 查询 WBNB Testnet 合约

```bash
WBNB_TESTNET="0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
WALLET="0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"

# 查询 WBNB 余额
curl -s -X POST http://127.0.0.1:8765/ \
  -H 'Content-Type: application/json' \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 1,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"token_balance\",
      \"arguments\": {
        \"chain\": \"bnb\",
        \"network\": \"testnet\",
        \"token_address\": \"$WBNB_TESTNET\",
        \"owner\": \"$WALLET\"
      }
    }
  }"
```

### 示例 2: 转账测试 BNB

```bash
# 转 0.01 tBNB 到 burn 地址 (测试用)
curl -s -X POST http://127.0.0.1:8765/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "transfer",
      "arguments": {
        "chain": "bnb",
        "network": "testnet",
        "to_address": "0x0000000000000000000000000000000000000001",
        "amount": "10000000000000000",
        "wallet_type": "local",
        "tx_type": "eip1559",
        "confirmations": 1
      }
    }
  }'
```

## 链名称映射

| 实际链 | MCP 工具中使用的名称 | 说明 |
|--------|---------------------|------|
| BSC (BNB Chain) | `"bnb"` | Binance Smart Chain |
| Ethereum | `"ethereum"` | 以太坊主网/测试网 |
| Polygon | `"polygon"` | Polygon PoS |
| Avalanche | `"avalanche"` | Avalanche C-Chain |

## 下一步

1. **查看完整指南**:
   - [BSC Testnet 指南](BSC_TESTNET_GUIDE.md)
   - [合约测试指南](BSC_CONTRACT_TEST_GUIDE.md)
   - [钱包配置指南](WALLET_CONFIG_GUIDE.md)

2. **添加测试网合约** (可选):
   编辑 `abi_registry/contracts.json` 添加 BSC testnet 合约，重启服务器后会自动生成工具。

3. **探索 Solana 工具** (可选):
   服务器也加载了 Jupiter、Meteora 等 Solana DeFi 协议的 IDL 工具。

## 故障排除

**问题**: 工具返回 "Tool not found"
**解决**: 检查工具名称是否正确，使用 MCP JSON-RPC 格式

**问题**: 返回 "Unsupported chain: bsc"
**解决**: 使用 `"bnb"` 而不是 `"bsc"` 作为链名称

**问题**: 动态工具需要 signer 参数
**解决**: 动态工具主要用于构建交易，即使只读也需要 signer。对于简单查询，建议使用静态工具。

**问题**: 服务器无响应
**解决**: 检查服务器日志，可能在加载大量动态工具。等待加载完成（约 30 秒）。

## 相关命令

```bash
# 启动服务器
./scripts/start-bsc-testnet.sh

# 检查服务器状态
curl http://127.0.0.1:8765/health

# 停止服务器
pkill -f omniweb3-mcp

# 查看日志
# 日志在前台运行时直接显示

# 重新构建
zig build
```

## 成就解锁 🎉

✅ macOS 完全兼容
✅ 1057 个工具可用
✅ BSC Testnet 连接成功
✅ 钱包配置完成
✅ 测试币已到账

你的 MCP 服务器已经准备好进行 Web3 开发了！
