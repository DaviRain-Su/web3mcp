# Multi-Chain Universal MCP Gateway - 架构设计

## 🌍 终极愿景

**One Protocol to Bind Them All** - 一个 MCP Server 统一所有区块链的智能合约交互

```
AI (Claude/Cursor/V0)
        ↓
   MCP Protocol
        ↓
Universal Gateway (Zig Core)
        ↓
   ┌────┴────┐
   ↓         ↓
Solana    EVM Chains
Provider  Provider
   ↓         ↓
 IDL       ABI
```

---

## 🏗️ 核心架构：Provider 插件系统

### 统一抽象层

```zig
/// 区块链 Provider 统一接口
pub const ChainProvider = struct {
    const Self = @This();

    /// Provider 类型
    chain_type: ChainType,

    /// 虚函数表（类似 C++ vtable）
    vtable: *const VTable,

    pub const VTable = struct {
        /// 获取合约元数据（IDL/ABI）
        getContractMeta: *const fn (
            self: *Self,
            allocator: std.mem.Allocator,
            contract_address: []const u8,
        ) anyerror!ContractMeta,

        /// 动态生成 MCP Tools
        generateTools: *const fn (
            self: *Self,
            allocator: std.mem.Allocator,
            meta: *const ContractMeta,
        ) anyerror![]mcp.tools.Tool,

        /// 构建交易
        buildTransaction: *const fn (
            self: *Self,
            allocator: std.mem.Allocator,
            request: *const TransactionRequest,
        ) anyerror!Transaction,

        /// 读取链上数据（Resources）
        readOnchainData: *const fn (
            self: *Self,
            allocator: std.mem.Allocator,
            uri: []const u8,
        ) anyerror![]const u8,
    };
};

pub const ChainType = enum {
    Solana,
    EVM,
    // 未来扩展：
    // Aptos,
    // Sui,
};
```

### 通用数据结构

```zig
/// 合约元数据（统一表示 IDL 或 ABI）
pub const ContractMeta = struct {
    chain: ChainType,
    address: []const u8,
    name: ?[]const u8,

    /// 函数/指令列表
    functions: []Function,

    /// 账户/事件定义
    types: []TypeDef,

    /// 原始元数据（JSON）
    raw: std.json.Value,
};

/// 统一的函数定义（跨链抽象）
pub const Function = struct {
    name: []const u8,
    kind: FunctionKind,
    inputs: []Parameter,
    outputs: []Parameter,
    docs: ?[]const u8,

    /// 链特定的元数据
    chain_specific: union(ChainType) {
        solana: struct {
            accounts: []AccountMeta,
            discriminator: [8]u8,
        },
        evm: struct {
            selector: [4]u8,
            stateMutability: StateMutability,
        },
    },
};

pub const FunctionKind = enum {
    Read,      // Solana: Account getter, EVM: view/pure
    Write,     // Solana: Instruction, EVM: payable/nonpayable
    Event,     // EVM events, Solana: 暂无标准
};

pub const StateMutability = enum {
    pure,
    view,
    nonpayable,
    payable,
};
```

---

## 📐 Solana Provider 设计

### 实现细节

