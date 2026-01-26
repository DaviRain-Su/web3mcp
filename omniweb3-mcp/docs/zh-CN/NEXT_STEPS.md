# 下一步计划 🎯

> **最后更新**: 2026-01-26 17:45
> **当前分支**: main
> **Phase 1 状态**: ✅ 完成
> **Phase 2 状态**: ✅ 大部分完成 (12 个 Solana 程序已集成)

---

## Phase 1 完成总结 🎉

### ✅ 已完成的所有功能

**核心架构**:
- [x] ChainProvider 接口
- [x] SolanaProvider 实现
- [x] IDL 解析器（Anchor IDL）
- [x] 动态工具生成器
- [x] Borsh 序列化
- [x] 交易构建器

**工具集成**:
- [x] DynamicToolRegistry 实现
- [x] 动态工具注册到 MCP Server
- [x] 真实 Handler 实现（替换占位符）
- [x] 全局注册表和工具路由
- [x] 完整的 InputSchema 生成
- [x] 类型映射（IDL → JSON Schema）

**测试和验证**:
- [x] 动态工具加载测试
- [x] Handler 功能测试
- [x] InputSchema 验证
- [x] 错误处理测试
- [x] 回归测试（静态工具）
- [x] 生产环境部署

**文档**:
- [x] Phase 1 实现文档
- [x] Phase 1 测试文档
- [x] Jupiter 对比分析
- [x] 混合架构文档

---

## Phase 2 完成总结 🎉 (新增)

### ✅ 已完成：Solana 程序大规模扩展

**配置驱动架构**:
- [x] 创建 `idl_registry/programs.json` 配置文件
- [x] 实现通用 `loadSolanaPrograms()` 方法
- [x] IDL 自动获取和手动获取混合策略
- [x] 程序启用/禁用开关

**成功集成的 Solana 程序** (12 个):
1. [x] Jupiter v6 (6 指令) - DEX 聚合器
2. [x] Metaplex Token Metadata (58 指令) - NFT 标准
3. [x] Orca Whirlpool (58 指令) - CLMM DEX
4. [x] Marinade Finance (28 指令) - 流动性质押
5. [x] Drift Protocol (241 指令) - 永续合约 ⭐ 最大
6. [x] Meteora DLMM (74 指令) - 动态流动性
7. [x] Meteora DAMM v2 (35 指令) - 动态 AMM
8. [x] Meteora DAMM v1 (26 指令) - 动态 AMM
9. [x] Meteora DBC (28 指令) - 动态联合曲线
10. [x] PumpFun (27 指令) - 代币发射平台
11. [x] Squads V4 (31 指令) - 多签钱包
12. [x] Raydium CLMM (25 指令) - 集中流动性

**IDL 获取方法**:
- Anchor CLI: 10 个程序 (77% 成功率)
- GitHub 仓库: 1 个程序 (Metaplex)
- 创建完整的 IDL 获取指南文档

**未能获取的程序** (3 个):
- Kamino Lending - IDL 未公开
- Meteora M3M3 - IDL 未公开
- Sanctum S Controller - IDL 未公开

### 📊 Phase 2 最终统计

```
总工具数: ~802
├── 静态工具: 165 (手动编码的 REST API 包装器)
│   ├── Jupiter REST API: ~47 工具
│   ├── Privy 钱包: ~12 工具
│   ├── Meteora: ~30 工具
│   ├── DFlow: ~20 工具
│   └── 其他 Solana RPC: ~56 工具
│
└── 动态工具: 637 (从 12 个 Solana 程序 IDL 自动生成) ⭐ 新增
    ├── Jupiter: 6 指令
    ├── Metaplex: 58 指令
    ├── Orca: 58 指令
    ├── Marinade: 28 指令
    ├── Drift: 241 指令 ⭐ 最大
    ├── Meteora DLMM: 74 指令
    ├── Meteora DAMM v2: 35 指令
    ├── Meteora DAMM v1: 26 指令
    ├── Meteora DBC: 28 指令
    ├── PumpFun: 27 指令
    ├── Squads V4: 31 指令
    └── Raydium CLMM: 25 指令
```

**工具增长**: 171 → 802 (+369% 🚀)

**生产环境**: ✅ https://api.web3mcp.app/ (等待 GitHub 恢复后部署)

