# Phase 1 实现：通用链提供者基础架构

## 概述

Phase 1 建立了从区块链程序元数据动态生成 MCP 工具的基础架构。此实现专注于 Solana/Anchor，但设计为可扩展到其他链。

**状态**: ✅ 核心实现完成 (Tasks #1-6)
**语言**: Zig 0.16-dev
**架构**: 提供者插件系统 + 运行时多态

## 实现总结

### 已完成组件

1. **ChainProvider 接口** (`src/core/chain_provider.zig`)
   - 所有区块链提供者的通用抽象
   - 基于 VTable 的运行时多态（Zig 无类/继承）
   - 支持：元数据解析、工具生成、交易构建、链上查询

2. **Borsh 序列化** (`src/core/borsh.zig`)
   - 完整实现 Borsh 规范的 Zig 版本
   - 支持：原始类型、字符串、数组、结构体、可选类型、枚举
   - 序列化和反序列化
   - Solana 用于交易编码

3. **SolanaProvider** (`src/providers/solana/provider.zig`)
   - Solana 的 ChainProvider 具体实现
   - IDL 缓存提升性能
   - 委托给专用模块

4. **IDL 解析器** (`src/providers/solana/idl_resolver.zig`)
   - 多源 IDL 解析策略：
     1. 本地注册表（最快）
     2. Solana FM API（可靠）
     3. 链上 IDL 账户（待实现）
   - 解析 Anchor IDL JSON 为 ContractMeta
   - 提取指令、类型、事件

5. **工具生成器** (`src/providers/solana/tool_generator.zig`)
   - 从合约元数据动态创建 MCP 工具
   - 从 Anchor 类型生成 JSON Schema
   - 每个指令/函数一个工具
   - 命名规则: `{program_name}_{function_name}`

6. **交易构建器** (`src/providers/solana/transaction_builder.zig`)
   - 从函数调用构建未签名交易
   - Anchor 判别器计算: SHA256("global:function_name")[0..8]
   - Borsh 参数序列化
   - 元数据保留用于签名

## 架构决策

### 1. VTable 模式实现多态

**问题**: Zig 没有继承或 trait 系统
**解决方案**: 函数指针结构体（VTable）+ 不透明上下文

```zig
pub const ChainProvider = struct {
    chain_type: ChainType,
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        getContractMeta: *const fn(ctx: *anyopaque, ...) anyerror!ContractMeta,
        generateTools: *const fn(ctx: *anyopaque, ...) anyerror![]mcp.tools.Tool,
        buildTransaction: *const fn(ctx: *anyopaque, ...) anyerror!Transaction,
        // ...
    };
};
```

**优势**:
- 类似虚函数的运行时分发
- 使用 `@ptrCast(@alignCast(ctx))` 类型安全向下转型
- 易于添加新提供者

### 2. 从零实现 Borsh

**为什么不用现有库？**
- 没有成熟的 Zig Borsh 库
- 完全控制序列化逻辑
- 理解 Solana 内部机制的教育价值

**实现方法**:
- 使用 `@typeInfo` 编译时反射
- 复杂类型的递归序列化
- 小端整数编码
- 长度前缀的字符串/数组

### 3. 多源 IDL 解析

**回退策略**:
1. **本地注册表** (`idl_registry/{program_id}.json`)
   - 即时访问，无需网络
   - 用户可填充已知程序

2. **Solana FM API** (`https://api.solana.fm/v1/programs/{program_id}/idl`)
   - 社区维护的 IDL 数据库
   - 覆盖大多数流行程序

3. **链上 IDL**（未来）
   - 从 Solana 区块链读取 IDL 账户
   - 最权威但需要 RPC

**理由**: 可靠性 > 速度。多个源确保可用性。

### 4. JSON Schema 生成

**类型映射**:
```
Anchor 类型         → JSON Schema
─────────────────────────────────────
u8, u16, u32, u64   → type: "integer"
i8, i16, i32, i64   → type: "integer"
bool                → type: "boolean"
string              → type: "string"
publicKey           → type: "string" (description: base58)
bytes               → type: "string" (description: base64/hex)
Option<T>           → anyOf: [T, null]
Vec<T>              → type: "array", items: T
struct              → type: "object", properties: {...}
```

**优势**:
- LLM 可理解参数模式
- 用户输入自动验证
- 一致的错误消息

## API 示例

### 使用 ChainProvider

```zig
// 初始化 Solana 提供者
const provider = try SolanaProvider.init(allocator, "https://api.mainnet-beta.solana.com");
defer provider.deinit();

// 转换为通用接口
const chain_prov = provider.asChainProvider();

// 获取合约元数据
const meta = try chain_prov.getContractMeta(allocator, "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4");

// 生成 MCP 工具
const tools = try chain_prov.generateTools(allocator, &meta);

// 构建交易
const call = FunctionCall{
    .contract = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
    .function = "swap",
    .signer = user_pubkey,
    .args = args_json,
    .options = .{ .value = 0, .gas_limit = null },
};
const tx = try chain_prov.buildTransaction(allocator, call);
```

### 判别器计算

```zig
const disc = try computeDiscriminator(allocator, "swap");
// 结果: F8C69E91E17587C8 (SHA256("global:swap")[0..8])
```

### Borsh 序列化

```zig
// 序列化结构体
const Point = struct { x: u32, y: u32 };
const point = Point{ .x = 10, .y = 20 };
const bytes = try borsh.serialize(allocator, point);
// bytes = [0A 00 00 00 14 00 00 00] (小端)

// 序列化字符串
var buffer: std.ArrayList(u8) = .empty;
try borsh.serializeString(allocator, &buffer, "hello");
// buffer = [05 00 00 00 68 65 6C 6C 6F] (长度前缀 + UTF-8)
```

## Zig 0.16 兼容性

### ArrayList API 变更

**旧版 (Zig 0.13)**:
```zig
var list = std.ArrayList(u8).init(allocator);
try list.append(1);
list.deinit();
```

**新版 (Zig 0.16)**:
```zig
var list: std.ArrayList(u8) = .empty;
try list.append(allocator, 1);  // 传递 allocator！
list.deinit(allocator);
```

**理由**: ArrayList 现在是"非托管"的 - 不在内部存储 allocator，减少结构体大小并提高可组合性。

### Type Info 变更

**旧版**: `@typeInfo(T).Int`
**新版**: `@typeInfo(T).int`

`builtin.Type` 中的所有联合字段现在都是小写。

## 测试

### 组件测试（已验证 ✅）

**test_phase1.zig** 验证:
- Anchor 判别器确定性
- Borsh 整数序列化 (u64)
- Borsh 字符串序列化（长度前缀）
- Borsh 布尔序列化

**结果**:
```
Test 1: Anchor 判别器计算
  initialize: AFAF6D1F0D989BED ✓
  swap: F8C69E91E17587C8 ✓
  transfer: A334C8E78C0345BA ✓
  mint: 3339E12FB69289A6 ✓
  burn: 746E1D386BDB2A5D ✓

Test 2: Borsh 序列化
  u64: 8 字节 ✓
  string: 17 字节 (4 字节长度 + 13 字符) ✓
  bool: 1 字节 ✓
```

### 集成测试（受阻）

**计划的测试**:
- Jupiter swap 工具生成
- SPL Token transfer/mint/burn 工具
- 端到端: IDL 获取 → 工具生成 → 交易构建

**阻塞原因**: 构建系统依赖项获取失败（GitHub releases 503 错误）。需要部署环境或手动依赖管理。

## 已知限制

1. **无链上 IDL 读取**
   - 当前依赖本地注册表或 Solana FM API
   - 未来：直接从区块链读取 IDL 账户

2. **无账户解析**
   - 交易构建器不自动派生 PDA
   - 用户必须提供所有账户地址
   - 未来：从 IDL 解析 `#[account(...)]` 约束

3. **无模拟/估算**
   - 无计算单元估算
   - 交易构建前无余额检查
   - 未来：集成 RPC `simulateTransaction`

4. **有限类型支持**
   - 自定义类型（带数据的枚举、嵌套结构）需要更多工作
   - 不支持 Anchor 的 `#[zero_copy]` 或 `#[account]` 类型
   - 未来：完整 Anchor 类型系统支持

5. **无事件解析**
   - 事件从 IDL 解析但未使用
   - 未来：事件订阅、日志解码

6. **无多指令交易**
   - 一个函数调用 = 一条指令
   - 未来：可组合指令构建器

## 下一步

### Phase 2: EVM 提供者
- 使用相同 ChainProvider 接口实现 `EVMProvider`
- ABI 解析（类似 IDL 解析）
- RLP 序列化（类似 Borsh）
- Solidity 合约工具生成

### Phase 3: MCP 服务器集成
- HTTP 服务器 + MCP 协议
- 工具路由到正确提供者
- 会话管理
- 错误处理和日志

### Phase 4: 钱包集成
- 交易签名（Phantom、MetaMask）
- 批准 UI
- 多签支持

## 文件结构

```
src/
├── core/
│   ├── chain_provider.zig      # 通用提供者接口
│   └── borsh.zig                # Borsh 序列化库
└── providers/
    └── solana/
        ├── provider.zig         # Solana 提供者实现
        ├── idl_resolver.zig     # IDL 获取和解析
        ├── tool_generator.zig   # MCP 工具生成
        └── transaction_builder.zig  # 交易构建
```

## 依赖项

- Zig 0.16-dev (nightly)
- std 库（内置 ArrayList、JSON、crypto）
- 外部（通过 build.zig.zon）:
  - mcp: MCP 协议类型
  - solana_client: RPC 客户端（未来）
  - solana_sdk: 密钥/签名类型（未来）

## 贡献

添加新链时：

1. 创建 `src/providers/{chain}/provider.zig`
2. 实现 ChainProvider.VTable 方法
3. 添加链特定元数据解析器
4. 如需要添加序列化库
5. 编写集成测试
6. 更新文档

## 参考资料

- [Anchor IDL 规范](https://www.anchor-lang.com/docs/idl)
- [Borsh 规范](https://borsh.io/)
- [MCP 协议](https://modelcontextprotocol.io/docs)
- [Solana FM IDL API](https://docs.solana.fm/api-reference/idl-api)

---

**实现日期**: 2026年1月
**状态**: 核心基础完成，集成测试待部署环境
