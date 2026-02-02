# Universal MCP Gateway - 架构规划

## 🎯 核心愿景

将任何 Solana Program 通过 IDL 自动映射为 MCP 接口，实现"零代码"集成新协议。

**当前状态（v1.0）**：手动为每个 DeFi 协议编写工具
- ✅ Jupiter: 19 个手写工具
- ✅ Meteora: 45 个手写工具（含 API）
- ✅ dFlow: 20+ 个手写工具
- ❌ 新协议需要重新编写代码

**目标状态（v2.0 - Universal Gateway）**：
- ✅ 给定任意 Program ID，自动发现 IDL
- ✅ IDL Instructions → MCP Tools（动态生成）
- ✅ IDL Accounts → MCP Resources（自动反序列化）
- ✅ 零延迟支持新协议

---

## 📐 架构设计

### 三层架构

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: MCP Interface (User-facing)                   │
│  - Claude/Cursor/V0 等 AI 客户端                         │
│  - 标准 MCP Protocol (JSON-RPC)                          │
└─────────────────────────────────────────────────────────┘
                         ▲
                         │ MCP Protocol
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 2: Universal Gateway (Core Engine)               │
│  ┌─────────────────┐  ┌──────────────────┐              │
│  │ IDL Resolver    │  │ Dynamic Tool Gen │              │
│  │ - Fetch IDL     │  │ - IDL → Tools    │              │
│  │ - Cache         │  │ - Schema Gen     │              │
│  │ - Validation    │  │ - Doc Extract    │              │
│  └─────────────────┘  └──────────────────┘              │
│                                                          │
│  ┌─────────────────┐  ┌──────────────────┐              │
│  │ Generic Executor│  │ Account Parser   │              │
│  │ - Tx Builder    │  │ - Borsh Deser    │              │
│  │ - PDA Derive    │  │ - JSON Format    │              │
│  │ - Signing       │  │ - Type Mapping   │              │
│  └─────────────────┘  └──────────────────┘              │
└─────────────────────────────────────────────────────────┘
                         ▲
                         │ RPC + Account Data
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Solana Blockchain                             │
│  - Programs (IDL 在链上或 Explorer)                      │
│  - Accounts (Borsh 序列化数据)                           │
│  - RPC Endpoints                                        │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 核心组件

### 1. IDL Resolver（IDL 解析器）

**职责**：给定 Program ID，获取并缓存 IDL

**实现策略**：
```zig
pub const IdlResolver = struct {
    allocator: std.mem.Allocator,
    rpc_client: RpcClient,
    cache: IdlCache,

    /// 优先级顺序获取 IDL
    pub fn resolve(self: *Self, program_id: PublicKey) !Idl {
        // 1. 本地缓存
        if (self.cache.get(program_id)) |idl| return idl;

        // 2. 链上 IDL Account (Anchor v0.29+)
        if (self.fetchOnchainIdl(program_id)) |idl| {
            self.cache.put(program_id, idl);
            return idl;
        }

        // 3. Solana FM / SolScan API
        if (self.fetchFromExplorer(program_id)) |idl| {
            self.cache.put(program_id, idl);
            return idl;
        }

        // 4. GitHub Registry (community-maintained)
        if (self.fetchFromRegistry(program_id)) |idl| {
            self.cache.put(program_id, idl);
            return idl;
        }

        return error.IdlNotFound;
    }
};
```

**数据源**：
1. **链上 IDL Account**（Anchor 0.29+）：
   - PDA: `seeds = ["anchor:idl", program_id]`
   - 优点：最权威
   - 缺点：不是所有程序都有

2. **Explorer API**：
   - Solana FM: `https://api.solana.fm/v1/programs/{program_id}/idl`
   - SolScan: `https://api.solscan.io/program/{program_id}/idl`

3. **本地 Registry**：
   - `idl_registry/` 目录存储常用协议 IDL
   - Jupiter, Meteora, Raydium 等

### 2. Dynamic Tool Generator（动态工具生成器）

**职责**：将 IDL Instructions 转换为 MCP Tools

**示例转换**：