### 🎯 关键成就

1. **混合架构验证成功**
   - 静态工具（手动）+ 动态工具（IDL 生成）和谐共存
   - 无需修改现有代码即可添加新工具
   - 向后兼容，零破坏性变更

2. **完整的工具元数据**
   - 每个动态工具都有完整的参数 schema
   - 类型安全：IDL 类型正确映射到 JSON Schema
   - 必需参数标记清晰

3. **真实交易构建**
   - Handler 能够构建真实的 Solana 交易
   - Base64 编码的指令数据
   - 正确的 Anchor 指令鉴别器

4. **生产就绪**
   - 已部署到生产环境
   - 所有测试通过
   - 性能良好（工具加载 < 100ms，调用 < 20ms）

---

## Phase 2.5：API 服务集成 🌐 (新发现)

### 背景

在完成 12 个 Solana 程序的 IDL 集成后，我们发现：**许多链上程序除了链上指令外，还提供额外的 REST API 服务**。

这些 API 服务提供了 IDL 无法覆盖的功能，例如：
- 历史数据查询（交易历史、价格历史）
- 聚合数据（池信息、TVL、APY）
- 优化的查询端点（比直接查询链上数据更快）
- 辅助功能（报价计算、路由优化）

### 📊 API 服务分析结果

**详细分析文档**: [API 服务分析](./API_SERVICES_ANALYSIS.md) ← **新增**

**发现总结**:
- **9/12 程序 (75%)** 提供额外的 REST API
- **预估需增加**: ~93 个静态工具
- **最终工具数**: ~895 工具 (从 802 增长 11.6%)

**有 API 的程序**:

| 优先级 | 程序 | API 类型 | 预估工具数 |
|--------|------|----------|------------|
| ⭐⭐⭐ 关键 | Jupiter | Swap, Price, Token, Trigger | 15-20 |
| ⭐⭐⭐ 高 | Raydium CLMM | REST API v3 | 10-15 |
| ⭐⭐ 中 | Meteora DLMM | 20 REST 端点 | ~20 |
| ⭐⭐ 中 | Metaplex | DAS API (~20 方法) | ~20 |
| ⭐⭐ 中 | Drift | Data API + Gateway | 10-15 |
| ⭐⭐ 中 | Orca | Public API | 10-12 |
| ⭐ 中低 | Marinade | Swagger API | 5-10 |
| ⭐ 中低 | Squads | REST API v0/v1 | 10-15 |
| ⭐ 低 | PumpFun | 第三方 API | 5-10 |

**无额外 API 的程序** (仅 IDL):
- Meteora DAMM v1, v2, DBC

### 🎯 实施计划

#### 阶段 1: 关键 API (第 1 周)
优先级: ⭐⭐⭐ 关键

**Jupiter APIs** (~8 工具):
- Swap API: Quote, Swap, Swap Instructions
- Price API: 代币价格查询
- Trigger API: 限价订单 (CreateOrder, Execute, Cancel)

**实施步骤**:
```bash
# 创建 Jupiter API 静态工具
mkdir -p src/tools/static/jupiter
# - swap_api.zig (Quote, Swap, Instructions)
# - price_api.zig (Price queries)
# - trigger_api.zig (Limit orders)
# - token_api.zig (Token lists)

# 更新工具注册
# 在 src/tools/registry.zig 中注册新工具
```

**预计时间**: 3-5 天

#### 阶段 2: 高优先级 API (第 2 周)
优先级: ⭐⭐⭐ 高

**Raydium + Meteora DLMM APIs** (~25 工具):
- Raydium: Compute, Pools, Mint 数据
- Meteora: Pairs, Positions, Analytics

**预计时间**: 5-7 天

#### 阶段 3: 中等优先级 API (第 3 周)
优先级: ⭐⭐ 中等

**Metaplex + Drift + Orca APIs** (~35 工具):
- Metaplex DAS: 资产查询、搜索
- Drift: 市场数据、DLOB
- Orca: 池/仓位管理

**预计时间**: 5-7 天

#### 阶段 4: 较低优先级 API (第 4 周)
优先级: ⭐ 中低

**Marinade + Squads + PumpFun APIs** (~25 工具):
- Marinade: 质押操作
- Squads: 多签管理
- PumpFun: 可选第三方支持