```zig
pub const SolanaProvider = struct {
    allocator: std.mem.Allocator,
    rpc_client: RpcClient,
    idl_cache: IdlCache,

    pub fn init(allocator: std.mem.Allocator, rpc_url: []const u8) !SolanaProvider {
        return .{
            .allocator = allocator,
            .rpc_client = try RpcClient.init(allocator, rpc_url),
            .idl_cache = IdlCache.init(allocator),
        };
    }

    /// 实现 ChainProvider.getContractMeta
    pub fn getContractMeta(
        self: *SolanaProvider,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        // 1. 尝试从缓存获取
        if (self.idl_cache.get(program_id)) |idl| {
            return idlToContractMeta(allocator, idl);
        }

        // 2. 链上 IDL Account (Anchor 0.29+)
        const pubkey = try PublicKey.fromBase58(program_id);
        if (try self.fetchOnchainIdl(pubkey)) |idl| {
            try self.idl_cache.put(program_id, idl);
            return idlToContractMeta(allocator, idl);
        }

        // 3. Solana FM API
        const url = try std.fmt.allocPrint(
            allocator,
            "https://api.solana.fm/v1/programs/{s}/idl",
            .{program_id}
        );
        defer allocator.free(url);

        const idl_json = try secure_http.secureGet(allocator, url, false, false);
        defer allocator.free(idl_json);

        const idl = try parseIdl(allocator, idl_json);
        try self.idl_cache.put(program_id, idl);

        return idlToContractMeta(allocator, idl);
    }

    /// IDL → ContractMeta 转换
    fn idlToContractMeta(allocator: std.mem.Allocator, idl: Idl) !ContractMeta {
        var functions = std.ArrayList(Function).init(allocator);

        // 将 IDL Instructions 转换为 Function
        for (idl.instructions) |ix| {
            const func = Function{
                .name = ix.name,
                .kind = .Write,  // Solana Instructions 都是写操作
                .inputs = try convertIdlArgs(allocator, ix.args),
                .outputs = &.{},
                .docs = ix.docs,
                .chain_specific = .{
                    .solana = .{
                        .accounts = ix.accounts,
                        .discriminator = try computeDiscriminator(ix.name),
                    },
                },
            };
            try functions.append(func);
        }

        // TODO: 将 IDL Accounts 转换为 Read Functions

        return ContractMeta{
            .chain = .Solana,
            .address = idl.address orelse "",
            .name = idl.name,
            .functions = try functions.toOwnedSlice(),
            .types = try convertIdlTypes(allocator, idl.types),
            .raw = idl.raw,
        };
    }
};
```

### Resource URI 格式

```
solana://<program_id>/<account_type>/<pubkey>
solana://JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4/SwapState/8xKn...
```

---

## 📐 EVM Provider 设计

### 实现细节

