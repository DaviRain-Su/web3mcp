# Meteora 工具使用指南

**版本**: 1.0
**最后更新**: 2026-01-26
**工具总数**: 209 个（46 静态 + 163 动态）

---

## 📚 目录

1. [概览](#概览)
2. [协议类型对比](#协议类型对比)
3. [REST API vs 链上工具](#rest-api-vs-链上工具)
4. [工具分类](#工具分类)
5. [使用示例](#使用示例)
6. [最佳实践](#最佳实践)
7. [常见问题](#常见问题)

---

## 概览

Meteora 是 Solana 上的多协议 DeFi 平台，提供：

- **DLMM**: 动态流动性市场做市商（类似 Uniswap V3）
- **DAMM v1/v2**: 动态 AMM 恒定乘积做市商
- **DBC**: 动态联合曲线（代币发射平台）
- **Vault**: 收益聚合器
- **Alpha Vault**: 带反机器人保护的金库
- **M3M3**: 质押赚取手续费

### 工具统计

| 协议 | 静态工具 | 动态工具（IDL） | 总计 | 说明 |
|------|----------|-----------------|------|------|
| **DLMM** | 10 | 74 | 84 | 集中流动性 + 动态费用 |
| **DAMM v2** | 8 | 35 | 43 | 新一代恒定乘积 AMM |
| **DAMM v1** | 5 | 26 | 31 | 旧版 AMM（遗留）|
| **DBC** | 7 | 28 | 35 | 代币发射联合曲线 |
| **Vault** | 4 | - | 4 | 收益优化 |
| **Alpha Vault** | 4 | - | 4 | 反机器人金库 |
| **M3M3** | 5 | - | 5 | 质押手续费 |
| **REST API** | 3 | - | 3 | HTTP API 查询 |
| **总计** | **46** | **163** | **209** | |

---

## 协议类型对比

### 1. DLMM (Dynamic Liquidity Market Maker)

**特点**:
- ✅ 集中流动性（类似 Uniswap V3）
- ✅ 动态费用（根据波动率调整）
- ✅ Bin-based 定价（价格区间）
- ✅ 资本效率高

**适用场景**:
- 高频交易对（SOL/USDC, JUP/USDC）
- 需要精细控制价格区间
- LP 寻求最大化收益

**关键概念**:
- **Bin**: 价格区间，类似 Uniswap V3 的 tick
- **Active Bin**: 当前价格所在的 bin
- **Bin Step**: 价格增量（basis points）

### 2. DAMM v2 (Dynamic AMM v2)

**特点**:
- ✅ 恒定乘积公式（x * y = k）
- ✅ 支持定时激活池
- ✅ 动态手续费
- ✅ NFT 仓位

**适用场景**:
- 标准 AMM 需求
- 不需要集中流动性
- 新代币发射

**vs DAMM v1**:
- v2: NFT 仓位，更灵活
- v1: 遗留版本，推荐迁移到 v2

### 3. DBC (Dynamic Bonding Curve)

**特点**:
- ✅ 联合曲线定价
- ✅ 代币发射专用
- ✅ 自动毕业到 DAMM
- ✅ 创建者手续费

**适用场景**:
- 代币初始发行
- Fair launch（公平发射）
- 自动流动性迁移

**生命周期**:
```
创建 → 购买/出售 → 达到市值 → 毕业（迁移到 DAMM）
```

### 4. Vault / Alpha Vault

**Vault 特点**:
- ✅ 自动复利
- ✅ 收益聚合
- ✅ 简单存取

**Alpha Vault 特点**:
- ✅ Vault 所有功能
- ✅ 反机器人保护
- ✅ 公平分配机制
- ✅ 防抢跑

### 5. M3M3 (Stake for Fee)

**特点**:
- ✅ 质押代币赚取手续费
- ✅ 流动性挖矿替代方案
- ✅ 锁定期机制

---

## REST API vs 链上工具

### REST API 工具（3 个）

| 工具 | 端点 | 用途 |
|------|------|------|
| `meteora_api_list_dlmm_pools` | GET /pair/all | 获取所有 DLMM 池 |
| `meteora_api_get_dlmm_pool` | GET /pair/{address} | 获取单个池详情 |
| `meteora_api_list_damm_pools` | GET /pool/list | 获取所有 DAMM 池 |

**优点**:
- ✅ 快速查询（< 100ms）
- ✅ 聚合数据（TVL, 24h volume, APR）
- ✅ 无需 RPC 调用
- ✅ 历史数据（累计交易量等）

**缺点**:
- ❌ 可能有轻微延迟（缓存）
- ❌ 不适合实时交易决策

**使用场景**:
- 🔍 浏览所有池
- 📊 展示 TVL/APR 排行
- 📈 历史数据分析
- 🎨 UI 展示

### 链上工具（43 个）

**优点**:
- ✅ 实时准确数据
- ✅ 可用于交易构建
- ✅ 无第三方依赖

**缺点**:
- ❌ 较慢（RPC 查询）
- ❌ 需要解析链上数据

**使用场景**:
- 💱 执行交易（swap, add liquidity）
- 🎯 精确报价
- 🔐 构建未签名交易

### 推荐策略

```
┌─────────────────┬────────────────┬───────────────┐
│ 场景            │ 推荐工具类型   │ 示例工具      │
├─────────────────┼────────────────┼───────────────┤
│ 浏览池列表      │ REST API       │ list_dlmm_pools │
│ 展示池详情      │ REST API       │ get_dlmm_pool   │
│ 获取交换报价    │ 链上工具       │ dlmm_swap_quote │
│ 执行交换        │ 链上工具       │ dlmm_swap       │
│ 添加流动性      │ 链上工具       │ dlmm_add_liquidity │
│ 查询用户仓位    │ 链上工具       │ dlmm_get_positions │
│ 显示 APR 排行   │ REST API       │ list_dlmm_pools │
└─────────────────┴────────────────┴───────────────┘
```

---

## 工具分类

### DLMM 工具（10 个静态 + 74 个动态）

#### 查询工具

**`meteora_dlmm_get_pool`** - 获取池信息
```json
{
  "tool": "meteora_dlmm_get_pool",
  "params": {
    "pool_address": "池地址",
    "network": "mainnet"
  }
}
```

**`meteora_dlmm_get_active_bin`** - 获取当前价格 bin
```json
{
  "tool": "meteora_dlmm_get_active_bin",
  "params": {
    "pool_address": "池地址"
  }
}
```

**`meteora_dlmm_get_bins`** - 获取价格区间列表
```json
{
  "tool": "meteora_dlmm_get_bins",
  "params": {
    "pool_address": "池地址",
    "min_bin_id": -100,  // 可选
    "max_bin_id": 100     // 可选
  }
}
```

**`meteora_dlmm_get_positions`** - 获取用户仓位
```json
{
  "tool": "meteora_dlmm_get_positions",
  "params": {
    "pool_address": "池地址",
    "owner": "用户地址"
  }
}
```

#### 交易工具

**`meteora_dlmm_swap_quote`** - 获取交换报价
```json
{
  "tool": "meteora_dlmm_swap_quote",
  "params": {
    "pool_address": "池地址",
    "amount": "1000000",
    "swap_for_y": true,  // true = X→Y, false = Y→X
    "slippage_bps": 50   // 0.5%
  }
}
```

**`meteora_dlmm_swap`** - 执行交换
```json
{
  "tool": "meteora_dlmm_swap",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "amount": "1000000",
    "swap_for_y": true,
    "min_out_amount": "990000",  // 滑点保护
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_dlmm_add_liquidity`** - 添加流动性
```json
{
  "tool": "meteora_dlmm_add_liquidity",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "amount_x": "1000000",
    "amount_y": "1000000",
    "strategy": "SpotBalanced",  // 策略
    "min_bin_id": 100,           // 最小 bin
    "max_bin_id": 200,           // 最大 bin
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**流动性策略**:
- `SpotBalanced`: 平衡当前价格
- `BidAsk`: 挂单策略
- `Spot`: 单边流动性

**`meteora_dlmm_remove_liquidity`** - 移除流动性
```json
{
  "tool": "meteora_dlmm_remove_liquidity",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "position": "仓位地址",
    "bps": 10000,  // 10000 = 100% 全部移除
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_dlmm_claim_fees`** - 领取手续费
```json
{
  "tool": "meteora_dlmm_claim_fees",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "position": "仓位地址",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_dlmm_claim_rewards`** - 领取流动性挖矿奖励
```json
{
  "tool": "meteora_dlmm_claim_rewards",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "position": "仓位地址",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

### DAMM v2 工具（8 个静态 + 35 个动态）

**`meteora_damm_v2_create_pool`** - 创建池
```json
{
  "tool": "meteora_damm_v2_create_pool",
  "params": {
    "user": "创建者地址",
    "token_a_mint": "代币A地址",
    "token_b_mint": "代币B地址",
    "token_a_amount": "1000000",
    "token_b_amount": "1000000",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_damm_v2_swap`** - 交换
```json
{
  "tool": "meteora_damm_v2_swap",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "input_mint": "输入代币地址",
    "amount": "1000000",
    "min_out_amount": "990000",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**其他工具**:
- `meteora_damm_v2_get_pool` - 获取池信息
- `meteora_damm_v2_get_position` - 获取仓位
- `meteora_damm_v2_swap_quote` - 获取报价
- `meteora_damm_v2_add_liquidity` - 添加流动性
- `meteora_damm_v2_remove_liquidity` - 移除流动性
- `meteora_damm_v2_claim_fee` - 领取手续费

### DAMM v1 工具（5 个静态 + 26 个动态）

⚠️ **注意**: DAMM v1 是遗留版本，推荐使用 DAMM v2。

- `meteora_damm_v1_get_pool`
- `meteora_damm_v1_swap_quote`
- `meteora_damm_v1_swap`
- `meteora_damm_v1_deposit`
- `meteora_damm_v1_withdraw`

### DBC 工具（7 个静态 + 28 个动态）

**代币发射工作流程**:

```
1. create_pool → 2. buy/sell → 3. check_graduation → 4. migrate
```

**`meteora_dbc_create_pool`** - 创建发射池
```json
{
  "tool": "meteora_dbc_create_pool",
  "params": {
    "user": "创建者地址",
    "name": "My Token",
    "symbol": "MTK",
    "uri": "https://...",  // 元数据 URI
    "base_amount": "1000000000",  // 初始供应
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_dbc_buy`** - 购买代币
```json
{
  "tool": "meteora_dbc_buy",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "quote_amount": "10000000",  // SOL/USDC 数量
    "min_base_amount": "9900000",  // 最小获得代币
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_dbc_sell`** - 出售代币
```json
{
  "tool": "meteora_dbc_sell",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "base_amount": "1000000",  // 代币数量
    "min_quote_amount": "990000",  // 最小获得 SOL/USDC
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_dbc_check_graduation`** - 检查毕业状态
```json
{
  "tool": "meteora_dbc_check_graduation",
  "params": {
    "pool_address": "池地址"
  }
}
```

**`meteora_dbc_migrate`** - 迁移到 DAMM
```json
{
  "tool": "meteora_dbc_migrate",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "target": "damm_v2",  // 或 damm_v1
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**其他工具**:
- `meteora_dbc_get_pool` - 获取池信息
- `meteora_dbc_get_quote` - 获取买卖报价

### Vault 工具（4 个）

**`meteora_vault_get_info`** - 获取金库信息
```json
{
  "tool": "meteora_vault_get_info",
  "params": {
    "token_mint": "代币地址"
  }
}
```

**`meteora_vault_deposit`** - 存入金库
```json
{
  "tool": "meteora_vault_deposit",
  "params": {
    "token_mint": "代币地址",
    "user": "用户地址",
    "amount": "1000000",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_vault_withdraw`** - 从金库取出
```json
{
  "tool": "meteora_vault_withdraw",
  "params": {
    "token_mint": "代币地址",
    "user": "用户地址",
    "lp_amount": "1000000",  // LP 代币数量
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_vault_get_user_balance`** - 获取用户余额
```json
{
  "tool": "meteora_vault_get_user_balance",
  "params": {
    "token_mint": "代币地址",
    "user": "用户地址"
  }
}
```

### Alpha Vault 工具（4 个）

**类似 Vault，但增加反机器人保护**:
- `meteora_alpha_vault_get_info`
- `meteora_alpha_vault_deposit`
- `meteora_alpha_vault_withdraw`
- `meteora_alpha_vault_claim`

### M3M3 (Stake for Fee) 工具（5 个）

**`meteora_m3m3_stake`** - 质押代币
```json
{
  "tool": "meteora_m3m3_stake",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "amount": "1000000",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_m3m3_unstake`** - 取消质押
```json
{
  "tool": "meteora_m3m3_unstake",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "amount": "1000000",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**`meteora_m3m3_claim_fee`** - 领取手续费
```json
{
  "tool": "meteora_m3m3_claim_fee",
  "params": {
    "pool_address": "池地址",
    "user": "用户地址",
    "wallet_type": "privy",
    "wallet_id": "wallet ID"
  }
}
```

**其他工具**:
- `meteora_m3m3_get_pool` - 获取池信息
- `meteora_m3m3_get_user_balance` - 获取用户余额和可领取手续费

---

## 使用示例

### 示例 1：DLMM 交换流程

```javascript
// 1. 获取池信息（可选，了解池状态）
const poolInfo = await call({
  tool: "meteora_api_get_dlmm_pool",
  params: {
    pool_address: "SOL-USDC DLMM 池地址"
  }
});
// 查看 TVL, APR, 24h volume

// 2. 获取交换报价
const quote = await call({
  tool: "meteora_dlmm_swap_quote",
  params: {
    pool_address: "SOL-USDC DLMM 池地址",
    amount: "100000000",  // 0.1 SOL
    swap_for_y: true,      // SOL → USDC
    slippage_bps: 50       // 0.5%
  }
});
// 检查 quote.estimated_amount_out, quote.price_impact

// 3. 如果满意，执行交换
const result = await call({
  tool: "meteora_dlmm_swap",
  params: {
    pool_address: "SOL-USDC DLMM 池地址",
    user: "你的地址",
    amount: "100000000",
    swap_for_y: true,
    min_out_amount: quote.min_amount_out,
    wallet_type: "privy",
    wallet_id: "你的wallet_id"
  }
});
// result.signature = 交易签名
```

### 示例 2：DLMM 做市（添加流动性）

```javascript
// 1. 决定价格区间
const currentBin = await call({
  tool: "meteora_dlmm_get_active_bin",
  params: {
    pool_address: "池地址"
  }
});
// currentBin.active_bin_id = 当前价格 bin

// 2. 设置价格区间（例如：当前价格 ±10%）
const minBin = currentBin.active_bin_id - 20;
const maxBin = currentBin.active_bin_id + 20;

// 3. 添加流动性
const result = await call({
  tool: "meteora_dlmm_add_liquidity",
  params: {
    pool_address: "池地址",
    user: "你的地址",
    amount_x: "1000000",  // 代币 X 数量
    amount_y: "1000000",  // 代币 Y 数量
    strategy: "SpotBalanced",
    min_bin_id: minBin,
    max_bin_id: maxBin,
    wallet_type: "privy",
    wallet_id: "你的wallet_id"
  }
});

// 4. 定期领取手续费
const fees = await call({
  tool: "meteora_dlmm_claim_fees",
  params: {
    pool_address: "池地址",
    user: "你的地址",
    position: result.position_address,
    wallet_type: "privy",
    wallet_id: "你的wallet_id"
  }
});
```

### 示例 3：代币发射（DBC）

```javascript
// 1. 创建发射池
const pool = await call({
  tool: "meteora_dbc_create_pool",
  params: {
    user: "创建者地址",
    name: "My Awesome Token",
    symbol: "MAT",
    uri: "https://metadata.uri",
    base_amount: "1000000000000",  // 1B tokens
    wallet_type: "privy",
    wallet_id: "你的wallet_id"
  }
});
// pool.pool_address = 新创建的池地址

// 2. 用户购买代币
const buy = await call({
  tool: "meteora_dbc_buy",
  params: {
    pool_address: pool.pool_address,
    user: "买家地址",
    quote_amount: "100000000",  // 0.1 SOL
    min_base_amount: "9900000",
    wallet_type: "privy",
    wallet_id: "buyer_wallet_id"
  }
});

// 3. 检查是否达到毕业条件
const gradStatus = await call({
  tool: "meteora_dbc_check_graduation",
  params: {
    pool_address: pool.pool_address
  }
});

// 4. 如果已毕业，迁移到 DAMM
if (gradStatus.graduated) {
  const migrate = await call({
    tool: "meteora_dbc_migrate",
    params: {
      pool_address: pool.pool_address,
      user: "创建者地址",
      target: "damm_v2",
      wallet_type: "privy",
      wallet_id: "你的wallet_id"
    }
  });
  // migrate.damm_pool_address = 新的 DAMM 池地址
}
```

### 示例 4：Vault 收益优化

```javascript
// 1. 查看 Vault 信息
const vaultInfo = await call({
  tool: "meteora_vault_get_info",
  params: {
    token_mint: "USDC地址"
  }
});
// vaultInfo.apy, vaultInfo.total_deposited

// 2. 存入 Vault
const deposit = await call({
  tool: "meteora_vault_deposit",
  params: {
    token_mint: "USDC地址",
    user: "你的地址",
    amount: "1000000000",  // 1000 USDC
    wallet_type: "privy",
    wallet_id: "你的wallet_id"
  }
});

// 3. 定期查看余额
const balance = await call({
  tool: "meteora_vault_get_user_balance",
  params: {
    token_mint: "USDC地址",
    user: "你的地址"
  }
});
// balance.lp_amount = LP 代币数量
// balance.token_amount = 对应的底层代币数量（包括收益）

// 4. 取出
const withdraw = await call({
  tool: "meteora_vault_withdraw",
  params: {
    token_mint: "USDC地址",
    user: "你的地址",
    lp_amount: balance.lp_amount,  // 全部取出
    wallet_type: "privy",
    wallet_id: "你的wallet_id"
  }
});
```

---

## 最佳实践

### 1. 选择合适的协议

| 需求 | 推荐协议 | 理由 |
|------|----------|------|
| 主流币交换（SOL, USDC） | DLMM | 集中流动性，费用低 |
| 小市值代币交换 | DAMM v2 | 更广泛的价格区间 |
| 代币发射 | DBC | 自动流动性管理 |
| 被动收益 | Vault | 自动复利 |
| 新代币发射（防抢跑） | Alpha Vault | 反机器人保护 |
| 长期质押赚手续费 | M3M3 | 稳定手续费收入 |

### 2. 流动性策略

**DLMM 流动性策略对比**:

```
SpotBalanced (推荐新手):
├─ 50% 资金在当前价格
├─ 25% 在当前价格上方
└─ 25% 在当前价格下方

BidAsk (适合做市商):
├─ 全部资金分布在设定区间
└─ 挂单策略

Spot (适合单边押注):
└─ 全部资金在当前价格
```

**示例**:
```json
// 稳定币对（窄价格区间）
{
  "strategy": "SpotBalanced",
  "min_bin_id": "current - 5",
  "max_bin_id": "current + 5"
}

// 波动代币（宽价格区间）
{
  "strategy": "BidAsk",
  "min_bin_id": "current - 50",
  "max_bin_id": "current + 50"
}
```

### 3. 滑点设置

| 池类型 | 推荐滑点 |
|--------|----------|
| DLMM 稳定币对 | 0.1% (10 bps) |
| DLMM 主流币 | 0.5% (50 bps) |
| DAMM 小市值 | 1-3% (100-300 bps) |
| DBC 早期 | 3-5% (300-500 bps) |

### 4. Gas 优化

- ✅ 批量操作：一次交易完成多个操作
- ✅ 使用 `sponsor: true`（Privy gasless）
- ✅ 设置合理的优先费用

### 5. 监控和维护

**DLMM LP 维护检查清单**:
```
□ 每天：检查仓位是否在活跃区间
□ 每周：领取手续费
□ 价格大幅变化时：调整价格区间
□ 定期：重新平衡仓位
```

**工具**:
```json
// 检查仓位状态
{
  "tool": "meteora_dlmm_get_positions",
  "params": {
    "pool_address": "池地址",
    "owner": "你的地址"
  }
}

// 查看当前活跃 bin
{
  "tool": "meteora_dlmm_get_active_bin",
  "params": {
    "pool_address": "池地址"
  }
}
```

---

## 常见问题

### Q1: DLMM vs DAMM，应该用哪个？

**A**: 
- **DLMM**: 主流交易对，追求最大收益，愿意主动管理
- **DAMM**: 长尾资产，希望简单操作，被动做市

### Q2: Bin Step 是什么？

**A**: 价格增量（basis points）。
- 小 bin step (25-100): 更细粒度，适合稳定币
- 大 bin step (100-1000): 更宽区间，适合波动币

**示例**:
```
Bin Step = 100 (1%)
Bin 0: 价格 = $1.00
Bin 1: 价格 = $1.01
Bin 2: 价格 = $1.02
...
```

### Q3: 如何计算 DLMM 收益？

**A**: 
1. **手续费收益**: swap 时 LP 赚取手续费
2. **流动性挖矿**: 某些池有额外 token 奖励
3. **无常损失**: 价格变化导致的损失

**查看收益**:
```json
{
  "tool": "meteora_api_get_dlmm_pool",
  "params": {
    "pool_address": "池地址"
  }
}
// 查看 fees_24h, apr
```

### Q4: DBC 何时毕业？

**A**: 当池子市值达到预设阈值（graduation_threshold）。

**检查**:
```json
{
  "tool": "meteora_dbc_get_pool",
  "params": {
    "pool_address": "池地址"
  }
}
// current_market_cap vs graduation_threshold
```

### Q5: Alpha Vault 如何防机器人？

**A**:
- 定时开放（时间锁）
- 逐步释放额度
- 地址白名单（可选）
- 最大单次存入限制

### Q6: M3M3 锁定期多久？

**A**: 由池创建者设定，通常 7-30 天。

**查看**:
```json
{
  "tool": "meteora_m3m3_get_pool",
  "params": {
    "pool_address": "池地址"
  }
}
// unstake_lock_period (秒)
```

### Q7: 为什么我的 DLMM 仓位不赚手续费？

**A**: 可能原因：
1. 价格不在你的区间内
2. 没有交易发生
3. 手续费已累积但未领取

**解决**:
- 检查活跃 bin 是否在你的区间
- 调整区间包含当前价格
- 定期领取手续费

### Q8: 如何在 testnet 测试？

**A**:
```json
{
  "network": "devnet",
  "endpoint": "https://api.devnet.solana.com"
}
```

⚠️ 注意：某些功能可能在 devnet 不可用。

### Q9: 动态工具（IDL）vs 静态工具，区别是什么？

**A**:
- **静态工具**: 手动实现，针对常用操作优化
- **动态工具**: 自动生成，覆盖所有程序指令

**推荐**:
- 优先使用静态工具（更稳定，文档更全）
- 高级操作使用动态工具

### Q10: 错误 "Pool account data too small"？

**A**: 池地址可能错误或池不存在。

**检查**:
1. 使用 `meteora_api_list_dlmm_pools` 确认池地址
2. 检查网络（mainnet vs devnet）
3. 确认池类型（DLMM vs DAMM）

---

## 相关资源

### 官方文档
- [Meteora 文档](https://docs.meteora.ag/)
- [DLMM 文档](https://docs.meteora.ag/dlmm)
- [DAMM 文档](https://docs.meteora.ag/damm)
- [DBC 文档](https://docs.meteora.ag/dbc)

### API 文档
- [DLMM API](https://docs.meteora.ag/api-reference/dlmm/overview)

### 工具
- [Meteora 前端](https://app.meteora.ag/)
- [DLMM 分析](https://app.meteora.ag/dlmm)

### 社区
- [Discord](https://discord.gg/meteora)
- [Twitter](https://twitter.com/MeteoraAG)

---

## 更新日志

### v1.0 (2026-01-26)
- ✅ 初始版本
- ✅ 覆盖所有 209 个工具
- ✅ 详细的协议对比
- ✅ REST API vs 链上工具指南
- ✅ 完整工作流程示例
- ✅ 最佳实践和常见问题

---

**维护者**: omniweb3-mcp 团队
**反馈**: 欢迎提交 issues 和 PRs
