# Web3 MCP 网关 - 技术架构

> **通用网关：将任意区块链程序（通过 IDL/ABI）转换为 AI 可访问的 MCP 工具**

## 目录
- [核心愿景](#核心愿景)
- [架构概览](#架构概览)
- [Provider 插件系统](#provider-插件系统)
- [统一抽象](#统一抽象)
- [Solana Provider](#solana-provider)
- [EVM Provider](#evm-provider)
- [其他链 Provider](#其他链-provider)
- [实施阶段](#实施阶段)

---

## 核心愿景

### 问题

目前，为新的区块链程序添加支持需要：
1. 为每个函数手动创建工具
2. 硬编码数据结构
3. 自定义序列化逻辑
4. 程序特定的错误处理

当有数千个程序分布在几十条区块链上时，这种方式无法扩展。

### 解决方案

**在运行时自动将区块链程序元数据（IDL/ABI）转换为 MCP 工具。**

```
IDL/ABI → 动态 MCP 工具 → AI 可立即与任何程序交互
```

### 关键洞察

每个区块链生态系统都已有机器可读的合约接口格式：
- **Solana**: Anchor IDL (JSON)
- **EVM**: 合约 ABI (JSON)
- **Cosmos**: Protobuf 模式
- **Starknet**: Cairo ABI
- **ICP**: Candid IDL

我们只需要**解析这些格式并动态生成 MCP 工具**。

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                  AI 客户端 (Claude 等)                       │
└────────────────────────┬────────────────────────────────────┘
                         │ MCP 协议 (JSON-RPC)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    通用 MCP 网关                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Provider 注册中心 & 路由器                   │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │   Solana     │ │   EVM        │ │   Cosmos     │  ...  │
│  │   Provider   │ │   Provider   │ │   Provider   │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
   ┌─────────┐      ┌─────────┐      ┌─────────┐
   │ Solana  │      │   EVM   │      │ Cosmos  │
   │  链     │      │   链    │      │   链    │
   └─────────┘      └─────────┘      └─────────┘
```

### 三层设计

1. **MCP 接口层**（前端）
   - 标准 JSON-RPC 服务器
   - 工具/资源注册
   - 请求路由

2. **Provider 抽象层**（核心）
   - 统一的 `ChainProvider` 接口
   - 动态工具生成
   - 交易构建
   - 账户数据解析

3. **区块链层**（后端）
   - 链特定的 RPC 客户端
   - IDL/ABI 解析器
   - 交易签名器

---

## Provider 插件系统

### ChainProvider 接口

所有区块链 Provider 实现统一接口：

```zig
pub const ChainProvider = struct {
    const Self = @This();

    chain_type: ChainType,
    vtable: *const VTable,
    context: *anyopaque,  // Provider 特定状态

    pub const VTable = struct {
        // 获取合约元数据 (IDL/ABI)
        getContractMeta: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            address: []const u8,
        ) anyerror!ContractMeta,

        // 从元数据生成 MCP 工具
        generateTools: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            meta: ContractMeta,
        ) anyerror![]mcp.tools.Tool,

        // 构建未签名交易
        buildTransaction: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            call: FunctionCall,
        ) anyerror!Transaction,

        // 读取链上账户/状态数据
        readOnchainData: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            query: DataQuery,
        ) anyerror![]const u8,

        // 清理
        deinit: *const fn(ctx: *anyopaque) void,
    };

    // 公共 API（委托给 vtable）
    pub fn getContractMeta(self: *Self, allocator: std.mem.Allocator, address: []const u8) !ContractMeta {
        return self.vtable.getContractMeta(self.context, allocator, address);
    }

    pub fn generateTools(self: *Self, allocator: std.mem.Allocator, meta: ContractMeta) ![]mcp.tools.Tool {
        return self.vtable.generateTools(self.context, allocator, meta);
    }

    pub fn buildTransaction(self: *Self, allocator: std.mem.Allocator, call: FunctionCall) !Transaction {
        return self.vtable.buildTransaction(self.context, allocator, call);
    }

    pub fn readOnchainData(self: *Self, allocator: std.mem.Allocator, query: DataQuery) ![]const u8 {
        return self.vtable.readOnchainData(self.context, allocator, query);
    }

    pub fn deinit(self: *Self) void {
        self.vtable.deinit(self.context);
    }
};

pub const ChainType = enum {
    solana,
    evm,
    cosmos,
    ton,
    starknet,
    icp,
    sui,
    aptos,
    near,
    bitcoin,
    tron,
    // ... 可扩展
};
```

---

## 统一抽象

### ContractMeta
跨所有链的合约元数据通用表示：

```zig
pub const ContractMeta = struct {
    chain: ChainType,
    address: []const u8,
    name: ?[]const u8,
    version: ?[]const u8,
    functions: []Function,
    types: []TypeDef,
    events: []Event,
    raw: std.json.Value,  // 原始 IDL/ABI 供高级使用
};

pub const Function = struct {
    name: []const u8,
    description: ?[]const u8,
    inputs: []Parameter,
    outputs: []Parameter,
    mutability: Mutability,
};

pub const Mutability = enum {
    view,       // 只读（Solana: 无签名者，EVM: view/pure）
    mutable,    // 状态改变（需要交易）
    payable,    // 接受原生代币（EVM: payable，Solana: 转账）
};

pub const Parameter = struct {
    name: []const u8,
    type: Type,
    optional: bool = false,
};

pub const Type = union(enum) {
    primitive: PrimitiveType,
    array: *Type,
    struct_type: []Field,
    option: *Type,
    custom: []const u8,  // 引用 TypeDef
};

pub const PrimitiveType = enum {
    u8, u16, u32, u64, u128, u256,
    i8, i16, i32, i64, i128,
    bool,
    string,
    bytes,
    pubkey,    // Solana 公钥
    address,   // EVM 地址
};
```

### Transaction
链无关的交易表示：

```zig
pub const Transaction = struct {
    chain: ChainType,
    from: ?[]const u8,
    to: []const u8,
    data: []const u8,        // 序列化的指令/调用数据
    value: ?u128,            // 原生代币数量（lamports/wei）
    gas_limit: ?u64,
    gas_price: ?u64,
    nonce: ?u64,
    metadata: std.json.Value,  // 链特定字段
};

pub const FunctionCall = struct {
    contract: []const u8,
    function: []const u8,
    args: std.json.Value,
    signer: ?[]const u8,
    options: CallOptions,
};

pub const CallOptions = struct {
    value: ?u128 = null,
    gas: ?u64 = null,
    simulate: bool = false,
};
```

---

## Solana Provider

### IDL 解析策略

```zig
pub const SolanaProvider = struct {
    rpc_client: SolanaRpcClient,
    idl_cache: std.StringHashMap(ContractMeta),

    pub fn getContractMeta(
        self: *SolanaProvider,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        // 先检查缓存
        if (self.idl_cache.get(program_id)) |cached| {
            return cached;
        }

        // 策略 1: 从链上 IDL 账户获取
        if (self.fetchOnChainIdl(allocator, program_id)) |idl| {
            const meta = try self.parseIdl(allocator, idl, program_id);
            try self.idl_cache.put(program_id, meta);
            return meta;
        } else |_| {}

        // 策略 2: 查询 Solana FM API
        if (self.fetchFromSolanaFM(allocator, program_id)) |idl| {
            const meta = try self.parseIdl(allocator, idl, program_id);
            try self.idl_cache.put(program_id, meta);
            return meta;
        } else |_| {}

        // 策略 3: 检查本地注册表
        if (self.loadFromRegistry(allocator, program_id)) |idl| {
            const meta = try self.parseIdl(allocator, idl, program_id);
            try self.idl_cache.put(program_id, meta);
            return meta;
        } else |_| {}

        return error.IdlNotFound;
    }
};
```

### 动态工具生成

```zig
pub fn generateTools(
    self: *SolanaProvider,
    allocator: std.mem.Allocator,
    meta: ContractMeta,
) ![]mcp.tools.Tool {
    var tools = std.ArrayList(mcp.tools.Tool).init(allocator);

    for (meta.functions) |func| {
        // 生成工具名称: programName_functionName
        const tool_name = try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ meta.name orelse "program", func.name },
        );

        // 从函数输入生成输入模式
        const input_schema = try self.generateInputSchema(allocator, func.inputs);

        // 创建捕获元数据的工具处理器
        const handler = try self.createHandler(allocator, meta.address, func);

        try tools.append(.{
            .name = tool_name,
            .description = func.description orelse try std.fmt.allocPrint(
                allocator,
                "在 {s} 上调用 {s} 指令",
                .{ meta.address, func.name },
            ),
            .inputSchema = input_schema,
            .handler = handler,
        });
    }

    return tools.toOwnedSlice();
}
```

---

## EVM Provider

### ABI 解析策略

```zig
pub const EvmProvider = struct {
    rpc_client: EvmRpcClient,
    etherscan_api_key: ?[]const u8,
    abi_cache: std.StringHashMap(ContractMeta),

    pub fn getContractMeta(
        self: *EvmProvider,
        allocator: std.mem.Allocator,
        address: []const u8,
    ) !ContractMeta {
        // 检查缓存
        if (self.abi_cache.get(address)) |cached| {
            return cached;
        }

        // 策略 1: 检查是否为代理，获取实现
        const impl_address = try self.resolveProxy(allocator, address);

        // 策略 2: 从 Etherscan 获取 ABI
        if (self.fetchFromEtherscan(allocator, impl_address)) |abi| {
            const meta = try self.parseAbi(allocator, abi, impl_address);
            try self.abi_cache.put(address, meta);
            return meta;
        } else |_| {}

        // 策略 3: 检查本地注册表
        if (self.loadFromRegistry(allocator, impl_address)) |abi| {
            const meta = try self.parseAbi(allocator, abi, impl_address);
            try self.abi_cache.put(address, meta);
            return meta;
        } else |_| {}

        return error.AbiNotFound;
    }

    fn resolveProxy(
        self: *EvmProvider,
        allocator: std.mem.Allocator,
        address: []const u8,
    ) ![]const u8 {
        // ERC-1967: 实现槽位 = keccak256("eip1967.proxy.implementation") - 1
        const slot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

        const impl_bytes = try self.rpc_client.getStorageAt(address, slot);

        // 如果槽位为零，不是代理
        const is_zero = for (impl_bytes) |b| {
            if (b != 0) break false;
        } else true;

        if (is_zero) {
            return address;  // 不是代理
        }

        // 从最后 20 字节提取地址
        return try std.fmt.allocPrint(allocator, "0x{s}", .{
            std.fmt.fmtSliceHexLower(impl_bytes[12..32]),
        });
    }
};
```

---

## 其他链 Provider

### Cosmos Provider
- 通过 gRPC 反射获取 Protobuf 模式
- CosmWasm: 合约状态中的 JSON 模式
- 查询: `/cosmos.tx.v1beta1.Service/GetTx`

### Starknet Provider
- 从合约类获取 Cairo ABI
- Felt252 序列化
- 合约类哈希解析

### TON Provider
- TL-B 模式解析
- Cell 序列化
- Actor 模型消息构造

### ICP Provider
- 从 canister 元数据获取 Candid IDL
- CBOR 编码
- Update/Query 调用区分

### Sui/Aptos Provider
- Move 模块 ABI
- BCS 序列化
- 面向对象的交易构建

---

## 实施阶段

### 阶段 1: 基础（4-6 周）
**目标**: 用 Solana 证明概念

- [ ] 实现 `ChainProvider` 接口
- [ ] 创建 `SolanaProvider` 并支持 IDL 解析
- [ ] 构建动态工具生成器
- [ ] 实现 Borsh 序列化
- [ ] 用 3 个程序测试（Jupiter、Metaplex、SPL Token）

**交付成果**: AI 可以与任何 Anchor 程序交互（给定其 IDL）

### 阶段 2: EVM 支持（3-4 周）
**目标**: 扩展到以太坊生态

- [ ] 创建 `EvmProvider` 并支持 ABI 解析
- [ ] 实现代理检测（ERC-1967）
- [ ] 添加 Etherscan API 集成
- [ ] 构建 ABI 编码器/解码器
- [ ] 用 Uniswap V3、USDC、Aave 测试

**交付成果**: 单个 MCP 服务器同时支持 Solana 和 EVM

### 阶段 3: 多链（4-5 周）
**目标**: 覆盖 80% 的 Web3 生态

- [ ] 添加 Cosmos Provider（Protobuf + gRPC）
- [ ] 添加 Starknet Provider（Cairo ABI）
- [ ] 添加 TON Provider（TL-B）
- [ ] 实现 Provider 注册表和路由
- [ ] 添加地址自动链检测

**交付成果**: 支持 5+ 链类型的通用网关

### 阶段 4: 高级功能（3-4 周）
**目标**: 生产就绪能力

- [ ] 基于意图的 API（高级目标 → 多步执行）
- [ ] 执行前交易模拟
- [ ] Gas 优化策略
- [ ] 多签支持
- [ ] Session key 管理

**交付成果**: 企业级网关与高级功能

### 阶段 5: 生态集成（2-3 周）
**目标**: 实际部署

- [ ] NEAR 集成（统一账户的链签名）
- [ ] 托管 API 服务（api.web3mcp.com）
- [ ] 自定义 Provider 的 SDK
- [ ] 文档和教程
- [ ] 性能优化（缓存、批处理）

**交付成果**: 准备大规模采用的公共服务

---

## 资源 URI 格式

区块链数据的通用寻址方案：

```
<chain>://<contract>/<resource_type>/<identifier>[?params]
```

### 示例

```
solana://TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA/account/mint/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v

evm://0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48/balance/0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb

cosmos://cosmoshub-4/bank/balance/cosmos1...?denom=uatom

starknet://0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7/storage/0x123

ton://EQD...ABC/get_method/get_wallet_data

near://token.near/ft_balance_of/alice.near
```

---

## 性能考虑

### 缓存策略
1. **IDL/ABI 缓存**: 内存 + 磁盘持久化（24h TTL）
2. **工具缓存**: 为流行合约预生成工具
3. **RPC 缓存**: 缓存不可变数据（区块历史、交易收据）

### 优化技术
1. **延迟加载**: 首次访问时才获取 IDL
2. **批处理**: 将多个 RPC 调用组合成单个请求
3. **并行获取**: 并发 Provider 操作
4. **代码生成**: 将流行合约预编译为原生工具

### 可扩展性目标
- **延迟**: < 200ms（缓存），< 2s（未缓存）
- **吞吐量**: 100+ 并发请求
- **内存**: 每个 Provider 实例 < 50MB
- **合约**: 每个 Provider 支持 1000+ 合约

---

## 安全模型

### 密钥管理
- 私钥永不离开 MCP 服务器
- 支持硬件钱包（Ledger、Trezor）
- 限定范围操作的 Session key
- 多签钱包集成

### 交易安全
- 执行前强制模拟
- Gas 价格限制和滑点保护
- 合约白名单/黑名单
- 高价值交易需用户确认

### API 安全
- 每个 API key 的速率限制
- 合约验证检查
- 沙盒执行环境
- 所有操作的审计日志

---

## 测试策略

### 单元测试
- 每个 Provider 的 IDL/ABI 解析
- 类型转换和序列化
- 交易构建逻辑

### 集成测试
- 端到端工具生成 → 执行
- 多链交易流程
- 错误处理和恢复

### 主网测试
- 测试网上的真实交易
- 流行合约交互
- 性能基准测试

---

## 结论

此架构将 web3mcp 从**静态工具集合**转变为**动态通用网关**，无需手动集成工作即可与任何区块链程序交互。

**主要优势**:
1. **零日支持**: 新程序可立即被 AI 访问
2. **开发者效率**: 无需手动创建工具
3. **用户体验**: 自然语言 → 任意区块链操作
4. **生态影响**: 消除 Web3 x AI 集成的摩擦

**下一步**:
- 参见 [USE_CASES.md](./USE_CASES.md) 了解应用场景
- 参见 [BUSINESS_MODEL.md](./BUSINESS_MODEL.md) 了解变现策略
- 参见 [NEAR_INTEGRATION.md](./NEAR_INTEGRATION.md) 了解链抽象方法