```zig
pub const EvmProvider = struct {
    allocator: std.mem.Allocator,
    rpc_client: EvmRpcClient,
    abi_cache: AbiCache,
    chain_id: u64,

    /// 支持的 EVM 链
    pub const ChainId = enum(u64) {
        ethereum_mainnet = 1,
        bsc_mainnet = 56,
        polygon_mainnet = 137,
        avalanche_mainnet = 43114,
        arbitrum_mainnet = 42161,
        optimism_mainnet = 10,
        base_mainnet = 8453,
        // ... 可扩展
    };

    pub fn init(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        chain_id: u64,
    ) !EvmProvider {
        return .{
            .allocator = allocator,
            .rpc_client = try EvmRpcClient.init(allocator, rpc_url),
            .abi_cache = AbiCache.init(allocator),
            .chain_id = chain_id,
        };
    }

    /// 实现 ChainProvider.getContractMeta
    pub fn getContractMeta(
        self: *EvmProvider,
        allocator: std.mem.Allocator,
        contract_address: []const u8,
    ) !ContractMeta {
        // 1. 检查缓存
        if (self.abi_cache.get(contract_address)) |abi| {
            return abiToContractMeta(allocator, contract_address, abi);
        }

        // 2. 检测代理合约（重要！）
        const impl_address = try self.detectProxy(contract_address);
        const target_address = impl_address orelse contract_address;

        // 3. 从 Etherscan/Basescan 等获取 ABI
        const abi_json = try self.fetchAbiFromExplorer(target_address);
        defer allocator.free(abi_json);

        const abi = try parseAbi(allocator, abi_json);
        try self.abi_cache.put(contract_address, abi);

        return abiToContractMeta(allocator, contract_address, abi);
    }

    /// 代理合约检测（EVM 特有难点）
    fn detectProxy(self: *EvmProvider, address: []const u8) !?[]const u8 {
        // ERC-1967: 实现地址存储在特定 slot
        // bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
        const IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

        const impl_bytes = try self.rpc_client.eth_getStorageAt(
            address,
            IMPLEMENTATION_SLOT,
            "latest",
        );

        // 如果 slot 非零，说明是代理
        if (!isZeroBytes(impl_bytes)) {
            // 提取地址（最后 20 字节）
            return bytesToAddress(impl_bytes);
        }

        // 还可以检测其他代理模式：
        // - ERC-1822: Universal Upgradeable Proxy
        // - Beacon Proxy
        // - Transparent Proxy

        return null;
    }

    /// 从区块链浏览器获取 ABI
    fn fetchAbiFromExplorer(self: *EvmProvider, address: []const u8) ![]const u8 {
        const explorer_url = switch (self.chain_id) {
            1 => "https://api.etherscan.io/api",
            56 => "https://api.bscscan.com/api",
            137 => "https://api.polygonscan.com/api",
            8453 => "https://api.basescan.org/api",
            // ... 其他链
            else => return error.UnsupportedChain,
        };

        // Etherscan API: ?module=contract&action=getabi&address=...
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}?module=contract&action=getabi&address={s}&apikey={s}",
            .{ explorer_url, address, getApiKey(self.chain_id) },
        );
        defer self.allocator.free(url);

        const response = try secure_http.secureGet(self.allocator, url, false, false);
        defer self.allocator.free(response);

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response,
            .{},
        );
        defer parsed.deinit();

        const result_obj = parsed.value.object.get("result") orelse return error.NoAbi;
        if (result_obj != .string) return error.InvalidResponse;

        return try self.allocator.dupe(u8, result_obj.string);
    }

    /// ABI → ContractMeta 转换
    fn abiToContractMeta(
        allocator: std.mem.Allocator,
        address: []const u8,
        abi: Abi,
    ) !ContractMeta {
        var functions = std.ArrayList(Function).init(allocator);

        for (abi.items) |item| {
            switch (item.type) {
                .function => {
                    const kind: FunctionKind = switch (item.stateMutability) {
                        .pure, .view => .Read,
                        .nonpayable, .payable => .Write,
                    };

                    const func = Function{
                        .name = item.name,
                        .kind = kind,
                        .inputs = try convertAbiInputs(allocator, item.inputs),
                        .outputs = try convertAbiOutputs(allocator, item.outputs),
                        .docs = null,  // ABI 通常没有文档
                        .chain_specific = .{
                            .evm = .{
                                .selector = try computeSelector(item.name, item.inputs),
                                .stateMutability = item.stateMutability,
                            },
                        },
                    };
                    try functions.append(func);
                },
                .event => {
                    // TODO: 将 Events 转换为只读 Resources
                },
                else => {}, // constructor, fallback, receive
            }
        }

        return ContractMeta{
            .chain = .EVM,
            .address = address,
            .name = null,  // ABI 没有合约名
            .functions = try functions.toOwnedSlice(),
            .types = &.{},
            .raw = abi.raw,
        };
    }
};
```

### Resource URI 格式

```
evm://<chain_id>/<contract_address>/<function_name>?args=[...]
evm://1/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48/balanceOf?args=["0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"]
```

**只读数据示例**：
```
AI: "读取 evm://1/0xA0b.../balanceOf?args=[0x742...]"
Gateway: 调用 eth_call，返回 "1000000000" (USDC balance)
```

---

## 🔧 核心引擎：通用工具生成

### 动态 MCP Tool 生成器

