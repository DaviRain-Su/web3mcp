# Phase 1 Implementation: Universal Chain Provider Foundation

## Overview

Phase 1 establishes the foundational architecture for dynamic MCP tool generation from blockchain program metadata. This implementation focuses on Solana/Anchor but is designed to be extensible to other chains.

**Status**: ✅ Core implementation complete (Tasks #1-6)
**Language**: Zig 0.16-dev
**Architecture**: Provider plugin system with runtime polymorphism

## Implementation Summary

### Completed Components

1. **ChainProvider Interface** (`src/core/chain_provider.zig`)
   - Universal abstraction for all blockchain providers
   - VTable-based runtime polymorphism (no classes/inheritance in Zig)
   - Supports: metadata resolution, tool generation, transaction building, on-chain queries

2. **Borsh Serialization** (`src/core/borsh.zig`)
   - Complete implementation of Borsh spec for Zig
   - Supports: primitives, strings, arrays, structs, optionals, enums
   - Both serialization and deserialization
   - Used by Solana for transaction encoding

3. **SolanaProvider** (`src/providers/solana/provider.zig`)
   - Concrete implementation of ChainProvider for Solana
   - IDL caching for performance
   - Delegates to specialized modules

4. **IDL Resolver** (`src/providers/solana/idl_resolver.zig`)
   - Multi-source IDL resolution strategy:
     1. Local registry (fastest)
     2. Solana FM API (reliable)
     3. On-chain IDL account (TODO)
   - Parses Anchor IDL JSON into ContractMeta
   - Extracts instructions, types, events

5. **Tool Generator** (`src/providers/solana/tool_generator.zig`)
   - Dynamic MCP tool creation from contract metadata
   - Generates JSON Schema from Anchor types
   - One tool per instruction/function
   - Naming: `{program_name}_{function_name}`

6. **Transaction Builder** (`src/providers/solana/transaction_builder.zig`)
   - Builds unsigned transactions from function calls
   - Anchor discriminator computation: SHA256("global:function_name")[0..8]
   - Borsh argument serialization
   - Metadata preservation for signing

## Architecture Decisions

### 1. VTable Pattern for Polymorphism

**Problem**: Zig has no inheritance or trait system
**Solution**: Function pointer struct (VTable) with opaque context

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

**Benefits**:
- Runtime dispatch like virtual methods
- Type-safe downcasting with `@ptrCast(@alignCast(ctx))`
- Easy to add new providers

### 2. Borsh from Scratch

**Why not use existing library?**
- No mature Zig Borsh library available
- Full control over serialization logic
- Educational value for understanding Solana internals

**Implementation approach**:
- Compile-time reflection with `@typeInfo`
- Recursive serialization for complex types
- Little-endian integer encoding
- Length-prefixed strings/arrays

### 3. Multi-Source IDL Resolution

**Fallback strategy**:
1. **Local registry** (`idl_registry/{program_id}.json`)
   - Instant access, no network
   - User can populate with known programs

2. **Solana FM API** (`https://api.solana.fm/v1/programs/{program_id}/idl`)
   - Community-maintained IDL database
   - Covers most popular programs

3. **On-chain IDL** (future)
   - Read IDL account from Solana blockchain
   - Most authoritative but requires RPC

**Rationale**: Reliability > Speed. Multiple sources ensure availability.

### 4. JSON Schema Generation

**Type mapping**:
```
Anchor Type          → JSON Schema
─────────────────────────────────────
u8, u16, u32, u64    → type: "integer"
i8, i16, i32, i64    → type: "integer"
bool                 → type: "boolean"
string               → type: "string"
publicKey            → type: "string" (description: base58)
bytes                → type: "string" (description: base64/hex)
Option<T>            → anyOf: [T, null]
Vec<T>               → type: "array", items: T
struct               → type: "object", properties: {...}
```

**Benefits**:
- LLMs can understand parameter schemas
- Auto-validation of user inputs
- Consistent error messages

## API Examples

### Using ChainProvider

```zig
// Initialize Solana provider
const provider = try SolanaProvider.init(allocator, "https://api.mainnet-beta.solana.com");
defer provider.deinit();

// Convert to generic interface
const chain_prov = provider.asChainProvider();

// Get contract metadata
const meta = try chain_prov.getContractMeta(allocator, "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4");

// Generate MCP tools
const tools = try chain_prov.generateTools(allocator, &meta);

// Build transaction
const call = FunctionCall{
    .contract = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
    .function = "swap",
    .signer = user_pubkey,
    .args = args_json,
    .options = .{ .value = 0, .gas_limit = null },
};
const tx = try chain_prov.buildTransaction(allocator, call);
```

### Discriminator Computation

```zig
const disc = try computeDiscriminator(allocator, "swap");
// Result: F8C69E91E17587C8 (SHA256("global:swap")[0..8])
```

### Borsh Serialization

```zig
// Serialize struct
const Point = struct { x: u32, y: u32 };
const point = Point{ .x = 10, .y = 20 };
const bytes = try borsh.serialize(allocator, point);
// bytes = [0A 00 00 00 14 00 00 00] (little-endian)

// Serialize string
var buffer: std.ArrayList(u8) = .empty;
try borsh.serializeString(allocator, &buffer, "hello");
// buffer = [05 00 00 00 68 65 6C 6C 6F] (length prefix + UTF-8)
```

## Zig 0.16 Compatibility

### ArrayList API Changes

**Old (Zig 0.13)**:
```zig
var list = std.ArrayList(u8).init(allocator);
try list.append(1);
list.deinit();
```

**New (Zig 0.16)**:
```zig
var list: std.ArrayList(u8) = .empty;
try list.append(allocator, 1);  // Pass allocator!
list.deinit(allocator);
```

**Rationale**: ArrayList is now "unmanaged" - doesn't store allocator internally, reducing struct size and improving composability.

### Type Info Changes

**Old**: `@typeInfo(T).Int`
**New**: `@typeInfo(T).int`

All union fields in `builtin.Type` are now lowercase.

## Testing

### Component Tests (Verified ✅)

**test_phase1.zig** validates:
- Anchor discriminator determinism
- Borsh integer serialization (u64)
- Borsh string serialization (length prefix)
- Borsh boolean serialization

**Results**:
```
Test 1: Anchor Discriminator Computation
  initialize: AFAF6D1F0D989BED ✓
  swap: F8C69E91E17587C8 ✓
  transfer: A334C8E78C0345BA ✓
  mint: 3339E12FB69289A6 ✓
  burn: 746E1D386BDB2A5D ✓

Test 2: Borsh Serialization
  u64: 8 bytes ✓
  string: 17 bytes (4 byte length + 13 chars) ✓
  bool: 1 byte ✓
```

### Integration Tests (Blocked)

**Planned tests**:
- Jupiter swap tool generation
- SPL Token transfer/mint/burn tools
- End-to-end: IDL fetch → Tool gen → Transaction build

**Blocker**: Build system dependency fetch fails (503 errors on GitHub releases). Requires deployment environment or manual dependency management.

## Known Limitations

1. **No On-Chain IDL Reading**
   - Currently depends on local registry or Solana FM API
   - Future: Read IDL account from blockchain directly

2. **No Account Resolution**
   - Transaction builder doesn't auto-derive PDAs
   - User must provide all account addresses
   - Future: Parse `#[account(...)]` constraints from IDL

3. **No Simulation/Estimation**
   - No compute unit estimation
   - No balance checks before transaction building
   - Future: Integrate with RPC `simulateTransaction`

4. **Limited Type Support**
   - Custom types (enums with data, nested structs) need more work
   - No support for Anchor's `#[zero_copy]` or `#[account]` types
   - Future: Full Anchor type system support

5. **No Event Parsing**
   - Events are parsed from IDL but not used
   - Future: Event subscriptions, log decoding

6. **No Multi-Instruction Transactions**
   - One function call = one instruction
   - Future: Composable instruction builder

## Next Steps

### Phase 2: EVM Provider
- Implement `EVMProvider` with same ChainProvider interface
- ABI parsing (similar to IDL parsing)
- RLP serialization (similar to Borsh)
- Tool generation for Solidity contracts

### Phase 3: MCP Server Integration
- HTTP server with MCP protocol
- Tool routing to correct provider
- Session management
- Error handling and logging

### Phase 4: Wallet Integration
- Transaction signing (Phantom, MetaMask)
- Approval UI
- Multi-sig support

## File Structure

```
src/
├── core/
│   ├── chain_provider.zig      # Universal provider interface
│   └── borsh.zig                # Borsh serialization library
└── providers/
    └── solana/
        ├── provider.zig         # Solana provider implementation
        ├── idl_resolver.zig     # IDL fetching and parsing
        ├── tool_generator.zig   # MCP tool generation
        └── transaction_builder.zig  # Transaction building
```

## Dependencies

- Zig 0.16-dev (nightly)
- std library (builtin ArrayList, JSON, crypto)
- External (via build.zig.zon):
  - mcp: MCP protocol types
  - solana_client: RPC client (future)
  - solana_sdk: Key/signature types (future)

## Contributing

When adding a new chain:

1. Create `src/providers/{chain}/provider.zig`
2. Implement ChainProvider.VTable methods
3. Add chain-specific metadata parser
4. Add serialization library if needed
5. Write integration tests
6. Update docs

## References

- [Anchor IDL Spec](https://www.anchor-lang.com/docs/idl)
- [Borsh Specification](https://borsh.io/)
- [MCP Protocol](https://modelcontextprotocol.io/docs)
- [Solana FM IDL API](https://docs.solana.fm/api-reference/idl-api)

---

**Implementation Date**: January 2026
**Status**: Core foundation complete, integration tests pending