```json
// IDL Input
{
  "name": "swap",
  "accounts": [
    { "name": "user", "isMut": true, "isSigner": true },
    { "name": "poolState", "isMut": true, "isSigner": false }
  ],
  "args": [
    { "name": "amountIn", "type": "u64" },
    { "name": "minimumAmountOut", "type": "u64" }
  ],
  "docs": ["Swap tokens using the pool"]
}
```

↓ **自动生成** ↓

```zig
// MCP Tool Definition
Tool {
    .name = "raydium_swap",  // prefix: program_name
    .description = "Swap tokens using the pool. Parameters: amountIn (u64), minimumAmountOut (u64)",
    .inputSchema = .{
        .type = "object",
        .properties = .{
            .amountIn = .{ .type = "integer", .description = "Amount to swap" },
            .minimumAmountOut = .{ .type = "integer", .description = "Slippage protection" },
            .user = .{ .type = "string", .description = "User public key (signer)" },
            .poolState = .{ .type = "string", .description = "Pool state account" }
        },
        .required = &[_][]const u8{ "amountIn", "minimumAmountOut", "user", "poolState" }
    },
    .handler = genericInstructionHandler  // 通用处理器
}
```

### 3. Generic Executor（通用执行器）

**职责**：根据 IDL 动态构建交易

```zig
pub fn genericInstructionHandler(
    allocator: std.mem.Allocator,
    program_id: PublicKey,
    instruction_name: []const u8,
    args: std.json.Value
) !ToolResult {
    // 1. 从 IDL 获取指令定义
    const idl = try idl_resolver.resolve(program_id);
    const ix_def = idl.getInstruction(instruction_name) orelse return error.InstructionNotFound;

    // 2. 动态序列化参数（Borsh）
    const ix_data = try serializeInstructionData(allocator, ix_def, args);

    // 3. 解析账户列表（支持 PDA 推导）
    const accounts = try resolveAccounts(allocator, ix_def, args);

    // 4. 构建交易
    const tx = try buildTransaction(allocator, .{
        .program_id = program_id,
        .accounts = accounts,
        .data = ix_data,
    });

    // 5. 返回未签名交易（或签名后发送）
    return ToolResult{ .transaction = tx };
}
```

**关键技术点**：
- **Borsh 序列化**：需要实现 Zig 的 Borsh 编码器
- **PDA 推导**：`PublicKey.findProgramAddress(seeds, program_id)`
- **账户推断**：某些账户可以从 IDL 的 `accounts` 字段推导

### 4. Account Parser（账户解析器）

**职责**：将链上 Borsh 数据反序列化为 JSON（MCP Resources）

```zig
pub fn parseAccount(
    allocator: std.mem.Allocator,
    program_id: PublicKey,
    account_type: []const u8,  // 如 "UserAccount"
    data: []const u8
) !std.json.Value {
    const idl = try idl_resolver.resolve(program_id);
    const type_def = idl.getAccountType(account_type) orelse return error.TypeNotFound;

    // 使用 IDL 中的类型定义反序列化
    return borsh.deserializeWithSchema(allocator, type_def, data);
}
```

**MCP Resource URI 格式**：
```
solana://<program_id>/account/<account_type>/<pubkey>
```

示例：
```
solana://JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4/UserAccount/8xKn...
```

AI 读取这个 Resource 时，Gateway 自动：
1. 从 RPC 获取账户数据
2. 根据 IDL 反序列化
3. 返回 JSON 文本

---

## 🗺️ 实施路线图

### Phase 1: 基础设施（2-3周）

**目标**：构建核心引擎，支持简单指令

#### 任务列表

1. **IDL 数据结构定义**
   - [ ] 定义 Zig 的 IDL 类型系统
   - [ ] 实现 JSON → Zig IDL 解析
   - [ ] 单元测试（使用 Jupiter IDL）

2. **IDL Resolver**
   - [ ] 实现本地文件加载
   - [ ] 实现链上 IDL 获取（Anchor IDL Account）
   - [ ] 实现 Explorer API 集成（Solana FM）
   - [ ] 添加 LRU 缓存

