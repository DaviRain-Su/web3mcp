# 混合架构文档 🔀

## 概述

OmniWeb3 MCP 采用**混合架构**，结合了两种工具生成策略：

1. **静态工具**（手动编码）- 传统的 REST API 包装器
2. **动态工具**（自动生成）- 从区块链程序 IDL/ABI 生成

这种架构充分利用了两种方法的优势，为 AI 代理提供最全面的 Web3 功能。

---

## 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                      MCP HTTP Server                         │
│                     (http_server.zig)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Tool Registry (Hybrid)                      │
│                  (tools/registry.zig)                        │
│                                                              │
│  registerAllWithDynamic(server, dynamic_registry)           │
└───────┬────────────────────────────────────┬────────────────┘
        │                                    │
        ▼                                    ▼
┌──────────────────┐              ┌────────────────────────────┐
│  Static Tools    │              │   Dynamic Tools            │
│  (手动实现)      │              │   (自动生成)              │
├──────────────────┤              ├────────────────────────────┤
│ • common/*       │              │ • DynamicToolRegistry      │
│ • unified/*      │              │ • IDL Resolver             │
│ • evm/*          │              │ • ChainProvider VTable     │
│ • solana/*       │              │ • Transaction Builder      │
│ • privy/*        │              │                            │
│                  │              │ Supported:                 │
│ 总计: ~182 工具  │              │ • Solana/Anchor (IDL)      │
│                  │              │ • Future: EVM (ABI)        │
└──────────────────┘              └────────────────────────────┘
```

---

## 工具对比：Jupiter 示例

以 Jupiter DEX 为例，混合架构的优势：

### 静态工具（旧版 REST API 包装器）

**特点**：
- ✅ 覆盖 47 个 Jupiter 功能
- ✅ 包含查询类 API（代币、价格、投资组合）
- ✅ 包含高级功能（Ultra、DBC Studio）
- ✅ 开箱即用，无需 RPC
- ❌ 依赖 Jupiter 中心化服务
- ❌ 每个功能需手动编码

**示例**：
```
get_jupiter_quote          - 获取最优价格路由
get_jupiter_tokens         - 获取支持的代币列表
get_jupiter_price          - 获取代币实时价格
submit_jupiter_swap        - 通过 REST API 提交交易
...
```

### 动态工具（Phase 1 IDL 生成）

**特点**：
- ✅ 自动生成 6 个链上指令工具
- ✅ 完全去中心化（直接与链交互）
- ✅ 零手动编码
- ✅ 可扩展到任何 Anchor 程序
- ❌ 不支持纯 REST API 功能
- ❌ 需要用户自己处理路由优化

**示例**（从 Jupiter v6 IDL 自动生成）：
```
jupiter_route                    - 执行代币兑换（最常用）
jupiter_sharedAccountsRoute      - 使用共享账户的路由
jupiter_exactOutRoute            - 精确输出金额的路由
jupiter_setTokenLedger           - 设置代币账本
jupiter_createOpenOrders         - 创建 OpenBook 订单账户
jupiter_createProgramOpenOrders  - 创建程序 OpenBook 账户
```

### 覆盖功能分析

| 功能类别           | 静态工具 | 动态工具 | 说明                    |
|--------------------|----------|----------|-------------------------|
| Swap 基础指令      | ✓        | ✓        | 从 Jupiter v6 IDL 生成  |
| 路由优化           | ✓        | ✗        | 需要 REST API           |
| Limit Order        | ✓        | ✓        | 单独程序（如有 IDL）    |
| DCA/Recurring      | ✓        | ✓        | 单独程序（如有 IDL）    |
| 代币信息查询       | ✓        | ✗        | 纯 REST API             |
| 价格查询           | ✓        | ✗        | 纯 REST API             |
| 投资组合统计       | ✓        | ✗        | 纯 REST API             |
| DBC Studio         | ✓        | ?        | 可能是混合架构          |
| Ultra 高级功能     | ✓        | ✗        | 高级 REST API           |

**结论**：混合架构让用户可以选择：
- 使用静态工具获取路由优化和价格信息
- 使用动态工具执行去中心化链上交易

---

## 实现细节

### 1. 工具注册流程

**main.zig** - 入口点
```zig
fn run(init: std.process.Init) !void {
    const allocator = ts_allocator.allocator();

    // 1. 初始化动态工具注册表
    var dyn_registry = dynamic_tools.DynamicToolRegistry.init(allocator);
    defer dyn_registry.deinit();

    // 2. 加载 Jupiter IDL（可选）
    const rpc_url = init.environ_map.get("SOLANA_RPC_URL") orelse "https://api.mainnet-beta.solana.com";
    const enable_dynamic = init.environ_map.get("ENABLE_DYNAMIC_TOOLS");

    if (enable_dynamic == null or std.mem.eql(u8, enable_dynamic.?, "true")) {
        dyn_registry.loadJupiter(rpc_url) catch |err| {
            std.log.warn("Failed to load Jupiter: {}", .{err});
        };
    }

    // 3. 传递给 HTTP 服务器
    const setup = http_server.ServerSetup{
        .name = "omniweb3-mcp",
        .register = tools.registerAllWithDynamic,
        .dynamic_registry = &dyn_registry,  // 传递动态注册表
    };

    try http_server.runHttpServer(allocator, init.io, .{ .setup = setup });
}
```

**tools/registry.zig** - 混合注册
```zig
pub fn registerAllWithDynamic(
    server: *mcp.Server,
    dynamic_registry_opaque: ?*anyopaque,
) !void {
    // 1. 先注册所有静态工具
    try registerAll(server);

    // 2. 然后注册动态工具（如果可用）
    if (dynamic_registry_opaque) |opaque_ptr| {
        const dyn_reg: *dynamic.DynamicToolRegistry = @ptrCast(@alignCast(opaque_ptr));

        std.log.info("Registering dynamic tools...", .{});
        try dyn_reg.registerAll(server);

        // 打印统计信息
        const total = toolCount() + dyn_reg.toolCount();
        std.log.info("=== Hybrid Tool Registry ===", .{});
        std.log.info("Static tools:  {}", .{toolCount()});
        std.log.info("Dynamic tools: {}", .{dyn_reg.toolCount()});
        std.log.info("Total tools:   {}", .{total});
    }
}
```

### 2. 动态工具加载

**tools/dynamic/registry.zig** - DynamicToolRegistry
```zig
pub const DynamicToolRegistry = struct {
    allocator: std.mem.Allocator,
    solana_provider: ?*SolanaProvider,
    tools: std.ArrayList(DynamicTool),

    pub fn loadJupiter(self: *DynamicToolRegistry, rpc_url: []const u8) !void {
        // 1. 初始化 Solana 提供者
        const provider = try SolanaProvider.init(self.allocator, rpc_url);
        self.solana_provider = provider;

        // 2. 解析 Jupiter IDL
        const jupiter_program_id = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";
        const meta = try provider.resolver.resolve(self.allocator, jupiter_program_id);

        // 3. 生成 MCP 工具
        const chain_prov = provider.asChainProvider();
        const generated_tools = try chain_prov.generateTools(self.allocator, &meta);

        // 4. 存储工具
        for (generated_tools, 0..) |tool, i| {
            try self.tools.append(self.allocator, .{
                .tool = tool,
                .meta = &meta,
                .function_name = meta.functions[i].name,
                .chain_type = .solana,
            });
        }
    }

    pub fn registerAll(self: *DynamicToolRegistry, server: *mcp.Server) !void {
        for (self.tools.items) |dyn_tool| {
            try server.addTool(dyn_tool.tool);
        }
    }
};
```

### 3. 动态工具处理

**tools/dynamic/handler.zig** - 处理动态工具调用
```zig
pub fn handleDynamicTool(
    allocator: std.mem.Allocator,
    registry: *const DynamicToolRegistry,
    tool_name: []const u8,
    args: ?std.json.Value,
) !mcp.tools.ToolResult {
    // 1. 查找工具元数据
    const dyn_tool = registry.findTool(tool_name) orelse return error.ToolNotFound;

    // 2. 提取参数
    const signer = mcp.tools.getString(args, "signer") orelse return error.MissingSigner;

    // 3. 构建函数调用
    const call = FunctionCall{
        .contract = dyn_tool.meta.address,
        .function = dyn_tool.function_name,
        .signer = signer,
        .args = args orelse std.json.Value{ .object = ... },
    };

    // 4. 通过提供者构建交易
    const provider = switch (dyn_tool.chain_type) {
        .solana => ...,
        else => return error.UnsupportedChain,
    };

    const tx = try provider.buildTransaction(allocator, call);

    // 5. 返回未签名交易
    return formatTransactionResult(allocator, tx);
}
```

---

## 环境变量配置

### 启用/禁用动态工具

```bash
# 启用动态工具（默认）
ENABLE_DYNAMIC_TOOLS=true zig build run

# 禁用动态工具（仅使用静态工具）
ENABLE_DYNAMIC_TOOLS=false zig build run
```

### 自定义 Solana RPC

```bash
# 使用自定义 RPC 节点
SOLANA_RPC_URL=https://your-rpc-url.com zig build run

# 使用 Helius
SOLANA_RPC_URL=https://mainnet.helius-rpc.com zig build run
```

### 完整配置示例

```bash
# .env 文件
HOST=0.0.0.0
PORT=8765
MCP_WORKERS=4
ENABLE_DYNAMIC_TOOLS=true
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com

# 启动服务器
zig build run
```

---

## 测试

### 快速测试脚本

```bash
# 运行混合架构测试
./scripts/test_hybrid_tools.sh
```

测试脚本会：
1. ✅ 检查服务器是否运行
2. ✅ 统计静态工具数量
3. ✅ 统计动态工具数量
4. ✅ 测试工具执行
5. ✅ 显示摘要信息

### 手动测试

```bash
# 1. 启动服务器
zig build run

# 2. 查看所有工具
curl http://localhost:8765/tools | jq '.tools[] | .name'

# 3. 查看静态工具（旧版 Jupiter REST API）
curl http://localhost:8765/tools | jq '.tools[] | select(.name | startswith("get_jupiter"))'

# 4. 查看动态工具（从 IDL 生成）
curl http://localhost:8765/tools | jq '.tools[] | select(.name | startswith("jupiter_"))'

# 5. 调用静态工具
curl -X POST http://localhost:8765/tool/get_jupiter_tokens \
  -H "Content-Type: application/json" \
  -d '{}'

# 6. 调用动态工具（返回未签名交易）
curl -X POST http://localhost:8765/tool/jupiter_route \
  -H "Content-Type: application/json" \
  -d '{
    "signer": "YourWalletAddressHere",
    "routePlan": [],
    "inAmount": "1000000",
    "quotedOutAmount": "990000",
    "slippageBps": 50,
    "platformFeeBps": 0
  }'
```

---

## 日志输出

启动服务器时，你会看到类似的输出：

```
info: Loading dynamic tools from Jupiter IDL...
info: Jupiter v6 IDL loaded: jupiter_aggregator, 6 instructions
info: Generated tool: jupiter_route for function: route
info: Generated tool: jupiter_sharedAccountsRoute for function: sharedAccountsRoute
info: Generated tool: jupiter_exactOutRoute for function: exactOutRoute
info: Generated tool: jupiter_setTokenLedger for function: setTokenLedger
info: Generated tool: jupiter_createOpenOrders for function: createOpenOrders
info: Generated tool: jupiter_createProgramOpenOrders for function: createProgramOpenOrders
info: Total dynamic tools loaded: 6
info: Registering static tools...
info: Static tool registration complete: 182 tools
info: Registering dynamic tools...
info: Registered: jupiter_route
info: Registered: jupiter_sharedAccountsRoute
info: Registered: jupiter_exactOutRoute
info: Registered: jupiter_setTokenLedger
info: Registered: jupiter_createOpenOrders
info: Registered: jupiter_createProgramOpenOrders
info: === Hybrid Tool Registry ===
info: Static tools:  182
info: Dynamic tools: 6
info: Total tools:   188
info: ============================
```

---

## 工具命名约定

为了避免冲突，我们使用以下命名约定：

### 静态工具
- **格式**：`<action>_<protocol>_<function>`
- **示例**：
  - `get_jupiter_quote` - 获取 Jupiter 报价（REST API）
  - `submit_jupiter_swap` - 提交 Jupiter 交换（REST API）
  - `get_solana_balance` - 获取 Solana 余额

### 动态工具
- **格式**：`<protocol>_<instruction>`
- **示例**：
  - `jupiter_route` - Jupiter 路由指令（链上）
  - `jupiter_exactOutRoute` - Jupiter 精确输出路由（链上）
  - `spl_transfer` - SPL Token 转账指令（链上）

**规则**：
- 静态工具通常以动词开头（`get_`, `submit_`, `fetch_`）
- 动态工具以协议名开头（`jupiter_`, `spl_`, `metaplex_`）
- 如有冲突，动态工具优先（更去中心化）

---

## 扩展到其他协议

混合架构的优势在于**可扩展性**。添加新协议非常简单：

### 添加新的动态工具（推荐）

如果协议有 IDL/ABI：

```zig
// 在 DynamicToolRegistry 中添加新方法
pub fn loadMetaplex(self: *DynamicToolRegistry, rpc_url: []const u8) !void {
    const metaplex_program_id = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s";
    const meta = try self.solana_provider.?.resolver.resolve(
        self.allocator,
        metaplex_program_id,
    );

    const chain_prov = self.solana_provider.?.asChainProvider();
    const tools = try chain_prov.generateTools(self.allocator, &meta);

    // 存储工具...
}

// 在 main.zig 中调用
try dyn_registry.loadMetaplex(rpc_url);
```

**零额外代码**！IDL 自动生成所有工具。

### 添加新的静态工具（如需要）

如果协议只有 REST API：

```zig
// 在 src/tools/solana/defi/<protocol>/ 创建新工具
pub fn get_protocol_data(
    allocator: std.mem.Allocator,
    args: ?std.json.Value,
) !mcp.tools.ToolResult {
    // 实现 REST API 调用...
}

// 在对应的 registry.zig 中注册
pub const tools = [_]mcp.tools.Tool{
    .{
        .name = "get_protocol_data",
        .description = "获取协议数据",
        .handler = get_protocol_data,
    },
};
```

---

## 性能考虑

### IDL 缓存

动态工具首次加载时需要：
1. 获取 IDL（本地缓存或 Solana FM API）
2. 解析 IDL
3. 生成工具元数据

**优化**：
- ✅ IDL 本地缓存（`idl_registry/` 目录）
- ✅ 工具生成只在启动时执行一次
- ⏱️ 首次加载约 100-500ms（取决于 IDL 大小）

### 工具查找

混合注册表使用：
- 静态工具：编译时数组（O(1) 查找）
- 动态工具：运行时 ArrayList（O(n) 查找）

对于 < 100 个动态工具，查找性能可忽略。

### 内存占用

- 每个静态工具：~200 bytes
- 每个动态工具：~500 bytes（包含元数据）
- 188 个工具总计：~100 KB

完全可接受。

---

## 故障排查

### 动态工具未加载

**症状**：日志显示 "Failed to load Jupiter dynamic tools"

**可能原因**：
1. 网络问题（无法访问 RPC 或 Solana FM API）
2. IDL 格式错误
3. 内存不足

**解决方案**：
```bash
# 1. 检查网络连接
curl https://api.mainnet-beta.solana.com -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'

# 2. 手动下载 IDL
curl https://api.solana.fm/v1/programs/JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4/idl \
  -o idl_registry/JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4.json

# 3. 禁用动态工具，只使用静态工具
ENABLE_DYNAMIC_TOOLS=false zig build run
```

### 工具名称冲突

**症状**：两个工具有相同的名称

**解决方案**：
1. 检查命名约定（静态工具用 `get_`/`submit_` 前缀）
2. 修改 IDL 工具生成器添加前缀
3. 重命名静态工具

### 交易构建失败

**症状**：调用动态工具时返回错误

**可能原因**：
1. 参数缺失或格式错误
2. Borsh 序列化失败
3. 账户推导失败

**解决方案**：
```bash
# 检查工具的输入模式
curl http://localhost:8765/tools | jq '.tools[] | select(.name == "jupiter_route") | .inputSchema'

# 确保提供所有必需参数
curl -X POST http://localhost:8765/tool/jupiter_route \
  -H "Content-Type: application/json" \
  -d '{
    "signer": "YourAddress",
    "routePlan": [],
    ...
  }' | jq
```

---

## 下一步计划

### 短期（1-2 周）

1. ✅ 集成混合架构（已完成）
2. ⏳ 添加更多 Solana 程序
   - Metaplex NFT
   - Raydium AMM
   - Orca Whirlpools
3. ⏳ 优化 IDL 缓存和热重载

### 中期（1 个月）

4. ⏳ Phase 2: EVM Provider
   - ABI 解析器
   - RLP 序列化
   - Uniswap、AAVE、USDC 支持
5. ⏳ 多链路由和统一资源 URI

### 长期（2-3 个月）

6. ⏳ Phase 3-5: 全面多链支持（Cosmos, Polkadot）
7. ⏳ Intent-based API
8. ⏳ 公开部署和监控

---

## 参考资料

- [Phase 1 实现文档](./PHASE_1_IMPLEMENTATION.md)
- [Jupiter 对比分析](./JUPITER_COMPARISON.md)
- [ChainProvider 接口设计](./CHAIN_PROVIDER.md)
- [下一步计划](./NEXT_STEPS.md)

---

**更新时间**: 2026年1月26日
**当前版本**: 0.1.0 (Hybrid Architecture)
**贡献者**: OmniWeb3 团队
