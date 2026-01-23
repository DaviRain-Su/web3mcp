# ROADMAP

## v0.1.0 - MCP Skeleton (Zig 0.15, mcp.zig)
- Status: ⏳ In Progress
- Scope:
  - 初始化 Zig 工程与构建系统
  - 接入 mcp.zig，跑通最小 Server（ping / list tools）
  - 定义统一 Chain/Protocol 抽象与工具注册入口

## v0.2.0 - Solana 基础
- Status: ⏳ Pending
- Scope:
  - Solana RPC 适配：余额查询、转账（devnet）
  - 工具：get_balance, transfer（SPL/Native）
  - 配置与密钥管理

## v0.3.0 - EVM 基础（Avalanche/BNB）
- Status: ⏳ Pending
- Scope:
  - 通用 EVM 适配（RPC, EIP-1559, secp256k1 签名）
  - Avalanche C-Chain / BNB Chain 配置
  - 工具复用：get_balance, transfer

## v0.4.0 - 协议集成（Swap + Lending）
- Status: ⏳ Pending
- Scope:
  - DEX Quote：Jupiter / Trader Joe / PancakeSwap（quote-only）
  - Lending：Marginfi / AAVE / Venus（deposit/withdraw/borrow/repay）
  - 跨链比较工具：compare_swap_rates, find_best_lending_rate

## v0.5.0 - 跨链与高级功能
- Status: ⏳ Pending
- Scope:
  - 桥路由：Wormhole / LayerZero（接口规划）
  - 套利发现、收益优化、风险监控
  - Portfolio 聚合与 PnL 跟踪