3. **Borsh 序列化库（Zig）**
   - [ ] 基础类型编码（u8, u16, u32, u64, i8, i16, i32, i64）
   - [ ] 字符串、Vec、Option 支持
   - [ ] 结构体序列化（基于 IDL schema）
   - [ ] 反序列化支持

4. **Dynamic Tool Generator**
   - [ ] IDL Instruction → MCP Tool 映射逻辑
   - [ ] JSON Schema 自动生成
   - [ ] 文档提取（IDL docs → Tool description）

#### 里程碑验证

使用 **Jupiter Swap** 作为测试案例：
- 输入：Jupiter Program ID + Swap IDL
- 输出：自动生成 `jupiter_swap` 工具
- 验证：AI 能调用该工具完成 swap

---

### Phase 2: 通用执行器（2周）

**目标**：能够动态构建和执行任意指令

#### 任务列表

1. **Generic Instruction Builder**
   - [ ] 参数序列化（args → Borsh）
   - [ ] 账户解析（处理 isMut, isSigner 标志）
   - [ ] PDA 推导集成

2. **Account Resolution**
   - [ ] 自动推导 PDA（基于 seeds 提示）
   - [ ] 用户账户管理（从参数或上下文获取）
   - [ ] Token Account 推导（ATA）

3. **Transaction Builder**
   - [ ] Solana Transaction v0 支持
   - [ ] 多指令批处理
   - [ ] Priority Fee 计算

4. **签名与发送**
   - [ ] 集成 Privy Wallet 签名
   - [ ] RPC 发送逻辑
   - [ ] 交易状态跟踪

#### 里程碑验证

实现：
```bash
# AI 提示词：
"使用 Raydium 的池子 ABC... 将 0.1 SOL 换成 USDC"

# Gateway 自动：
1. 发现 Raydium IDL
2. 生成 `raydium_swap` 工具
3. 构建交易并执行
```

---

### Phase 3: Account 数据解析（1-2周）

**目标**：实现 MCP Resources，AI 能读取链上数据

#### 任务列表

1. **Borsh 反序列化**
   - [ ] 基础类型解码
   - [ ] 嵌套结构解析
   - [ ] 数组和 Vec 支持

2. **MCP Resource Provider**
   - [ ] Resource URI 解析
   - [ ] 账户数据获取（RPC）
   - [ ] JSON 格式化输出

3. **类型推断优化**
   - [ ] Discriminator 匹配（Account 类型识别）
   - [ ] 枚举类型处理

#### 里程碑验证

AI 能够：
```
读取：solana://JUP6.../SwapState/XYZ...
返回：{ "token_a": "SOL", "token_b": "USDC", "fee": 0.25, ... }
```

---

### Phase 4: 高级特性（3-4周）

**目标**：生产级完善

#### 任务列表

1. **链上 Manifest Registry（可选）**
   - [ ] 设计 Manifest 数据结构
   - [ ] Solana Program 实现
   - [ ] AI 友好的 Prompt 增强

2. **智能 PDA 推导**
   - [ ] 常见 seeds 模式识别
   - [ ] 自动补全缺失的 seeds

3. **错误处理增强**
   - [ ] Program Error 映射到人类可读消息
   - [ ] 交易失败诊断

4. **性能优化**
   - [ ] IDL 缓存持久化（SQLite）
   - [ ] 并发请求处理
   - [ ] RPC 批量查询

5. **协议特化（Fallback）**
   - [ ] 保留现有手写工具作为优化版本
   - [ ] 通用引擎 + 特化工具混合模式

---

## 📂 新代码结构

```
src/
├── core/
│   ├── idl/
│   │   ├── types.zig          # IDL 数据结构
│   │   ├── parser.zig         # JSON → IDL 解析
│   │   ├── resolver.zig       # IDL 获取逻辑
│   │   └── cache.zig          # LRU 缓存
│   ├── borsh/
│   │   ├── serialize.zig      # Borsh 编码
│   │   ├── deserialize.zig    # Borsh 解码
│   │   └── schema.zig         # 基于 IDL 的 schema
│   ├── mcp_engine/
│   │   ├── tool_generator.zig # IDL → MCP Tool
│   │   ├── executor.zig       # 通用指令执行器
│   │   └── resource.zig       # MCP Resource 提供者
│   └── transaction/
│       ├── builder.zig        # 交易构建
│       └── pda.zig            # PDA 推导逻辑
├── tools/
│   ├── dynamic/               # 动态生成的工具
│   │   └── handler.zig        # 通用 handler
│   └── solana/
│       └── defi/              # 保留的特化工具
│           ├── jupiter/
│           └── meteora/
├── idl_registry/              # 本地 IDL 存储
│   ├── jupiter.json
│   ├── meteora_dlmm.json
│   └── raydium.json
└── main.zig
```