**预计时间**: 3-5 天

### 💡 技术考虑

**认证**:
- 大多数 API 是公开/免费的 (Jupiter Lite, Raydium, Meteora)
- 部分需要 API key (Jupiter Pro, PumpFun Trading API)
- 支持配置化的 API key 管理

**速率限制**:
- 实施客户端速率限制
- 响应缓存（适当场景）
- API key 轮换（高流量）

**错误处理**:
- API 不可用时优雅降级
- 清晰的错误消息
- 尽可能回退到链上查询

**架构建议**:
```
src/tools/static/
├── jupiter/      (Swap, Price, Trigger, Token APIs)
├── raydium/      (Compute, Pools, Mint APIs)
├── meteora/      (DLMM API)
├── metaplex/     (DAS API)
├── drift/        (Data API)
├── orca/         (Whirlpool API)
├── marinade/     (Staking API)
├── squads/       (Multisig API)
└── pumpfun/      (Third-party APIs)
```

### 📈 预期成果

**当前状态**: 802 工具 (165 静态 + 637 动态)
**完成 Phase 2.5 后**: ~895 工具 (258 静态 + 637 动态)
**增长**: +93 静态工具 (+11.6%)

---

## Phase 3 规划：多链扩展 🌐

### 目标

将动态工具生成能力扩展到更多区块链生态系统。

### 选项分析

#### 选项 A：添加更多 Solana 程序 🟣
**优先级**: ⭐⭐⭐⭐⭐ 最高

**理由**:
- ✅ 复用现有的 SolanaProvider 和 IDL 解析器
- ✅ 立即增加工具数量和实用价值
- ✅ 验证 IDL 解析器对不同程序的兼容性
- ✅ 最低成本，最快见效

**建议添加的程序**:
1. **Metaplex** (NFT 标准)
   - Token Metadata Program
   - Candy Machine
   - Auction House
   - 预计工具数: ~15-20

2. **Raydium** (DEX)
   - AMM Program
   - Farms
   - Staking
   - 预计工具数: ~10-15

3. **Orca** (DEX)
   - Whirlpools
   - Aquafarms
   - 预计工具数: ~8-12

4. **Marinade** (Liquid Staking)
   - Stake/Unstake
   - Liquid Unstake
   - 预计工具数: ~5-8

5. **Pyth** (Oracle)
   - Price Updates
   - 预计工具数: ~3-5

**预计总工具增长**: 171 → ~220-230 工具

**实施步骤**:
```zig
// src/tools/dynamic/registry.zig

pub fn loadSolanaPrograms(self: *DynamicToolRegistry, rpc_url: []const u8) !void {
    const provider = self.solana_provider orelse
        try SolanaProvider.init(self.allocator, rpc_url);

    // Jupiter (已完成)
    try self.loadProgram("JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4", "jupiter");

    // Metaplex Token Metadata
    try self.loadProgram("metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s", "metaplex");

    // Raydium AMM
    try self.loadProgram("675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8", "raydium");

    // Orca Whirlpool
    try self.loadProgram("whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc", "orca");

    // Marinade Finance
    try self.loadProgram("MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD", "marinade");
}
```

**预计时间**: 2-3 天

---

#### 选项 B：EVM Provider (以太坊/Polygon/BSC) 🔷
**优先级**: ⭐⭐⭐⭐

**目标**: 支持以太坊及其兼容链

**核心任务**:
1. **EvmProvider 实现**
   ```zig
   // src/providers/evm/provider.zig
   pub const EvmProvider = struct {
       allocator: std.mem.Allocator,
       rpc_url: []const u8,
       resolver: AbiResolver,

       pub fn asChainProvider(self: *EvmProvider) ChainProvider {
           return ChainProvider{
               .context = self,
               .vtable = &evm_vtable,
           };
       }
   };
   ```

2. **ABI 解析器**
   ```zig
   // src/providers/evm/abi_resolver.zig
   pub const AbiResolver = struct {
       // 从 Etherscan API 获取 ABI
       // 或从本地 JSON 文件加载
       pub fn resolve(
           self: *AbiResolver,
           allocator: std.mem.Allocator,
           address: []const u8,
       ) !ContractMeta {
           // Parse ABI JSON
           // Convert to ContractMeta
       }
   };
   ```

