# 🔍 链上程序 API 服务分析

**日期**: 2026-01-26
**目的**: 识别 12 个链上程序在 IDL 生成工具之外提供的 REST API 和其他 API 服务

---

## 📊 执行摘要

在我们已有 IDL 生成工具的 **12 个链上程序**中，**9 个程序 (75%)** 提供额外的 REST API 或 API 服务：

| 类别 | 数量 | 程序 | 状态 |
|----------|-------|----------|------|
| **有 API** | 9 | Jupiter, Drift, Meteora DLMM, Raydium CLMM, Orca, Marinade, Metaplex, PumpFun (第三方), Squads | |
| **已实现** | 1 | ✅ Jupiter (53 工具) | ✅ 完成 |
| **待实现** | 8 | 其他 8 个程序 | ⏳ 待开发 |
| **仅 IDL** | 3 | Meteora DAMM v1, Meteora DAMM v2, Meteora DBC | N/A |

**需实现的 API 端点总数**:
- ✅ **已实现**: ~53 Jupiter 工具
- ⏳ **待实现**: ~40 其他程序工具
- 📊 **总计**: ~93 静态工具

---

## 🎯 有 API 服务的程序

### 1. Jupiter v6 ✅ **已完整实现** (最高优先级)

**状态**: ✅ **已完全实现** - 47 个静态工具 + 6 个动态工具 = **53 个工具**
**优先级**: ~~关键~~ → **已完成** ✅
**API 覆盖率**: 98% (47/48 端点)

#### 🎉 实施状态：完整

项目已经有完整的 Jupiter API 实现，覆盖几乎所有端点：

**A. Swap API V6** (4 个工具)
- **Base URL**: `https://api.jup.ag` ✅ (正确使用新 API，无需担心 lite-api 弃用)
- ✅ `GET /quote` - get_quote.zig
- ✅ `POST /swap` - swap.zig
- ✅ `GET /program-id-to-label` - get_program_labels.zig
- ✅ execute_swap.zig (辅助工具)
- ⚪ `POST /swap-instructions` (缺失，但低频使用)

**B. Price API V3** (1 个工具)
- ✅ `GET /price` - get_price.zig

**C. Token API V2** (7 个工具)
- ✅ search_tokens.zig
- ✅ get_tokens_by_tag.zig
- ✅ get_tokens_by_category.zig
- ✅ get_recent_tokens.zig
- ✅ get_tokens_content.zig
- ✅ get_tokens_cooking.zig
- ✅ get_tokens_feed.zig

**D. Trigger/Limit Order API** (5 个工具)
- ✅ create_trigger_order.zig
- ✅ execute_trigger.zig
- ✅ cancel_trigger_order.zig
- ✅ cancel_trigger_orders.zig
- ✅ get_trigger_orders.zig

**E. Recurring API (DCA)** (4 个工具)
- ✅ create_recurring_order.zig
- ✅ execute_recurring.zig
- ✅ cancel_recurring_order.zig
- ✅ get_recurring_orders.zig

**F. Lend API (Earn)** (7 个工具)
- ✅ lend_mint.zig, lend_redeem.zig
- ✅ lend_deposit.zig, lend_withdraw.zig
- ✅ get_lend_positions.zig
- ✅ get_lend_earnings.zig
- ✅ get_lend_tokens.zig

**G. Ultra API** (7 个工具)
- ✅ ultra_order.zig, ultra_execute.zig
- ✅ get_balances.zig, get_holdings.zig
- ✅ get_shield.zig, ultra_search.zig
- ✅ get_routers.zig

**H. Portfolio API** (3 个工具)
- ✅ get_positions.zig
- ✅ get_platforms.zig
- ✅ get_staked_jup.zig

**I. Send API** (4 个工具)
- ✅ craft_send.zig, craft_clawback.zig
- ✅ get_pending_invites.zig
- ✅ get_invite_history.zig

**J. Studio API (DBC)** (5 个工具)
- ✅ get_dbc_fee.zig, claim_dbc_fee.zig
- ✅ get_dbc_pools.zig
- ✅ create_dbc_pool.zig
- ✅ submit_dbc_pool.zig

**K. 动态工具（从 IDL）** (6 个)
- ✅ jupiter_route
- ✅ jupiter_sharedAccountsRoute
- ✅ jupiter_exactOutRoute
- ✅ jupiter_setTokenLedger
- ✅ jupiter_createOpenOrders
- ✅ jupiter_sharedAccountsRouteWithTokenLedger

**重要提示**:
- ✅ 已使用正确的新 API (`api.jup.ag`)，无需迁移
- ✅ lite-api.jup.ag 弃用不影响项目
- ✅ 覆盖率达 98%，只缺 1 个低频端点