---

## 🎯 Phase 1 第一步：从哪里开始？

**建议优先级**：

### 1. 定义 IDL 类型系统（1-2天）
```zig
// src/core/idl/types.zig
pub const Idl = struct {
    version: []const u8,
    name: []const u8,
    instructions: []Instruction,
    accounts: []AccountDef,
    types: []TypeDef,
    // ...
};

pub const Instruction = struct {
    name: []const u8,
    accounts: []AccountMeta,
    args: []InstructionArg,
    docs: ?[][]const u8,
};
```

### 2. 实现 JSON → IDL 解析器（2-3天）
```zig
// src/core/idl/parser.zig
pub fn parseIdl(allocator: std.mem.Allocator, json: []const u8) !Idl {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{}
    );
    defer parsed.deinit();

    return idlFromJson(allocator, parsed.value);
}
```

### 3. 本地 IDL 加载（1天）
```zig
// src/core/idl/resolver.zig
pub fn loadLocal(
    allocator: std.mem.Allocator,
    program_name: []const u8
) !Idl {
    const path = try std.fmt.allocPrint(
        allocator,
        "idl_registry/{s}.json",
        .{program_name}
    );
    defer allocator.free(path);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    return parseIdl(allocator, content);
}
```

---

## 🧪 测试策略

### 单元测试
- 每个组件独立测试（IDL parser, Borsh encoder, etc.）
- 使用真实 IDL 文件（Jupiter, Meteora）

### 集成测试
- End-to-End: Program ID → 自动生成工具 → 执行交易
- 对比手写工具和动态工具的结果

### 性能基准
- IDL 解析速度
- Tool 生成延迟
- 交易构建时间

---

## 🚀 长期愿景

### v2.0: Universal Gateway
- ✅ 支持任意 Anchor Program
- ✅ 动态 Tool 生成
- ✅ 账户数据解析

### v3.0: Multi-Chain
- 扩展到 EVM（基于 ABI）
- 扩展到 Aptos/Sui（基于 Move IDL）

### v4.0: AI-Native Features
- 自动参数推断（基于上下文）
- 智能交易批处理
- Gas 优化建议

---

## 📌 关键决策点

### 1. Borsh 库选择
**选项**：
- A) 手写 Zig Borsh 库（控制力强，但工作量大）
- B) 调用 Rust Borsh（通过 C FFI，但引入依赖）
- C) 使用现有 Zig Borsh（如果有）

**建议**：选 A，Borsh 协议简单，Zig 实现不复杂

### 2. IDL 缓存策略
**选项**：
- A) 内存 LRU（简单但不持久）
- B) SQLite（持久化，查询快）
- C) 文件系统（简单但慢）

**建议**：Phase 1 用 A，Phase 4 升级到 B

### 3. 特化工具保留？
**问题**：手写的 Jupiter/Meteora 工具要保留吗？

**建议**：
- 保留作为"优化路径"
- 通用引擎优先，特化工具 Fallback
- 逐步迁移到通用引擎

---

## 📚 参考资源

- [Anchor IDL Spec](https://github.com/coral-xyz/anchor/blob/master/idl/src/lib.rs)
- [Borsh Specification](https://borsh.io/)
- [Solana Account Model](https://docs.solana.com/developing/programming-model/accounts)
- [MCP Protocol Spec](https://spec.modelcontextprotocol.io/)

---

## ✅ Next Action

**立即开始（本次会话）**：
1. 创建 Phase 1 的目录结构
2. 实现 IDL 类型定义
3. 下载 Jupiter IDL 作为测试文件

**你的决定**：要现在开始实现 Phase 1 吗？