```zig
pub const ToolGenerator = struct {
    pub fn generate(
        allocator: std.mem.Allocator,
        meta: *const ContractMeta,
    ) ![]mcp.tools.Tool {
        var tools = std.ArrayList(mcp.tools.Tool).init(allocator);

        for (meta.functions) |func| {
            // 只为 Write 操作生成 Tool（Read 操作通过 Resource）
            if (func.kind != .Write) continue;

            const tool = mcp.tools.Tool{
                .name = try generateToolName(allocator, meta, func),
                .description = try generateDescription(allocator, func),
                .inputSchema = try generateInputSchema(allocator, func),
                .handler = genericHandler,  // 通用处理器
            };

            try tools.append(tool);
        }

        return tools.toOwnedSlice();
    }

    /// 生成工具名：<chain>_<contract>_<function>
    fn generateToolName(
        allocator: std.mem.Allocator,
        meta: *const ContractMeta,
        func: Function,
    ) ![]const u8 {
        const chain_prefix = switch (meta.chain) {
            .Solana => "sol",
            .EVM => "evm",
        };

        const contract_name = meta.name orelse "contract";

        return std.fmt.allocPrint(
            allocator,
            "{s}_{s}_{s}",
            .{ chain_prefix, contract_name, func.name },
        );
    }

    /// 生成 JSON Schema
    fn generateInputSchema(
        allocator: std.mem.Allocator,
        func: Function,
    ) !mcp.tools.InputSchema {
        var properties = std.StringHashMap(mcp.tools.Property).init(allocator);
        var required = std.ArrayList([]const u8).init(allocator);

        for (func.inputs) |param| {
            const prop = try paramToProperty(allocator, param);
            try properties.put(param.name, prop);
            try required.append(param.name);
        }

        // 链特定的额外参数
        switch (func.chain_specific) {
            .solana => |sol| {
                // Solana 需要用户提供账户
                for (sol.accounts) |acc| {
                    if (acc.isSigner or acc.isMut) {
                        try properties.put(acc.name, .{
                            .type = "string",
                            .description = try std.fmt.allocPrint(
                                allocator,
                                "Account: {s} (signer: {}, mutable: {})",
                                .{ acc.name, acc.isSigner, acc.isMut },
                            ),
                        });
                        try required.append(acc.name);
                    }
                }
            },
            .evm => |evm| {
                // EVM 需要 from 地址
                try properties.put("from", .{
                    .type = "string",
                    .description = "Sender address",
                });
                try required.append("from");

                // payable 函数需要 value
                if (evm.stateMutability == .payable) {
                    try properties.put("value", .{
                        .type = "string",
                        .description = "ETH amount to send (wei)",
                    });
                }
            },
        }

        return .{
            .type = "object",
            .properties = properties,
            .required = try required.toOwnedSlice(),
        };
    }
};
```

---

## 🚀 统一交易构建

### 通用 Transaction 结构

```zig
pub const Transaction = union(ChainType) {
    solana: struct {
        recent_blockhash: [32]u8,
        instructions: []TransactionInstruction,
        signers: []Keypair,
        serialized: []const u8,
    },

    evm: struct {
        to: [20]u8,
        value: u256,
        data: []const u8,  // calldata
        gas_limit: u64,
        max_fee_per_gas: u256,
        max_priority_fee: u256,
        chain_id: u64,
        nonce: u64,
    },
};

pub const TransactionRequest = struct {
    chain: ChainType,
    contract_address: []const u8,
    function_name: []const u8,
    args: std.json.Value,

    /// 链特定配置
    config: union(ChainType) {
        solana: struct {
            compute_units: ?u32,
            priority_fee: ?u64,
        },
        evm: struct {
            gas_limit: ?u64,
            max_fee: ?u256,
        },
    },
};
```

### 通用处理器

```zig
pub fn genericHandler(
    allocator: std.mem.Allocator,
    args: ?std.json.Value,
) mcp.tools.ToolError!mcp.tools.ToolResult {
    // 1. 解析请求
    const chain = mcp.tools.getString(args, "chain") orelse return error.MissingChain;
    const contract = mcp.tools.getString(args, "contract") orelse return error.MissingContract;
    const function = mcp.tools.getString(args, "function") orelse return error.MissingFunction;

    // 2. 获取对应的 Provider
    const provider = try getProvider(allocator, chain);

    // 3. 获取合约元数据
    const meta = try provider.getContractMeta(allocator, contract);

    // 4. 构建交易
    const request = TransactionRequest{
        .chain = meta.chain,
        .contract_address = contract,
        .function_name = function,
        .args = args.?,
        // ...
    };

    const tx = try provider.buildTransaction(allocator, &request);

    // 5. 返回未签名交易（由前端钱包签名）
    const result = try serializeTransaction(allocator, tx);
    return mcp.tools.textResult(allocator, result);
}
```