**实际工具数**: **53 个**（远超预估的 15-20 个）

**工具位置**: `src/tools/solana/defi/jupiter/`

**详细分析**: 参见 `/tmp/jupiter_api_coverage.md`

**参考资料**:
- [Swap API](https://dev.jup.ag/api-reference/swap/quote)
- [V6 Swap API](https://hub.jup.ag/docs/apis/swap-api)
- [Price API](https://dev.jup.ag/docs/price)
- [Token API](https://dev.jup.ag/docs/token-api/)
- [Trigger API](https://dev.jup.ag/docs/trigger-api/create-order)

---

### 2. Raydium CLMM ⭐⭐⭐ (高优先级)

**状态**: 有完整的 REST API v3
**优先级**: 高 - 主要 DEX，API 功能全面

#### API 详情:

- **Base URL**: `https://api-v3.raydium.io`
- **文档**: [Swagger UI](https://api-v3.raydium.io/docs/)
- **端点类别**:
  - **Main**: 平台信息和工具
  - **Mint**: 代币列表和价格
  - **Pools**: 流动性和仓位数据
  - **Farms**: APY 和 TVL 数据
  - **IDO**: 初始 DEX 发行池密钥
  - **Compute**:
    - `/compute/swap-base-in` - 精确输入交换
    - `/compute/swap-base-out` - 精确输出交换

**重要提示**:
- API 设计用于监控和快速数据访问
- 不适合实时跟踪或开发依赖
- TypeScript SDK: [raydium-sdk-V2](https://github.com/raydium-io/raydium-sdk-V2)

**预估工具数**: ~10-15 个静态工具

**参考资料**:
- [Swagger 文档](https://api-v3.raydium.io/docs/)
- [Trade API](https://docs.raydium.io/raydium/for-developers/trade-api)

---

### 3. Meteora DLMM ⭐⭐ (中等优先级)

**状态**: 有专用 DLMM API
**优先级**: 中等 - 流行的 DLMM，API 全面

#### API 详情:

- **Base URL**: `https://dlmm-api.meteora.ag`
- **文档**: [Meteora DLMM API](https://docs.meteora.ag/api-reference/dlmm/overview)
- **速率限制**: 每秒 30 请求

#### 端点 (共 20 个):

**协议指标**:
- `GET /info/protocol_metrics` - 协议级指标

**交易对管理** (11 个端点):
- `GET /pair/all` - 所有交易对
- `GET /pair/all_by_groups` - 按组分类的交易对
- `GET /pair/all_by_groups_metadata` - 按元数据分类
- `GET /pair/all_with_pagination` - 分页交易对
- `GET /pair/group_pair/{lexical_order_mints}` - 特定组交易对
- `GET /pair/{pair_address}` - 单个交易对数据
- `GET /pair/{pair_address}/analytic/pair_fee_bps` - 手续费分析
- `GET /pair/{pair_address}/analytic/pair_trade_volume` - 交易量分析
- `GET /pair/{pair_address}/analytic/pair_tvl` - TVL 分析
- `GET /pair/{pair_address}/analytic/swap_history` - 交换历史
- `GET /pair/{pair_address}/analytic/positions_lock` - 仓位锁定

**仓位管理** (7 个端点):
- `GET /position/{position_address}` - 仓位详情
- `GET /position/{position_address}/claim_fees` - 可领取手续费
- `GET /position/{position_address}/claim_rewards` - 可领取奖励
- `GET /position/{position_address}/deposits` - 存款历史
- `GET /position/{position_address}/withdraws` - 取款历史
- `GET /position_v2/{position_address}` - 仓位 v2 数据
- `GET /wallet/{wallet_address}/{pair_address}/earning` - 钱包收益

**预估工具数**: ~20 个静态工具

**参考资料**:
- [DLMM API 概览](https://docs.meteora.ag/api-reference/dlmm/overview)
- [DLMM SDK](https://docs.meteora.ag/integration/dlmm-integration/dlmm-sdk)

---

### 4. Drift Protocol ⭐⭐ (中等优先级)

**状态**: 有数据 API 和网关
**优先级**: 中等 - 永续合约平台，API 实用

#### API 详情:

- **文档**: [protocol-v2 API](https://drift-labs.github.io/v2-teacher/)
- **网关**: [自托管 API 网关](https://github.com/drift-labs/gateway)
- **SDK**: TypeScript 和 Python 可用

#### 功能:

- **数据 API**: 市场、合约、代币经济数据
- **速率限制**: 已实现（具体限制未指定）
- **DLOB (去中心化限价订单簿)**: 拍卖参数端点用于市场订单参数
- **Swift 订单**: Builder 代码目前仅限于 Swift 订单

**注意**: 公开文档中没有具体端点列表，但有完整的 SDK 文档

**预估工具数**: ~10-15 个静态工具

**参考资料**:
- [SDK 文档](https://docs.drift.trade/sdk-documentation)
- [Gateway](https://github.com/drift-labs/gateway)

---

### 5. Orca Whirlpool ⭐⭐ (中等优先级)

**状态**: 有公共 API
**优先级**: 中等 - 主要 CLMM DEX

#### API 详情:

- **官方 API**: `https://api.orca.so/docs`
- **文档**: [Orca's Public API](https://dev.orca.so/API/)
- **SDK**: TypeScript SDK (使用 Solana Web3.js SDK v2，与 v1.x.x 不兼容)

#### 第三方集成 (Hummingbot):

通过 Hummingbot Gateway 可用的端点:
- `/connectors/orca/clmm/quote-swap` - 报价交换
- `/connectors/orca/clmm/execute-swap` - 执行交换
- `/connectors/orca/clmm/pool-info` - 池信息
- `/connectors/orca/clmm/position-info` - 仓位信息
- `/connectors/orca/clmm/positions-owned` - 拥有的仓位
- `/connectors/orca/clmm/quote-position` - 仓位报价
- `/connectors/orca/clmm/open-position` - 开启仓位
- `/connectors/orca/clmm/close-position` - 关闭仓位
- `/connectors/orca/clmm/add-liquidity` - 添加流动性
- `/connectors/orca/clmm/remove-liquidity` - 移除流动性
- `/connectors/orca/clmm/collect-fees` - 收集手续费

**注意**: 应查看 api.orca.so/docs 的官方 API 文档以获取完整端点列表

**预估工具数**: ~10-12 个静态工具

**参考资料**:
- [官方 API](https://dev.orca.so/API/)
- [Hummingbot 集成](https://hummingbot.org/exchanges/gateway/orca/)

---

### 6. Marinade Finance ⭐ (中低优先级)

**状态**: 有 Swagger API
**优先级**: 中低 - 流动性质押 API

#### API 详情:

- **API 文档**: `https://api.marinade.finance/docs` (Swagger UI)
- **原生质押 API**: `https://native-staking.marinade.finance/docs`
- **SDK**: [TypeScript SDK](https://github.com/marinade-finance/marinade-ts-sdk)

**注意**: 具体端点未公开列出，需直接访问 Swagger 文档

**预估工具数**: ~5-10 个静态工具

**参考资料**:
- [API 文档](https://api.marinade.finance/docs)
- [原生 API & SDK](https://docs.marinade.finance/marinade-protocol/protocol-overview/marinade-native/marinade-native-api-and-sdk)

---

### 7. Metaplex ⭐⭐ (中等优先级)

**状态**: 有 DAS (数字资产标准) API
**优先级**: 中等 - NFT 操作必需

#### API 详情:

- **文档**: [DAS API](https://developers.metaplex.com/das-api)
- **仓库**: [GitHub](https://github.com/metaplex-foundation/digital-asset-standard-api)
- **包**: `@metaplex-foundation/digital-asset-standard-api`

#### 核心方法 (5 个):

- `getAsset` - 单个资产元数据
- `getAssets` - 多个资产元数据
- `getAssetProof` - 压缩资产的 Merkle 树证明
- `getAssetProofs` - 多个证明
- `getAssetSignatures` - 资产签名

#### 筛选方法 (4 个):

- `getAssetsByAuthority` - 按权限查询资产
- `getAssetsByCreator` - 按创建者查询资产
- `getAssetsByGroup` - 按组查询资产
- `getAssetsByOwner` - 按所有者查询资产

#### 专用方法 (2 个):

- `getNFTEditions` - NFT 版本
- `getTokenAccounts` - 代币账户
- `searchAssets` - 搜索功能

#### MPL Core 扩展方法 (6 个):

- `getCoreAsset` - Core 资产
- `getCoreCollection` - Core 集合
- `getCoreAssetsByAuthority` - 按权限查询 Core 资产
- `getCoreAssetsByCollection` - 按集合查询 Core 资产
- `getCoreAssetsByOwner` - 按所有者查询 Core 资产
- `searchCoreAssets` - 搜索 Core 资产
- `searchCoreCollections` - 搜索 Core 集合

**总方法数**: ~20

**注意**:
- Core、Token Metadata 和压缩 (Bubblegum) 资产的统一接口
- 通过 RPC 提供商可用: Helius, Hello Moon, QuickNode, Shyft, Triton
- 可能需要在 RPC 提供商处启用 DAS API

**预估工具数**: ~20 个静态工具

**参考资料**:
- [DAS API 概览](https://developers.metaplex.com/das-api)
- [QuickNode DAS API](https://www.quicknode.com/docs/solana/solana-das-api)

---

### 8. Squads V4 ⭐ (中低优先级)

**状态**: 有 REST API v0 和 v1
**优先级**: 中低 - 多签管理 API

#### API 详情:

- **Base URL**: `https://developer-api.squads.so/api/v1`
- **文档**:
  - [API v0](https://developers.squads.so/squads-api/api-reference/v0/introduction)
  - [API v1](https://developers.squads.so/squads-api/api-reference/v1/quickstart)
- **SDK**: [开发 SDK](https://docs.squads.so/main/v/development/development/overview)

#### 端点类别:

- **智能账户端点**: 账户创建和管理
- **消费限制端点**: 配置消费限制
- **GET 端点**: 监控和状态查询
- **策略管理**: 时间锁、角色、子账户
- **交易处理**: SOL 和 USDC 手续费支付

**预估工具数**: ~10-15 个静态工具

**参考资料**:
- [API 概览](https://developers.squads.so/squads-api/introduction)
- [快速开始](https://docs.squads.so/main/development/introduction/quickstart)

---

### 9. PumpFun ⭐ (低优先级)

**状态**: 有第三方 API (无官方公共 API)
**优先级**: 低 - 仅社区/第三方 API

#### 可用 API:

**A. PumpPortal (第三方)**
- 交易 API (需门禁，每笔交易 0.5% 手续费)
- 数据 API (免费，有速率限制)
- **网站**: [pumpportal.fun](https://pumpportal.fun/)

**B. Moralis API**
- `getNewTokensByExchange` - 新代币
- `getTokenBondingStatus` - 绑定进度
- `getBondingTokensByExchange` - 绑定代币列表
- `getGraduatedTokensByExchange` - 毕业代币

**C. QuickNode Metis**
- `/pump-fun/quote` - 获取报价
- `/pump-fun/swap` - 执行交换

**D. Bitquery**
- 代币价格、OHLCV、ATH、市值、流动性数据
- 超低延迟

**注意**:
- 无官方 Pump.fun 公共 API
- 大多数 API 需要 JWT 认证
- 所有 API 由各自提供商拥有/运营

**预估工具数**: ~5-10 个静态工具 (如果选择支持第三方 API)

**参考资料**:
- [PumpPortal](https://pumpportal.fun/)
- [Moralis Pump.fun API](https://docs.moralis.com/web3-data-api/solana/tutorials/pump-fun-api-faq)
- [Bitquery](https://docs.bitquery.io/docs/blockchain/Solana/Pumpfun/Pump-Fun-API/)

---

## ❌ 没有额外 API 的程序 (仅 IDL)

### 10. Meteora DAMM v1

**状态**: 无 REST API
**工具**: 仅 26 个 IDL 生成工具

### 11. Meteora DAMM v2

**状态**: 无 REST API
**工具**: 仅 35 个 IDL 生成工具

### 12. Meteora DBC (动态联合曲线)

**状态**: 无 REST API
**工具**: 仅 28 个 IDL 生成工具

**注意**: 这三个 Meteora 程序完全依赖链上程序 IDL。未找到额外的 REST API 服务。

---

## 📈 实施优先级矩阵

| 优先级 | 程序 | 预估工具数 | 理由 | 状态 |
|----------|----------|-----------------|-----------|------|
| ~~**关键**~~ | ~~Jupiter~~ | ~~15-20~~ | ~~Solana 使用最广泛的聚合器~~ | ✅ **已完成** (53 工具) |
| **关键** | **Raydium CLMM** | 10-15 | 主要 DEX，API 全面 | ⏳ 待实现 |
| **高** | **Meteora DLMM** | ~20 | 流动性协议，20 REST 端点 | ⏳ 待实现 |
| **中等** | Drift, Orca, Metaplex | 35-45 | 重要 DeFi 协议，API 实用 | ⏳ 待实现 |
| **中低** | Marinade, Squads | 15-25 | 有用但访问频率较低 | ⏳ 待实现 |
| **低** | PumpFun | 5-10 | 仅第三方 API，可选 | ⏳ 待实现 |

---

## 🎯 推荐实施顺序 (更新)

### ✅ 阶段 0: 已完成
- **Jupiter** - 53 个工具（47 静态 + 6 动态）✅

### 阶段 1: 关键 (第 1 周)
1. **Raydium API** - Compute 端点、Pools、Mint 数据 (~10 个工具)
   - **小计**: ~10 个工具

### 阶段 2: 高优先级 (第 2 周)
2. **Meteora DLMM API** - Pairs、Positions、Analytics (~20 个工具)
   - **小计**: ~20 个工具

### 阶段 3: 中等优先级 (第 3 周)
3. **Metaplex DAS API** - 资产查询、搜索 (~15 个工具)
4. **Drift API** - 市场数据、DLOB (~10 个工具)
5. **Orca API** - 池/仓位管理 (~10 个工具)
   - **小计**: ~35 个工具

### 阶段 4: 较低优先级 (第 4 周)
6. **Marinade API** - 质押操作 (~8 个工具)
7. **Squads API** - 多签管理 (~12 个工具)
8. **PumpFun APIs** - 可选第三方支持 (~5 个工具)
   - **小计**: ~25 个工具

**待实现静态工具**: ~90 个工具（修正）
**已有工具**:
- 静态: 165 + 47 Jupiter = 212
- 动态: 637
- 小计: 849 工具
**实施后总数**: ~939 工具 (+10.6% 增长)

---

## 💡 实施注意事项

### 技术考虑:

1. **认证**:
   - 大多数 API 是公开/免费的 (Jupiter Lite, Raydium, Meteora)
   - 部分需要 API key (Jupiter Pro, PumpFun Trading API)
   - 考虑同时支持免费和付费层级

2. **速率限制**:
   - 实施客户端速率限制
   - 在适当的地方缓存响应
   - 考虑高流量场景的 API key 轮换

3. **错误处理**:
   - API 不可用时优雅降级
   - 清晰的速率限制错误消息
   - 尽可能回退到链上查询

4. **文档**:
   - 每个静态工具需要 InputSchema
   - 清晰的参数描述
   - 工具描述中的使用示例

### 架构建议:

```
src/tools/
├── static/
│   ├── jupiter/
│   │   ├── swap_api.zig        (Quote, Swap, Instructions)
│   │   ├── price_api.zig       (价格查询)
│   │   ├── trigger_api.zig     (限价订单)
│   │   └── token_api.zig       (代币列表)
│   ├── raydium/
│   │   ├── compute_api.zig     (交换计算)
│   │   ├── pools_api.zig       (池数据)
│   │   └── mint_api.zig        (代币数据)
│   ├── meteora/
│   │   └── dlmm_api.zig        (所有 DLMM 端点)
│   ├── metaplex/
│   │   └── das_api.zig         (数字资产查询)
│   ├── drift/
│   │   └── data_api.zig        (市场数据)
│   ├── orca/
│   │   └── whirlpool_api.zig   (池/仓位 API)
│   ├── marinade/
│   │   └── staking_api.zig     (质押 API)
│   ├── squads/
│   │   └── multisig_api.zig    (多签 API)
│   └── pumpfun/
│       └── third_party_api.zig (可选第三方)
└── dynamic/
    └── registry.zig             (现有 IDL 工具)
```

---

## 📊 最终统计 (更新)

### 当前状态:
- **程序**: 12 个 (都有 IDL)
- **工具**: ~849
  - 静态: 212 (165 通用 + 47 Jupiter)
  - 动态: 637

### 添加剩余 API 服务后:
- **程序**: 12 个链上 + 9 个 API 服务
- **静态工具**: 212 当前 + ~90 待实现 = ~302 静态工具
- **动态工具**: 637 (不变)
- **工具总数**: ~939 (+10.6% 增长)

### 覆盖范围:
- **有 API 的程序**: 9/12 (75%)
  - ✅ 已实现: 1/9 (Jupiter - 53 工具)
  - ⏳ 待实现: 8/9 (Raydium, Meteora, Metaplex, Drift, Orca, Marinade, Squads, PumpFun)
- **仅 IDL 的程序**: 3/12 (25%)
- **API 类别**: 交换、价格、NFT、质押、多签、DEX、永续合约

---

## ✅ 后续行动 (更新)

1. **审查和批准**: 用户审查此分析并批准实施计划
2. **阶段 1 实施**: ~~从 Jupiter API 开始~~ → 从 Raydium API 开始（关键优先级）
3. **测试**: 彻底测试每个 API 端点
4. **文档**: 更新面向用户的文档
5. **部署**: 分阶段推出到生产环境

**重要更新**: Jupiter API 已完全实现 (53 工具)，无需额外开发

---

**准备人**: Claude Code
**日期**: 2026-01-26 (更新)
**状态**: Jupiter 完成 ✅，其余待审查
**预计实施时间**: 3-4 周（分阶段方法，不含 Jupiter）
