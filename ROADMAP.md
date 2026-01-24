# ROADMAP

## v0.1.0 - MCP Skeleton (Zig 0.15, mcp.zig)
- Status: ✅ Completed (2026-01-23)
- Scope:
  - 初始化 Zig 工程与构建系统
  - 接入 mcp.zig，跑通最小 Server（ping / list tools）
  - 定义统一 Chain/Protocol 抽象与工具注册入口

## v0.2.0 - Solana 基础
- Status: ✅ Completed (2026-01-23)
- Scope:
  - Solana RPC 适配：余额查询、转账（devnet/testnet/mainnet/localhost）
  - 工具：get_balance, transfer（Native SOL）
  - 配置与密钥管理（SOLANA_KEYPAIR 环境变量 + 配置文件）

## v0.3.0 - EVM 基础（Ethereum/Avalanche/BNB）
- Status: 🔨 In Progress
- Scope:
  - 集成 zabi 库（EVM RPC, ABI, 签名）
  - 支持多链：Ethereum, Avalanche C-Chain, BNB Chain
  - 工具：get_evm_balance, evm_transfer（原生代币）
  - EIP-1559 + Legacy 交易支持

## v0.3.1 - 基础能力增强（Solana + EVM）
- Status: ✅ Completed (2026-01-23)
- Scope:
  - Solana 基础补全：账户信息、交易状态、SPL Token 基础
  - EVM 基础补全：交易/区块查询、nonce/fee/estimate、ERC20 余额
  - 只读 RPC 能力优先（eth_call/账户信息）

## v0.3.2 - Core Adapter Refactor
- Status: ✅ Completed (2026-01-23)
- Scope:
  - core/chain 统一入口 + adapters
  - core/wallet 抽象签名/密钥加载
  - tools 全部调用 core

## v0.3.3 - Unified Chain Tools
- Status: ✅ Completed (2026-01-23)
- Scope:
  - get_balance / transfer 统一接口
  - 移除链特定工具
  - 文档同步

## v0.3.4 - Solana Utility Tools
- Status: ✅ Completed (2026-01-23)
- Scope:
  - Solana 钱包地址读取工具
  - 关闭空 Token 账户工具
  - 文档与注册同步

## v0.3.5 - Solana Readonly Extras
- Status: ✅ Completed (2026-01-23)
- Scope:
  - get_latest_blockhash / rent / fee / program accounts / vote accounts
  - 适配器与文档同步

## v0.3.6 - EVM Readonly Extras
- Status: ✅ Completed (2026-01-23)
- Scope:
  - get_chain_id / get_fee_history / get_logs
  - 适配器与文档同步

## v0.3.7 - Tools Directory Refactor
- Status: ✅ Completed (2026-01-23)
- Scope:
  - tools 目录按链拆分
  - 注册与文档同步
  - 回归测试

## v0.4.0 - Jupiter API 完整集成
- Status: ✅ Completed (2026-01-24)
- Scope:
  - Jupiter Swap API: quote, swap, program labels
  - Jupiter Price API: token prices
  - Jupiter Ultra API: unified order flow
  - Jupiter Trigger API: limit/DCA orders
  - Jupiter Recurring API: recurring swaps
  - Jupiter Lend API: lending operations
  - Jupiter Send API: gasless transfers
  - Jupiter Studio API: DBC pool management
  - Jupiter Tokens API: token metadata
  - Jupiter Portfolio API: portfolio tracking
  - Total: 46 Jupiter tools

## v0.4.1 - dFlow Complete API 集成
- Status: ✅ Completed (2026-01-24)
- Scope:
  - dFlow Swap API:
    - Imperative Swap: quote, swap, swap-instructions
    - Declarative Swap: intent, submit-intent
    - Order API: order, order-status
    - Token API: tokens, tokens-with-decimals
    - Venue API: venues
    - Prediction Swap: prediction-market-init
  - dFlow Prediction Market Metadata API:
    - Events: events, event by ticker
    - Markets: markets, market by ticker/mint, outcome-mints
    - Orderbook: by ticker, by mint
    - Trades: paginated trades
    - Series: series templates
    - Search & Live Data
  - Total: 23 dFlow tools (11 Swap + 12 Prediction Market)

## v0.4.2 - Meteora Protocol 完整集成
- Status: ✅ Completed (2026-01-24)
- Scope:
  - DLMM (Dynamic Liquidity Market Maker): 10 tools
    - Pool info, active bin, bins range, positions
    - Swap quote, swap execution
    - Add/remove liquidity, claim fees/rewards
  - DAMM v2 (CP-AMM): 8 tools
    - Pool info, position info
    - Swap quote, swap execution
    - Add/remove liquidity, claim fees
    - Create pool
  - DAMM v1 (Legacy): 5 tools
    - Pool info, swap quote, swap
    - Deposit, withdraw
  - Dynamic Bonding Curve: 7 tools
    - Pool info, quote, buy, sell
    - Create pool, check graduation, migrate
  - Dynamic Vault: 4 tools
    - Vault info, deposit, withdraw, user balance
  - Alpha Vault: 4 tools
    - Vault info, deposit, withdraw, claim
  - Stake-for-Fee (M3M3): 5 tools
    - Pool info, stake, unstake
    - Claim fees, user balance
  - Total: 43 Meteora tools

## v0.4.3 - Lending 协议集成
- Status: ⏳ Pending
- Scope:
  - Lending：Marginfi / AAVE / Venus（deposit/withdraw/borrow/repay）
  - 跨链比较工具：compare_swap_rates, find_best_lending_rate

## v0.5.0 - 跨链与高级功能
- Status: ⏳ Pending
- Scope:
  - 桥路由：Wormhole / LayerZero（接口规划）
  - 套利发现、收益优化、风险监控
  - Portfolio 聚合与 PnL 跟踪

## v0.6.0 - 全链扩展（ALL WEB3 CHAINS）
- Status: ⏳ Pending
- Scope:
  - ChainAdapter 扩展：EVM 全家桶（ETH/L2/Alt-EVM）、Cosmos/IBC、Polkadot parachain、BTC L2、Move 生态等
  - 通用地址/签名/交易建模，支持多签/模块化 Rollup 特性
  - 资源/工具接口保持 MCP 统一，新增链仅需适配器与协议插件

## v0.7.0 - Web3 全面能力（超越 DeFi）
- Status: ⏳ Pending
- Scope:
  - NFT：Mint/Transfer/Marketplace 适配器
  - 数据/Index：Subgraph/Goldsky/Hypersync/Helius 查询工具
  - 存储：IPFS/Arweave/Filecoin 上传/检索/付费
  - 身份/DID/Name：ENS/SpaceID/Unstoppable 接口
  - 消息/通知：XMTP/Push
  - 支付/法币出入金：On/Off-ramp 聚合接口
  - 治理：投票、委托操作
  - 风控/监控：地址画像、风险评分
