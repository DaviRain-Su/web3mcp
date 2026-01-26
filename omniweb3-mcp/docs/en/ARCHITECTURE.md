# Web3 MCP Gateway - Technical Architecture

> **Universal Gateway that transforms any blockchain program (via IDL/ABI) into MCP tools accessible by AI**

## Table of Contents
- [Core Vision](#core-vision)
- [Architecture Overview](#architecture-overview)
- [Provider Plugin System](#provider-plugin-system)
- [Unified Abstractions](#unified-abstractions)
- [Solana Provider](#solana-provider)
- [EVM Provider](#evm-provider)
- [Other Chain Providers](#other-chain-providers)
- [Implementation Phases](#implementation-phases)

---

## Core Vision

### The Problem
Currently, adding support for a new blockchain program requires:
1. Manual tool creation for each function
2. Hardcoded data structures
3. Custom serialization logic
4. Program-specific error handling

This doesn't scale when there are thousands of programs across dozens of blockchains.

### The Solution
**Automatically convert blockchain program metadata (IDL/ABI) into MCP tools at runtime.**

```
IDL/ABI → Dynamic MCP Tools → AI can instantly interact with any program
```

### Key Insight
Every blockchain ecosystem already has a machine-readable contract interface format:
- **Solana**: Anchor IDL (JSON)
- **EVM**: Contract ABI (JSON)
- **Cosmos**: Protobuf schemas
- **Starknet**: Cairo ABI
- **ICP**: Candid IDL

We just need to **parse these formats and generate MCP tools dynamically**.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     AI Client (Claude, etc.)                 │
└────────────────────────┬────────────────────────────────────┘
                         │ MCP Protocol (JSON-RPC)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Universal MCP Gateway                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Provider Registry & Router                   │  │
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
   │  Chain  │      │  Chains │      │  Chains │
   └─────────┘      └─────────┘      └─────────┘
```

### Three-Layer Design

1. **MCP Interface Layer** (Frontend)
   - Standard JSON-RPC server
   - Tool/Resource registration
   - Request routing

2. **Provider Abstraction Layer** (Core)
   - Unified `ChainProvider` interface
   - Dynamic tool generation
   - Transaction building
   - Account data parsing

3. **Blockchain Layer** (Backend)
   - Chain-specific RPC clients
   - IDL/ABI resolvers
   - Transaction signers

---

## Provider Plugin System

### ChainProvider Interface

All blockchain providers implement this unified interface:

```zig
pub const ChainProvider = struct {
    const Self = @This();

    chain_type: ChainType,
    vtable: *const VTable,
    context: *anyopaque,  // Provider-specific state

    pub const VTable = struct {
        // Fetch contract metadata (IDL/ABI)
        getContractMeta: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            address: []const u8,
        ) anyerror!ContractMeta,

        // Generate MCP tools from metadata
        generateTools: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            meta: ContractMeta,
        ) anyerror![]mcp.tools.Tool,

        // Build unsigned transaction
        buildTransaction: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            call: FunctionCall,
        ) anyerror!Transaction,

        // Read on-chain account/state data
        readOnchainData: *const fn(
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            query: DataQuery,
        ) anyerror![]const u8,

        // Cleanup
        deinit: *const fn(ctx: *anyopaque) void,
    };

    // Public API (delegates to vtable)
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
    // ... extensible
};
```

---

## Unified Abstractions

### ContractMeta
Universal representation of contract metadata across all chains:

```zig
pub const ContractMeta = struct {
    chain: ChainType,
    address: []const u8,
    name: ?[]const u8,
    version: ?[]const u8,
    functions: []Function,
    types: []TypeDef,
    events: []Event,
    raw: std.json.Value,  // Original IDL/ABI for advanced use
};

pub const Function = struct {
    name: []const u8,
    description: ?[]const u8,
    inputs: []Parameter,
    outputs: []Parameter,
    mutability: Mutability,
};

pub const Mutability = enum {
    view,       // Read-only (Solana: no signer, EVM: view/pure)
    mutable,    // State-changing (requires transaction)
    payable,    // Accepts native token (EVM: payable, Solana: transfer)
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
    custom: []const u8,  // Reference to TypeDef
};

pub const PrimitiveType = enum {
    u8, u16, u32, u64, u128, u256,
    i8, i16, i32, i64, i128,
    bool,
    string,
    bytes,
    pubkey,    // Solana public key
    address,   // EVM address
};
```

### Transaction
Chain-agnostic transaction representation:

```zig
pub const Transaction = struct {
    chain: ChainType,
    from: ?[]const u8,
    to: []const u8,
    data: []const u8,        // Serialized instruction/calldata
    value: ?u128,            // Native token amount (lamports/wei)
    gas_limit: ?u64,
    gas_price: ?u64,
    nonce: ?u64,
    metadata: std.json.Value,  // Chain-specific fields
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

### DataQuery
Unified on-chain data access:

```zig
pub const DataQuery = struct {
    chain: ChainType,
    query_type: QueryType,
    address: []const u8,
    params: std.json.Value,
};

pub const QueryType = enum {
    account_info,      // Get account/contract state
    token_balance,
    transaction,
    block,
    logs,
    storage_slot,      // EVM-specific
    program_account,   // Solana-specific
};
```

---

## Solana Provider

### IDL Resolution Strategy

```zig
pub const SolanaProvider = struct {
    rpc_client: SolanaRpcClient,
    idl_cache: std.StringHashMap(ContractMeta),

    pub fn getContractMeta(
        self: *SolanaProvider,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        // Check cache first
        if (self.idl_cache.get(program_id)) |cached| {
            return cached;
        }

        // Strategy 1: Fetch from on-chain IDL account
        if (self.fetchOnChainIdl(allocator, program_id)) |idl| {
            const meta = try self.parseIdl(allocator, idl, program_id);
            try self.idl_cache.put(program_id, meta);
            return meta;
        } else |_| {}

        // Strategy 2: Query Solana FM API
        if (self.fetchFromSolanaFM(allocator, program_id)) |idl| {
            const meta = try self.parseIdl(allocator, idl, program_id);
            try self.idl_cache.put(program_id, meta);
            return meta;
        } else |_| {}

        // Strategy 3: Check local registry
        if (self.loadFromRegistry(allocator, program_id)) |idl| {
            const meta = try self.parseIdl(allocator, idl, program_id);
            try self.idl_cache.put(program_id, meta);
            return meta;
        } else |_| {}

        return error.IdlNotFound;
    }

    fn parseIdl(
        self: *SolanaProvider,
        allocator: std.mem.Allocator,
        idl_json: []const u8,
        program_id: []const u8,
    ) !ContractMeta {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, idl_json, .{});
        defer parsed.deinit();

        const idl = parsed.value;

        // Parse instructions -> Functions
        var functions = std.ArrayList(Function).init(allocator);
        const instructions = idl.object.get("instructions").?.array;
        for (instructions.items) |instr| {
            try functions.append(try self.parseInstruction(allocator, instr));
        }

        // Parse accounts -> TypeDefs
        var types = std.ArrayList(TypeDef).init(allocator);
        if (idl.object.get("accounts")) |accounts| {
            for (accounts.array.items) |account| {
                try types.append(try self.parseAccount(allocator, account));
            }
        }

        return ContractMeta{
            .chain = .solana,
            .address = program_id,
            .name = if (idl.object.get("name")) |n| n.string else null,
            .version = if (idl.object.get("version")) |v| v.string else null,
            .functions = try functions.toOwnedSlice(),
            .types = try types.toOwnedSlice(),
            .events = &.{},
            .raw = idl,
        };
    }
};
```

### Dynamic Tool Generation

```zig
pub fn generateTools(
    self: *SolanaProvider,
    allocator: std.mem.Allocator,
    meta: ContractMeta,
) ![]mcp.tools.Tool {
    var tools = std.ArrayList(mcp.tools.Tool).init(allocator);

    for (meta.functions) |func| {
        // Generate tool name: programName_functionName
        const tool_name = try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ meta.name orelse "program", func.name },
        );

        // Generate input schema from function inputs
        const input_schema = try self.generateInputSchema(allocator, func.inputs);

        // Create tool handler that captures metadata
        const handler = try self.createHandler(allocator, meta.address, func);

        try tools.append(.{
            .name = tool_name,
            .description = func.description orelse try std.fmt.allocPrint(
                allocator,
                "Call {s} instruction on {s}",
                .{ func.name, meta.address },
            ),
            .inputSchema = input_schema,
            .handler = handler,
        });
    }

    return tools.toOwnedSlice();
}
```

### Transaction Building

```zig
pub fn buildTransaction(
    self: *SolanaProvider,
    allocator: std.mem.Allocator,
    call: FunctionCall,
) !Transaction {
    // 1. Fetch IDL to get instruction layout
    const meta = try self.getContractMeta(allocator, call.contract);
    const func = try self.findFunction(meta, call.function);

    // 2. Serialize arguments using Borsh
    const args_data = try self.serializeBorsh(allocator, func.inputs, call.args);

    // 3. Build instruction discriminator (first 8 bytes of SHA256)
    const discriminator = try self.computeDiscriminator(call.function);

    // 4. Combine discriminator + args
    var instruction_data = try allocator.alloc(u8, 8 + args_data.len);
    @memcpy(instruction_data[0..8], &discriminator);
    @memcpy(instruction_data[8..], args_data);

    // 5. Resolve accounts (from args or derive PDAs)
    const accounts = try self.resolveAccounts(allocator, meta, func, call.args);

    // 6. Build transaction
    return Transaction{
        .chain = .solana,
        .from = call.signer,
        .to = call.contract,
        .data = instruction_data,
        .value = call.options.value,
        .metadata = try std.json.Value.object(allocator, .{
            .accounts = accounts,
            .program_id = call.contract,
        }),
    };
}
```

---

## EVM Provider

### ABI Resolution Strategy

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
        // Check cache
        if (self.abi_cache.get(address)) |cached| {
            return cached;
        }

        // Strategy 1: Check if proxy, get implementation
        const impl_address = try self.resolveProxy(allocator, address);

        // Strategy 2: Fetch ABI from Etherscan
        if (self.fetchFromEtherscan(allocator, impl_address)) |abi| {
            const meta = try self.parseAbi(allocator, abi, impl_address);
            try self.abi_cache.put(address, meta);
            return meta;
        } else |_| {}

        // Strategy 3: Check local registry
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
        // ERC-1967: Implementation slot = keccak256("eip1967.proxy.implementation") - 1
        const slot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

        const impl_bytes = try self.rpc_client.getStorageAt(address, slot);

        // If slot is zero, not a proxy
        const is_zero = for (impl_bytes) |b| {
            if (b != 0) break false;
        } else true;

        if (is_zero) {
            return address;  // Not a proxy
        }

        // Extract address from last 20 bytes
        return try std.fmt.allocPrint(allocator, "0x{s}", .{
            std.fmt.fmtSliceHexLower(impl_bytes[12..32]),
        });
    }
};
```

### ABI Parsing

```zig
fn parseAbi(
    self: *EvmProvider,
    allocator: std.mem.Allocator,
    abi_json: []const u8,
    address: []const u8,
) !ContractMeta {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, abi_json, .{});
    defer parsed.deinit();

    const abi = parsed.value.array;
    var functions = std.ArrayList(Function).init(allocator);
    var events = std.ArrayList(Event).init(allocator);

    for (abi.items) |item| {
        const item_type = item.object.get("type").?.string;

        if (std.mem.eql(u8, item_type, "function")) {
            try functions.append(try self.parseFunction(allocator, item));
        } else if (std.mem.eql(u8, item_type, "event")) {
            try events.append(try self.parseEvent(allocator, item));
        }
    }

    return ContractMeta{
        .chain = .evm,
        .address = address,
        .name = null,  // ABI doesn't include contract name
        .version = null,
        .functions = try functions.toOwnedSlice(),
        .types = &.{},  // EVM doesn't have TypeDefs in ABI
        .events = try events.toOwnedSlice(),
        .raw = parsed.value,
    };
}
```

### Transaction Building

```zig
pub fn buildTransaction(
    self: *EvmProvider,
    allocator: std.mem.Allocator,
    call: FunctionCall,
) !Transaction {
    // 1. Fetch ABI
    const meta = try self.getContractMeta(allocator, call.contract);
    const func = try self.findFunction(meta, call.function);

    // 2. Compute function selector (first 4 bytes of keccak256)
    const selector = try self.computeSelector(func);

    // 3. Encode arguments using ABI encoding
    const encoded_args = try self.encodeAbi(allocator, func.inputs, call.args);

    // 4. Combine selector + encoded args
    var calldata = try allocator.alloc(u8, 4 + encoded_args.len);
    @memcpy(calldata[0..4], &selector);
    @memcpy(calldata[4..], encoded_args);

    // 5. Estimate gas if not provided
    const gas_limit = call.options.gas orelse try self.estimateGas(
        call.signer,
        call.contract,
        calldata,
        call.options.value,
    );

    return Transaction{
        .chain = .evm,
        .from = call.signer,
        .to = call.contract,
        .data = calldata,
        .value = call.options.value,
        .gas_limit = gas_limit,
        .gas_price = try self.getGasPrice(),
        .nonce = if (call.signer) |s| try self.getNonce(s) else null,
    };
}
```

---

## Other Chain Providers

### Cosmos Provider
- Protobuf schemas via gRPC reflection
- CosmWasm: JSON schema in contract state
- Query: `/cosmos.tx.v1beta1.Service/GetTx`

### Starknet Provider
- Cairo ABI from contract class
- Felt252 serialization
- Contract class hash resolution

### TON Provider
- TL-B schema parsing
- Cell serialization
- Actor model message construction

### ICP Provider
- Candid IDL from canister metadata
- CBOR encoding
- Update/Query call distinction

### Sui/Aptos Provider
- Move module ABIs
- BCS serialization
- Object-centric transaction building

---

## Implementation Phases

### Phase 1: Foundation (4-6 weeks)
**Goal**: Prove the concept with Solana

- [ ] Implement `ChainProvider` interface
- [ ] Create `SolanaProvider` with IDL parsing
- [ ] Build dynamic tool generator
- [ ] Implement Borsh serialization
- [ ] Test with 3 programs (Jupiter, Metaplex, SPL Token)

**Deliverable**: AI can interact with any Anchor program given its IDL

### Phase 2: EVM Support (3-4 weeks)
**Goal**: Extend to Ethereum ecosystem

- [ ] Create `EvmProvider` with ABI parsing
- [ ] Implement proxy detection (ERC-1967)
- [ ] Add Etherscan API integration
- [ ] Build ABI encoder/decoder
- [ ] Test with Uniswap V3, USDC, Aave

**Deliverable**: Single MCP server supports both Solana and EVM

### Phase 3: Multi-Chain (4-5 weeks)
**Goal**: Cover 80% of Web3 ecosystems

- [ ] Add Cosmos Provider (Protobuf + gRPC)
- [ ] Add Starknet Provider (Cairo ABI)
- [ ] Add TON Provider (TL-B)
- [ ] Implement provider registry and routing
- [ ] Add chain auto-detection from addresses

**Deliverable**: Universal gateway supporting 5+ chain types

### Phase 4: Advanced Features (3-4 weeks)
**Goal**: Production-ready capabilities

- [ ] Intent-based API (high-level goals → multi-step execution)
- [ ] Transaction simulation before execution
- [ ] Gas optimization strategies
- [ ] Multi-signature support
- [ ] Session key management

**Deliverable**: Enterprise-grade gateway with advanced features

### Phase 5: Ecosystem Integration (2-3 weeks)
**Goal**: Real-world deployment

- [ ] NEAR integration (Chain Signatures for unified accounts)
- [ ] Hosted API service (api.web3mcp.com)
- [ ] SDK for custom providers
- [ ] Documentation and tutorials
- [ ] Performance optimization (caching, batching)

**Deliverable**: Public service ready for mass adoption

---

## Resource URI Format

Universal addressing scheme for blockchain data:

```
<chain>://<contract>/<resource_type>/<identifier>[?params]
```

### Examples

```
solana://TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA/account/mint/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v

evm://0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48/balance/0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb

cosmos://cosmoshub-4/bank/balance/cosmos1...?denom=uatom

starknet://0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7/storage/0x123

ton://EQD...ABC/get_method/get_wallet_data

near://token.near/ft_balance_of/alice.near
```

---

## Performance Considerations

### Caching Strategy
1. **IDL/ABI Cache**: In-memory + disk persistence (24h TTL)
2. **Tool Cache**: Pre-generate tools for popular contracts
3. **RPC Cache**: Cache immutable data (block history, transaction receipts)

### Optimization Techniques
1. **Lazy Loading**: Only fetch IDL when first accessed
2. **Batching**: Group multiple RPC calls into single request
3. **Parallel Fetching**: Concurrent provider operations
4. **Code Generation**: Pre-compile popular contracts into native tools

### Scalability Targets
- **Latency**: < 200ms for tool call (cached), < 2s (uncached)
- **Throughput**: 100+ concurrent requests
- **Memory**: < 50MB per provider instance
- **Contracts**: Support 1000+ contracts per provider

---

## Security Model

### Key Management
- Private keys never leave MCP server
- Support for hardware wallets (Ledger, Trezor)
- Session keys for limited-scope operations
- Multi-signature wallet integration

### Transaction Safety
- Mandatory simulation before execution
- Gas price limits and slippage protection
- Allowlist/denylist for contracts
- User confirmation for high-value transactions

### API Security
- Rate limiting per API key
- Contract verification checks
- Sandboxed execution environment
- Audit logging for all operations

---

## Testing Strategy

### Unit Tests
- Each provider's IDL/ABI parsing
- Type conversion and serialization
- Transaction building logic

### Integration Tests
- End-to-end tool generation → execution
- Multi-chain transaction flows
- Error handling and recovery

### Mainnet Tests
- Real transactions on testnets
- Popular contract interactions
- Performance benchmarks

---

## Conclusion

This architecture transforms web3mcp from a **static tool collection** into a **dynamic universal gateway** that can interact with any blockchain program without manual integration work.

**Key Benefits:**
1. **Zero-Day Support**: New programs instantly accessible to AI
2. **Developer Efficiency**: No manual tool creation needed
3. **User Experience**: Natural language → Any blockchain operation
4. **Ecosystem Impact**: Removes friction in Web3 x AI integration

**Next Steps:**
- See [USE_CASES.md](./USE_CASES.md) for application scenarios
- See [BUSINESS_MODEL.md](./BUSINESS_MODEL.md) for monetization strategy
- See [NEAR_INTEGRATION.md](./NEAR_INTEGRATION.md) for chain abstraction approach