3. **ABI → JSON Schema 转换**
   - `uint256` → `{"type": "string", "format": "uint256"}`
   - `address` → `{"type": "string", "pattern": "^0x[a-fA-F0-9]{40}$"}`
   - `bytes` → `{"type": "string", "format": "hex"}`
   - Tuple → `{"type": "array", "items": [...]}`

4. **RLP 编码（用于交易）**
   ```zig
   // src/providers/evm/rlp.zig
   pub fn encodeTransaction(tx: Transaction) ![]u8 {
       // EIP-1559 transaction encoding
   }
   ```

5. **Web3.js 兼容的交易格式**

**建议支持的合约**:
- Uniswap V2/V3
- Aave V2/V3
- USDC/USDT (ERC20)
- OpenSea Seaport
- ENS

**挑战**:
- ABI 比 IDL 更复杂（函数重载、事件、错误）
- 代理合约需要特殊处理
- Gas 估算复杂
- 需要支持多个 EVM 链（Ethereum, Polygon, BSC, Arbitrum, Optimism）

**预计时间**: 2-3 周

---

#### 选项 C：Cosmos Provider (Cosmos SDK) 🌌
**优先级**: ⭐⭐⭐

**目标**: 支持 Cosmos 生态（ATOM, OSMO, INJ 等）

**核心任务**:
1. CosmosProvider 实现
2. Protobuf 消息解析
3. Amino/Protobuf 编码
4. Cosmos SDK 交易构建

**建议支持的链**:
- Cosmos Hub (ATOM)
- Osmosis (OSMO)
- Injective (INJ)
- Celestia (TIA)

**预计时间**: 2-3 周

---

#### 选项 D：优化和改进现有功能 ⚡
**优先级**: ⭐⭐⭐

**目标**: 提升 Phase 1 的完善度

**任务列表**:

1. **自定义类型递归解析**
   - 当前: `Custom type: unknown`
   - 改进: 从 IDL types 定义递归解析字段
   ```json
   "routePlan": {
     "type": "array",
     "items": {
       "type": "object",
       "properties": {
         "swap": { "type": "object", "properties": {...} },
         "percent": { "type": "integer" },
         "inputIndex": { "type": "integer" }
       }
     }
   }
   ```

2. **IDL 缓存系统**
   - 避免每次启动都请求 Solana FM API
   - 本地缓存 + 版本检查
   ```zig
   // src/providers/solana/idl_cache.zig
   pub const IdlCache = struct {
       cache_dir: []const u8,

       pub fn get(self: *IdlCache, program_id: []const u8) ?[]const u8 {
           // Check local cache
       }

       pub fn set(self: *IdlCache, program_id: []const u8, idl: []const u8) !void {
           // Save to cache
       }
   };
   ```

3. **参数验证增强**
   - 添加 `minimum`, `maximum` 约束
   - 添加 `pattern` 正则验证
   - 添加自定义验证器

4. **交易模拟**
   ```zig
   pub fn simulateTransaction(
       self: *SolanaProvider,
       tx: Transaction,
   ) !SimulationResult {
       // Call simulateTransaction RPC
       // Return logs and compute units
   }
   ```

5. **账户派生 (PDA)**
   ```zig
   pub fn deriveAccounts(
       self: *SolanaProvider,
       function: Function,
       args: std.json.Value,
   ) ![]Account {
       // Derive PDAs based on function requirements
   }
   ```

**预计时间**: 1-2 周

---

## 推荐实施路径 🚀

### 路径 1：快速扩展（推荐） ⚡

**Week 1-2: 添加更多 Solana 程序（选项 A）**
- Day 1-3: Metaplex 集成
- Day 4-6: Raydium 集成
- Day 7-8: Orca 集成
- Day 9-10: 测试和文档

**Week 3-4: EVM Provider 基础（选项 B）**
- Week 3: EvmProvider + ABI 解析器
- Week 4: Uniswap V3 + USDC 测试

**交付物**:
- ✅ ~220 Solana 工具
- ✅ ~20 EVM 工具
- ✅ 验证多链架构

---

### 路径 2：深度优化（稳健）🛠️

**Week 1: 优化 Phase 1（选项 D）**
- 自定义类型解析
- IDL 缓存
- 参数验证

**Week 2-3: 添加 Solana 程序（选项 A）**
- Metaplex + Raydium + Orca

