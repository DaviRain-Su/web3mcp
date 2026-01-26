# 下一步计划 🎯

> **最后更新**: 2026-01-26
> **当前分支**: main
> **Phase 1 状态**: ✅ 完成

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
- [x] Phase 1 测试文档 ← **新增**
- [x] Jupiter 对比分析
- [x] 混合架构文档

### 📊 最终统计

```
总工具数: 171
├── 静态工具: 165 (手动编码的 REST API 包装器)
│   ├── Jupiter REST API: ~47 工具
│   ├── Privy 钱包: ~12 工具
│   ├── Meteora: ~30 工具
│   ├── DFlow: ~20 工具
│   └── 其他 Solana RPC: ~56 工具
│
└── 动态工具: 6 (从 Jupiter IDL 自动生成)
    ├── jupiter_route
    ├── jupiter_sharedAccountsRoute
    ├── jupiter_exactOutRoute
    ├── jupiter_setTokenLedger
    ├── jupiter_createOpenOrders
    └── jupiter_sharedAccountsRouteWithTokenLedger
```

**生产环境**: ✅ https://api.web3mcp.app/

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

## Phase 2 规划：多链扩展 🌐

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
- [Phase 1 测试文档](./PHASE1_TESTING.md) ← **新增**
- [混合架构文档](./HYBRID_ARCHITECTURE.md)
- [Jupiter 对比分析](./JUPITER_COMPARISON.md)

---

**下一步行动**: 开始实施**路径 1 - 快速扩展** 🚀

1. 添加 Metaplex 工具（预计 2-3 天）
2. 添加 Raydium 工具（预计 2-3 天）
3. 添加 Orca 工具（预计 1-2 天）
4. 开始 EVM Provider 设计（预计 2-3 周）
