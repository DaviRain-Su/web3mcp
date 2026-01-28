# BSC 合约测试指南

## 概述

omniweb3-mcp 提供两种方式与 BSC 合约交互：

1. **静态 EVM 工具** - 通用 EVM 操作，适合任何链和合约
2. **动态合约工具** - 从 ABI 自动生成，提供类型安全的接口

## 工具类型对比

### 静态工具 (173 个)
- `evm_get_balance` - 查询余额
- `evm_call` - 调用合约只读方法
- `evm_send_transaction` - 发送交易
- `evm_get_chain_id` - 获取链 ID
- 等等...

**优点：**
- 支持任何链和网络（mainnet, testnet）
- 灵活，可以调用任何合约
- 适合临时测试和探索

**使用场景：**
- BSC Testnet 测试（contracts.json 中的合约是主网的）
- 调用未注册的合约
- 快速原型开发

### 动态合约工具 (884 个)
从 `abi_registry/contracts.json` 自动生成，例如：
- `bsc_wbnb_name` - WBNB.name()
- `bsc_wbnb_balanceOf` - WBNB.balanceOf(address)
- `bsc_pancakeswap_router_v2_swapExactTokensForTokens` - PancakeSwap 交易
- 等等...

**优点：**
- 类型安全 - 参数自动验证
- 文档完整 - 包含函数描述和参数说明
- 便于发现 - 工具名清晰描述功能

**限制：**
- 当前仅配置了主网合约（chain_id: 56）
- 返回交易数据而不是直接执行（需要钱包签名）

## 测试 BSC Testnet

### 方法 1: 使用静态 EVM 工具 (推荐用于测试网)

```bash
# BSC Testnet 合约地址
WBNB_TESTNET="0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
WALLET="0xC5208D5e7a946d4B9C4dC28747B4f685159e6A71"

# 1. 查询 WBNB name()
curl -s -X POST http://127.0.0.1:8765/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "evm_call",
      "arguments": {
        "chain": "bsc",
        "network": "testnet",
        "to_address": "'"$WBNB_TESTNET"'",
        "function_signature": "name()",
        "function_return_types": ["string"]
      }
    }
  }'

# 2. 查询余额 balanceOf(address)
curl -s -X POST http://127.0.0.1:8765/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "evm_call",
      "arguments": {
        "chain": "bsc",
        "network": "testnet",
        "to_address": "'"$WBNB_TESTNET"'",
        "function_signature": "balanceOf(address)",
        "function_args": ["'"$WALLET"'"],
        "function_return_types": ["uint256"]
      }
    }
  }'
```

### 方法 2: 添加测试网合约到 contracts.json

编辑 `abi_registry/contracts.json`，添加：

```json
{
  "chain": "bsc",
  "chain_id": 97,  // BSC Testnet
  "address": "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
  "name": "wbnb_testnet",
  "display_name": "Wrapped BNB (Testnet)",
  "category": "token",
  "enabled": true,
  "description": "WBNB on BSC Testnet"
}
```

然后重启服务器，会生成新的工具：
- `bsc_wbnb_testnet_name`
- `bsc_wbnb_testnet_balanceOf`
- 等等...

## BSC Testnet 合约地址

### 代币
- **WBNB**: `0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd`
- **BUSD**: `0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee`
- **USDT**: `0x337610d27c682E347C9cD60BD4b3b107C9d34dDd`

### DeFi 协议
- **PancakeSwap Router V2**: `0xD99D1c33F9fC3444f8101754aBC46c52416550D1`
- **PancakeSwap Factory V2**: `0x6725F303b657a9451d8BA641348b6761A6CC7a17`

## 完整测试示例

运行准备好的测试脚本：

```bash
# 1. 简单测试（使用静态工具）
./scripts/simple-bsc-test.sh

# 2. 完整测试（包括 gas 估算等）
./scripts/complete-bsc-test.sh
```

## 工具参数说明

### 静态工具 `evm_call`
- `chain`: 链名称 ("bsc", "ethereum", "polygon")
- `network`: 网络 ("mainnet", "testnet")
- `to_address`: 合约地址
- `function_signature`: 函数签名，如 "balanceOf(address)"
- `function_args`: 参数数组（可选）
- `function_return_types`: 返回类型数组

### 动态合约工具
- `signer`: 签名者地址（必需，即使是只读调用）
- `chain`: 链名称
- `network`: 网络
- + 函数特定参数（如 `account` for balanceOf）

## 下一步

1. **查询操作** - 使用 `evm_call` 测试只读方法
2. **写入操作** - 使用 `evm_send_transaction` 或动态工具 + wallet
3. **添加测试网合约** - 更新 `contracts.json` 获得更好的开发体验
4. **自动化测试** - 编写脚本验证合约行为

## 常见问题

**Q: 为什么动态工具返回交易数据而不是结果？**
A: 动态工具设计用于构建交易，需要配合钱包签名和广播。对于只读操作，建议使用 `evm_call`。

**Q: 如何在测试网测试写入操作？**
A: 使用 `evm_send_transaction` 并配置本地钱包（见 WALLET_CONFIG_GUIDE.md）。

**Q: 能否调用未在 contracts.json 中的合约？**
A: 可以！使用静态 `evm_call` 工具，提供合约地址和函数签名即可。

## 相关文档

- [BSC Testnet 指南](BSC_TESTNET_GUIDE.md)
- [钱包配置指南](WALLET_CONFIG_GUIDE.md)
- [快速开始](QUICK_START_BSC.md)