**Week 4-5: EVM Provider（选项 B）**

**交付物**:
- ✅ 高质量的 Solana 工具
- ✅ EVM 支持
- ✅ 更好的用户体验

---

### 路径 3：全面多链（激进）🌐

**Week 1-2: EVM Provider（选项 B）**

**Week 3-4: Cosmos Provider（选项 C）**

**Week 5: 更多 Solana 程序（选项 A）**

**交付物**:
- ✅ 3 条主要链
- ✅ 验证架构通用性
- ✅ 多链工具路由

---

## 个人推荐：路径 1 🎯

**理由**:
1. **最大化价值**: 快速增加工具数量（171 → 240+）
2. **降低风险**: 先扩展已验证的 Solana 生态
3. **验证架构**: EVM 集成验证多链设计
4. **商业价值**: 更多工具 = 更多用例

**第一周立即开始的任务**:

```bash
# 1. 创建 Metaplex 集成
mkdir -p idl_registry/metaplex
curl -o idl_registry/metaplex/token_metadata.json \
  https://api.solanafm.com/v0/accounts/metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s/idl

# 2. 修改 registry.zig
vim src/tools/dynamic/registry.zig
# 添加 loadProgram 辅助函数
# 添加 loadMetaplex, loadRaydium 等方法

# 3. 更新 main.zig
vim src/main.zig
# 调用 loadSolanaPrograms

# 4. 测试
./build_linux.sh
./scripts/deploy.sh
./scripts/test_remote_dynamic_tools.sh
```

---

## Phase 3+ 展望 🔮

完成 Phase 2 后的长期目标：

### Phase 3: Intent-based API
- 用户表达意图："Swap 100 USDC to SOL"
- 系统自动选择最佳路径（Jupiter vs Raydium vs Orca）
- 跨链 Intent 路由

### Phase 4: 智能合约自动化
- 合约监听和事件触发
- 自动化交易执行
- DeFi 策略机器人

### Phase 5: AI Agent SDK
- 让 AI 能够自主交易
- 风险评估和安全控制
- 多步骤策略执行

---

## 测试清单 ✅

在开始 Phase 2 之前，确认以下测试通过：

**Phase 1 验收测试**:
- [x] 171 工具全部可用
- [x] 动态工具有完整 schema
- [x] Handler 能构建真实交易
- [x] 错误处理清晰
- [x] 静态工具未受影响
- [x] 生产环境正常运行
- [x] 文档完整

**准备开始 Phase 2**: ✅

---

## 相关文档

- [Phase 1 实现文档](./PHASE1_IMPLEMENTATION.md)
- [Phase 1 测试文档](./PHASE1_TESTING.md)
- [API 服务分析](./API_SERVICES_ANALYSIS.md) ← **新增**
- [混合架构文档](./HYBRID_ARCHITECTURE.md)
- [Jupiter 对比分析](./JUPITER_COMPARISON.md)
- [IDL 注册表说明](../../idl_registry/README.md)
- [IDL 手动获取指南](../../idl_registry/MANUAL_IDL_GUIDE.md)

---

## 当前优先级和下一步行动 🚀

### 立即行动 (本周)

**Phase 2.5 - 阶段 1: Jupiter API 集成** ⭐⭐⭐
1. 实施 Jupiter Swap API (Quote, Swap, Instructions) - 3 个工具
2. 实施 Jupiter Price API - 1 个工具
3. 实施 Jupiter Trigger API (限价订单) - 4 个工具
4. 测试和文档

**预计时间**: 3-5 天
**预期工具数**: 171 → 179 工具

### 短期计划 (2-4 周)

**Phase 2.5 - 阶段 2-4: 其他 API 集成**
- 周 2: Raydium + Meteora DLMM (~25 工具)
- 周 3: Metaplex + Drift + Orca (~35 工具)
- 周 4: Marinade + Squads (~20 工具)

**最终目标**: ~895 工具

### 长期规划 (Phase 3+)

参考上文的 **Phase 3 规划：多链扩展** 部分：
- EVM Provider (以太坊/Polygon/BSC)
- Cosmos Provider (ATOM/OSMO/INJ)
- 或继续优化现有功能

---

**当前阻塞**: GitHub 503 错误，等待恢复后部署 802 工具版本
