# 下一步计划 🎯

## 当前状态总结

### ✅ 已完成
1. **Phase 1 核心架构** (Tasks #1-6)
   - ChainProvider 接口 ✅
   - SolanaProvider 实现 ✅
   - IDL 解析器 ✅
   - 动态工具生成器 ✅
   - Borsh 序列化 ✅
   - 交易构建器 ✅

2. **文档**
   - Phase 1 实现文档（中英文）✅
   - Jupiter 对比分析 ✅
   - 核心算法验证测试 ✅

3. **现有系统**
   - HTTP MCP 服务器 (main.zig) ✅
   - 工具注册表系统 (registry.zig) ✅
   - 182 个手动工具（旧版）✅

### ⚠️ 未完成
- Phase 1 与现有 MCP 服务器的集成
- 实际的 Jupiter/SPL Token 端到端测试
- 动态工具注册到 MCP 服务器

---

## 选项分析

### 选项 A：集成 Phase 1 到现有服务器 🔧
**优先级**: ⭐⭐⭐⭐⭐ 最高

**目标**: 让动态生成的工具在 MCP 服务器中实际可用

**任务列表**:
1. 创建 `DynamicToolRegistry` 管理动态工具
2. 修改 `http_server.zig` 支持动态工具路由
3. 在启动时加载 Jupiter IDL 并生成工具
4. 实现工具调用时的动态分发
5. 测试端到端流程：HTTP请求 → 动态工具 → 交易构建

**优势**:
- ✅ 验证 Phase 1 架构的实际可用性
- ✅ 可以立即看到成果（AI 可以调用动态生成的工具）
- ✅ 为后续 Phase 2/3 打下基础

**挑战**:
- 需要修改现有的工具路由逻辑
- 动态工具与静态工具的命名冲突处理
- 工具元数据（JSON Schema）的正确生成

**预计时间**: 2-3 天

---

### 选项 B：实现混合架构 🔀
**优先级**: ⭐⭐⭐⭐

**目标**: 让动态工具和旧版 REST API 工具共存

**任务列表**:
1. 完成选项 A 的所有任务
2. 保留旧版 Jupiter REST API 工具
3. 创建工具命名空间（如 `jupiter_v6_route` vs `get_jupiter_quote`）
4. 添加工具描述说明链上指令 vs REST API
5. 性能对比测试

**优势**:
- ✅ 用户可以选择使用链上指令或 REST API
- ✅ 保留了旧版的全部功能
- ✅ 对比测试更容易

**挑战**:
- 代码库更复杂
- 需要清晰的文档说明两种工具的区别

**预计时间**: 3-4 天

---

### 选项 C：继续 Phase 2 - EVM Provider 🔗
**优先级**: ⭐⭐⭐

**目标**: 扩展到以太坊生态系统

**任务列表**:
1. 实现 `EvmProvider`（类似 SolanaProvider）
2. ABI 解析器（类似 IDL 解析器）
3. ABI 类型 → JSON Schema 转换
4. RLP 序列化（类似 Borsh）
5. 以太坊交易构建器
6. 测试：Uniswap V3、USDC、Aave

**优势**:
- ✅ 验证架构的通用性
- ✅ 支持最大的智能合约生态
- ✅ 展示多链能力

**挑战**:
- 需要先完成选项 A（集成）
- EVM 生态复杂（代理合约、升级模式等）
- ABI 编码比 Borsh 复杂

**预计时间**: 3-4 周

---

### 选项 D：优化和测试 Phase 1 🧪
**优先级**: ⭐⭐⭐

**目标**: 完善 Phase 1 的实现细节

**任务列表**:
1. 实际获取 Jupiter/SPL Token IDL
2. 端到端测试：IDL → 工具生成 → 交易构建 → 模拟执行
3. 处理复杂类型（嵌套结构、自定义类型）
4. 添加账户派生（PDA）支持
5. 添加交易模拟
6. 性能优化（IDL 缓存、工具缓存）

**优势**:
- ✅ 发现并修复边缘情况
- ✅ 提高鲁棒性
- ✅ 更好的用户体验

**挑战**:
- 可能遇到 Zig 0.16 的更多兼容性问题
- 需要 Solana RPC 访问

**预计时间**: 1-2 周

---

### 选项 E：生产环境部署 🚀
**优先级**: ⭐⭐

**目标**: 部署可用的 MCP 服务

**任务列表**:
1. 完成选项 A（必须）
2. Docker 化
3. 配置文件管理
4. 日志和监控
5. 部署到云服务（Railway/Fly.io/AWS）
6. 文档：API 文档、使用教程

**优势**:
- ✅ 实际可用的服务
- ✅ 用户反馈

**挑战**:
- 需要先完成基础功能
- 运维复杂度

**预计时间**: 1-2 周

---

## 推荐路径 🎯

### 第一阶段：验证和集成（1周）

**Week 1: 集成 Phase 1**
```
Day 1-2: 选项 A - 集成动态工具到 MCP 服务器
  - 创建 DynamicToolRegistry
  - 修改 http_server.zig
  - 基础测试

Day 3-4: 选项 D（部分）- 实际测试
  - 加载真实 Jupiter IDL
  - 端到端测试
  - 修复发现的问题

Day 5: 选项 B（部分）- 混合架构初步
  - 工具命名规范
  - 文档说明
```

**交付物**:
- ✅ 可运行的 MCP 服务器
- ✅ 动态生成 6 个 Jupiter 链上工具
- ✅ 保留 47 个旧版 Jupiter REST API 工具
- ✅ 端到端测试通过

### 第二阶段：扩展（2-3周）

**Week 2-3: Phase 2 - EVM Provider**
```
Week 2:
  - EvmProvider 骨架
  - ABI 解析器
  - 类型转换

Week 3:
  - RLP 序列化
  - 交易构建
  - 测试（Uniswap、USDC）
```

**交付物**:
- ✅ 支持 Solana + EVM
- ✅ 验证架构通用性

### 第三阶段：生产化（1周）

**Week 4: 部署和文档**
```
Day 1-2: 性能优化
Day 3-4: Docker + 部署
Day 5: 文档和教程
```

**交付物**:
- ✅ 公开可用的 MCP 服务
- ✅ 完整的用户文档

---

## 立即开始：选项 A 详细任务 🚀

### Task 1: 创建 DynamicToolRegistry

**文件**: `src/tools/dynamic/registry.zig`

```zig
const std = @import("std");
const mcp = @import("mcp");
const SolanaProvider = @import("../../providers/solana/provider.zig").SolanaProvider;

pub const DynamicToolRegistry = struct {
    allocator: std.mem.Allocator,
    solana_provider: ?*SolanaProvider,
    tools: std.ArrayList(mcp.tools.Tool),

    pub fn init(allocator: std.mem.Allocator) DynamicToolRegistry {
        return .{
            .allocator = allocator,
            .solana_provider = null,
            .tools = std.ArrayList(mcp.tools.Tool).init(allocator),
        };
    }

    pub fn deinit(self: *DynamicToolRegistry) void {
        if (self.solana_provider) |provider| {
            provider.deinit();
        }
        self.tools.deinit();
    }

    /// Load Jupiter IDL and generate tools
    pub fn loadJupiter(self: *DynamicToolRegistry) !void {
        const provider = try SolanaProvider.init(self.allocator, "https://api.mainnet-beta.solana.com");
        self.solana_provider = provider;

        const meta = try provider.resolver.resolve(
            self.allocator,
            "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"
        );

        const chain_prov = provider.asChainProvider();
        const tools = try chain_prov.generateTools(self.allocator, &meta);

        try self.tools.appendSlice(tools);
    }

    pub fn registerAll(self: *DynamicToolRegistry, server: *mcp.Server) !void {
        for (self.tools.items) |tool| {
            try server.addTool(tool);
        }
    }
};
```

### Task 2: 修改 main.zig 初始化动态工具

```zig
const dynamic_tools = @import("tools/dynamic/registry.zig");

fn run(init: std.process.Init) !void {
    // ... existing code ...

    // Initialize dynamic tools
    var dyn_registry = dynamic_tools.DynamicToolRegistry.init(allocator);
    defer dyn_registry.deinit();

    // Load Jupiter tools from IDL
    try dyn_registry.loadJupiter();

    const setup = http_server.ServerSetup{
        .name = "omniweb3-mcp",
        .version = "0.1.0",
        .title = "Omni Web3 MCP",
        .description = "Cross-chain Web3 MCP server with dynamic tool generation",
        .enable_logging = true,
        .register = registerAllTools,
        .dynamic_registry = &dyn_registry,  // Pass to setup
    };

    // ... rest of code ...
}

fn registerAllTools(server: *mcp.Server, dyn_registry: *dynamic_tools.DynamicToolRegistry) !void {
    // Register static tools
    try tools.registerAll(server);

    // Register dynamic tools
    try dyn_registry.registerAll(server);
}
```

### Task 3: 测试脚本

**文件**: `scripts/test_dynamic_tools.sh`

```bash
#!/bin/bash
# 测试动态工具生成

set -e

echo "🚀 Starting MCP server with dynamic tools..."
zig build run &
SERVER_PID=$!

sleep 3

echo "📋 Listing all tools..."
curl http://localhost:8765/tools | jq '.tools[] | select(.name | startswith("jupiter_"))'

echo ""
echo "✅ Testing jupiter_route tool..."
curl -X POST http://localhost:8765/tool/jupiter_route \
  -H "Content-Type: application/json" \
  -d '{
    "routePlan": [],
    "inAmount": "1000000",
    "quotedOutAmount": "990000",
    "slippageBps": 50,
    "platformFeeBps": 0
  }' | jq

kill $SERVER_PID
echo "✅ Test complete!"
```

---

## 开始实施

### 命令清单

```bash
# 1. 创建动态工具注册表
mkdir -p src/tools/dynamic
vim src/tools/dynamic/registry.zig  # 实现上述代码

# 2. 修改 main.zig
vim src/main.zig  # 添加动态工具初始化

# 3. 修改 http_server.zig（如需要）
vim src/http_server.zig  # 支持动态工具路由

# 4. 创建测试脚本
vim scripts/test_dynamic_tools.sh
chmod +x scripts/test_dynamic_tools.sh

# 5. 构建和测试
zig build
./scripts/test_dynamic_tools.sh

# 6. 验证
curl http://localhost:8765/tools | jq '.tools[] | select(.name | startswith("jupiter_"))'
```

---

## 成功标准 ✅

1. **功能性**
   - [ ] MCP 服务器成功启动
   - [ ] 动态加载 Jupiter IDL
   - [ ] 生成 6 个 jupiter_* 工具
   - [ ] 工具列表包含动态工具
   - [ ] 可以调用动态工具并返回交易

2. **质量**
   - [ ] 无内存泄漏
   - [ ] 错误处理完善
   - [ ] 日志清晰

3. **文档**
   - [ ] README 更新说明动态工具
   - [ ] API 文档包含动态工具示例

---

## 后续展望 🔮

完成选项 A 后：

1. **短期（1-2周）**
   - 添加更多 Solana 程序（Metaplex、Raydium）
   - 优化 IDL 缓存
   - 添加工具热重载

2. **中期（1个月）**
   - Phase 2: EVM Provider
   - 多链工具路由
   - 统一的资源 URI 格式

3. **长期（2-3个月）**
   - Phase 3-5: 全面多链支持
   - Intent-based API
   - 公开部署

---

**更新时间**: 2026年1月26日
**当前分支**: new-mcp-arc
**建议下一步**: 立即开始 **选项 A - 集成 Phase 1 到 MCP 服务器** 🚀