---

## 📊 对比：Solana vs EVM

| 维度 | Solana | EVM | 实现难度 |
|------|--------|-----|---------|
| **元数据获取** | IDL（链上或 API） | ABI（Etherscan API） | EVM 稍难（需 API Key） |
| **代理检测** | 几乎不存在 | 非常普遍（ERC-1967） | EVM 难 ⚠️ |
| **数据读取** | Account 反序列化 | `eth_call` 调用 | EVM 更简单 ✅ |
| **交易构建** | 多 Instruction 批处理 | 单 Calldata | 相似 |
| **类型系统** | Rust 类型（简单） | Solidity（uint256 大数） | EVM 稍难 |
| **多链支持** | 单链 | 数十条 EVM 兼容链 | EVM 优势 ✅ |

---

## 🗺️ 实施路线图（更新版）

### Phase 1: Solana Provider (2-3周)
- [x] IDL 类型定义
- [ ] IDL 解析器
- [ ] Borsh 序列化库
- [ ] 动态 Tool 生成
- [ ] 通用 Instruction 构建器

### Phase 2: EVM Provider (2-3周)
- [ ] ABI 类型定义
- [ ] ABI 解析器
- [ ] Etherscan API 集成
- [ ] **代理合约检测**（关键！）
- [ ] ABI 编码器（calldata 生成）
- [ ] 动态 Tool 生成（复用 Solana 逻辑）

### Phase 3: 统一抽象层 (1-2周)
- [ ] ChainProvider 接口定义
- [ ] 通用 ContractMeta 结构
- [ ] 统一 Transaction 类型
- [ ] Provider 注册与管理

### Phase 4: 多链支持 (1-2周)
- [ ] 配置系统（多 RPC、多 API Key）
- [ ] 链 ID 路由
- [ ] 跨链 Resource URI
- [ ] 统一错误处理

### Phase 5: 高级特性 (2-3周)
- [ ] Resource 缓存（Redis/SQLite）
- [ ] Gas 估算与优化
- [ ] 交易状态跟踪
- [ ] Event 订阅（WebSocket）

---

## 📂 新目录结构

```
src/
├── core/
│   ├── provider/              # Provider 抽象
│   │   ├── interface.zig      # ChainProvider 接口
│   │   ├── registry.zig       # Provider 注册管理
│   │   └── router.zig         # 链路由逻辑
│   ├── solana/
│   │   ├── provider.zig       # Solana Provider 实现
│   │   ├── idl/
│   │   │   ├── types.zig
│   │   │   ├── parser.zig
│   │   │   └── resolver.zig
│   │   ├── borsh/
│   │   │   ├── serialize.zig
│   │   │   └── deserialize.zig
│   │   └── transaction.zig
│   ├── evm/
│   │   ├── provider.zig       # EVM Provider 实现
│   │   ├── abi/
│   │   │   ├── types.zig
│   │   │   ├── parser.zig
│   │   │   └── resolver.zig   # Etherscan 集成
│   │   ├── encoding/
│   │   │   ├── encoder.zig    # ABI 编码
│   │   │   └── decoder.zig    # ABI 解码
│   │   ├── proxy.zig          # 代理检测
│   │   └── transaction.zig
│   ├── mcp_engine/
│   │   ├── tool_generator.zig # 跨链通用生成器
│   │   ├── resource.zig       # Resource Provider
│   │   └── executor.zig       # 通用执行器
│   └── transaction/
│       ├── types.zig          # 统一 Transaction 类型
│       └── builder.zig
├── tools/
│   └── dynamic/               # 动态工具
└── config/
    ├── chains.json            # 链配置（RPC, Explorer API）
    └── api_keys.json          # API Keys 配置
```

---

## 🎯 Phase 1 起点（立即可开始）

### 今天的任务（4-6小时）

1. **创建 Provider 抽象接口**（1小时）
   ```bash
   src/core/provider/interface.zig
   src/core/provider/registry.zig
   ```

