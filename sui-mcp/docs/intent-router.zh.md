# 意图路由器设计

本文档描述面向多链 MCP 的意图路由器设计。意图路由器位于链特定工具之上，将自然语言转化为可执行的工具调用计划。

## 目标

提供一个与链无关的意图层，用于解析用户意图、生成执行计划，并在 Sui、EVM、Solana 等链上路由工具调用，避免为每条链硬编码逻辑。

## 分层结构

1) **意图核心（链无关）**
- `intent_parse`: 将自然语言转为结构化意图。
- `intent_plan`: 生成带缺失字段的执行计划。
- `intent_execute`: 执行校验后的计划并返回结果。

2) **链适配器（链相关）**
- **SuiAdapter**：映射到 Sui 工具（`build_transfer_sui`、`execute_transaction_with_keystore`、`auto_fill_move_call`）。
- **EvmAdapter**：映射到 EVM 工具（`eth_sendTransaction`、ERC20 transfer、gas estimate）。
- **SolanaAdapter**：映射到 Solana 工具（system transfer、SPL transfer）。

3) **执行层**
- 按顺序执行工具调用，支持 dry-run、模拟与确认步骤。
- 追踪中间结果，逐步补全缺失字段。

## 意图 Schema（草案）

核心原则：**普通用户会说“链名”**（比如“Base 测试网 / 以太坊 / Arbitrum…”），但执行层必须稳定、可机器化。
因此我们把用户输入规范化为：

- `family`: `sui | evm | solana`
- `chain_id`: 当 `family=evm` 时使用 EVM chain id
- `network_name`: 规范化后的可读名称

```json
{
  "action": "transfer | swap | stake | unstake | pay | query",
  "network": {
    "family": "sui | evm | solana | auto",
    "network_name": "sui | base-sepolia | ethereum | arbitrum-sepolia | ...",
    "chain_id": 84532
  },
  "asset": "SUI | USDC | ETH | ...",
  "amount": "1.5",
  "from": "0x...",
  "to": "0x...",
  "constraints": {
    "max_slippage": "0.5%",
    "gas_budget": 1000000
  }
}
```

### 人类友好的 EVM 网络映射（默认偏 testnet）

为了降低误操作主网的风险，**默认更偏向 testnet**。

- Base
  - `base-sepolia` / “Base 测试网” → `chain_id=84532`
  - `base` / “Base 主网” → `chain_id=8453`
- Ethereum
  - `sepolia` / “以太坊测试网” → `chain_id=11155111`
  - `ethereum` / “以太坊主网” → `chain_id=1`
- Arbitrum
  - `arbitrum-sepolia` / “Arbitrum 测试网” → `chain_id=421614`
  - `arbitrum` / “Arbitrum One 主网” → `chain_id=42161`
- BSC
  - `bsc-testnet` / “BSC 测试网” → `chain_id=97`
  - `bsc` / “BSC 主网” → `chain_id=56`

RPC 通过 chain id 配置：`EVM_RPC_URL_<chainId>`（例如 `EVM_RPC_URL_84532=https://sepolia.base.org`）。


## 计划 Schema（草案）

```json
{
  "intent": { "..." },
  "missing": ["to", "amount"],
  "plan": [
    {
      "chain": "sui",
      "tool": "build_transfer_sui",
      "params": { "sender": "0x...", "recipient": "0x..." }
    },
    {
      "chain": "sui",
      "tool": "execute_transaction_with_keystore",
      "params": { "tx_bytes": "<tx_bytes>", "signer": "0x..." }
    }
  ]
}
```

## 安全与校验

- 默认校验签名地址与交易 sender 一致，除非显式允许。
- 大额转账需要显式确认。
- 支持模拟或 dry-run，再执行。

## 实现建议

1) 将 `nl_intent` 拆分为 `intent_parse` 和 `intent_plan`。
2) 定义跨链通用意图 schema。
3) 优先接入 Sui 适配器（已有工具）。
4) 预留 EVM/Solana 适配器，后续补齐。
5) 增加 `intent_execute` 统一执行计划并汇总结果。

## 备注

- 这是**应用层意图路由**，不是链级意图协议。
- 与 AI agent 工作流一致：意图 → 计划 → 执行。