2. **定义统一数据结构**（1-2小时）
   ```zig
   // src/core/provider/types.zig
   pub const ContractMeta = struct { ... };
   pub const Function = struct { ... };
   pub const Transaction = union(ChainType) { ... };
   ```

3. **实现 Solana Provider 骨架**（2小时）
   ```zig
   // src/core/solana/provider.zig
   pub const SolanaProvider = struct {
       pub fn init(...) !SolanaProvider { ... }
       pub fn getContractMeta(...) !ContractMeta { ... }
   };
   ```

4. **创建测试配置**（30分钟）
   ```json
   // config/chains.json
   {
     "solana": {
       "mainnet": {
         "rpc": "https://api.mainnet-beta.solana.com",
         "explorer": "https://api.solana.fm"
       }
     },
     "evm": {
       "ethereum": {
         "chain_id": 1,
         "rpc": "https://eth.llamarpc.com",
         "explorer": "https://api.etherscan.io"
       }
     }
   }
   ```

5. **下载测试数据**（30分钟）
   - Jupiter IDL
   - Uniswap V3 ABI
   - USDC ERC20 ABI

---

## 🔍 关键技术决策

### 1. EVM ABI 编码库
**选项**：
- A) 手写 Zig ABI 编码器（控制力强）
- B) 使用 `zabi` 库（如果成熟）
- C) 调用 Rust/JS 库（FFI）

**建议**：A，ABI 编码比 Borsh 更复杂但仍可控

### 2. 代理检测策略
**ERC-1967** 是主流，但还有：
- ERC-1822 (UUPS)
- Beacon Proxy
- Gnosis Safe (MultiSig)

**建议**：
- Phase 2 先支持 ERC-1967
- Phase 4 扩展其他模式

### 3. uint256 处理
JavaScript 的 `Number` 只有 53 位精度，Zig 原生支持大整数。

**策略**：
- 内部用 `u256` 计算
- JSON 序列化为字符串 `"1000000000000000000"`
- AI 友好的单位转换（如 1 ETH = 1e18 wei）

### 4. 多链 RPC 管理
**方案**：
```zig
pub const RpcManager = struct {
    endpoints: std.StringHashMap([]const u8),

    pub fn getRpc(self: *Self, chain: []const u8) ![]const u8 {
        return self.endpoints.get(chain) orelse {
            // Fallback to public RPC
            return getPublicRpc(chain);
        };
    }
};
```

---

## 🌟 杀手级应用场景

### 场景 1: 跨链 DeFi 操作
```
AI: "把我在 Ethereum 的 USDC 跨链到 Base，然后在 Aerodrome 提供流动性"

Gateway 自动：
1. 检测 USDC Ethereum 合约 ABI
2. 生成 approve + bridge 工具
3. 检测 Aerodrome Base 合约 ABI
4. 生成 addLiquidity 工具
5. 串联执行
```

### 场景 2: 新协议即时支持
```
开发者: "刚部署了一个新的 Lending Protocol 到 Arbitrum，地址是 0x..."

AI: "帮我存入 1 ETH"

Gateway:
1. 从 Arbiscan 抓取 ABI
2. 自动生成 deposit 工具
3. 构建交易
（无需任何代码更新！）
```

### 场景 3: 统一 Portfolio 查询
```
AI: "查看我在所有链上的 USDC 余额"

Gateway:
1. 遍历 EVM 链（Ethereum, BSC, Polygon, Base...）
2. 统一调用 balanceOf (view)
3. 返回聚合结果
```

---

## ✅ 决策点

**现在要开始实现吗？**

**A) 立即开始 - 创建 Provider 抽象**
   - 我会创建目录结构
   - 定义接口和类型
   - 实现 Solana Provider 骨架

**B) 先实现 Solana 部分**
   - 专注完成 Phase 1（Solana）
   - Phase 2 再做 EVM

**C) 先做技术调研**
   - 研究 zabi 库
   - 测试 Etherscan API
   - 评估工作量

你想选哪个？
