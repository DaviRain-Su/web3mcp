const std = @import("std");
const mcp = @import("../mcp.zig");

/// Chain types supported by the universal gateway
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

    pub fn toString(self: ChainType) []const u8 {
        return switch (self) {
            .solana => "solana",
            .evm => "evm",
            .cosmos => "cosmos",
            .ton => "ton",
            .starknet => "starknet",
            .icp => "icp",
            .sui => "sui",
            .aptos => "aptos",
            .near => "near",
            .bitcoin => "bitcoin",
            .tron => "tron",
        };
    }
};

/// Universal representation of contract metadata across all chains
pub const ContractMeta = struct {
    chain: ChainType,
    address: []const u8,
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    functions: []Function,
    types: []TypeDef,
    events: []Event,
    raw: std.json.Value, // Original IDL/ABI for advanced use

    pub fn deinit(self: *ContractMeta, allocator: std.mem.Allocator) void {
        for (self.functions) |*func| {
            func.deinit(allocator);
        }
        allocator.free(self.functions);

        for (self.types) |*type_def| {
            type_def.deinit(allocator);
        }
        allocator.free(self.types);

        for (self.events) |*event| {
            event.deinit(allocator);
        }
        allocator.free(self.events);
    }
};

/// Function definition in a contract
pub const Function = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    inputs: []Parameter,
    outputs: []Parameter,
    mutability: Mutability,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.inputs) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.inputs);

        for (self.outputs) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.outputs);
    }
};

/// Function mutability
pub const Mutability = enum {
    view, // Read-only (Solana: no signer, EVM: view/pure)
    mutable, // State-changing (requires transaction)
    payable, // Accepts native token (EVM: payable, Solana: transfer)
};

/// Parameter definition
pub const Parameter = struct {
    name: []const u8,
    type: Type,
    optional: bool = false,

    pub fn deinit(self: *Parameter, allocator: std.mem.Allocator) void {
        self.type.deinit(allocator);
    }
};

/// Type system
pub const Type = union(enum) {
    primitive: PrimitiveType,
    array: *Type,
    struct_type: []Field,
    option: *Type,
    custom: []const u8, // Reference to TypeDef

    pub fn deinit(self: *Type, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |ptr| {
                ptr.deinit(allocator);
                allocator.destroy(ptr);
            },
            .struct_type => |fields| {
                for (fields) |*field| {
                    field.deinit(allocator);
                }
                allocator.free(fields);
            },
            .option => |ptr| {
                ptr.deinit(allocator);
                allocator.destroy(ptr);
            },
            else => {},
        }
    }
};

/// Primitive types
pub const PrimitiveType = enum {
    u8,
    u16,
    u32,
    u64,
    u128,
    u256,
    i8,
    i16,
    i32,
    i64,
    i128,
    bool,
    string,
    bytes,
    pubkey, // Solana public key
    address, // EVM address
};

/// Field in a struct
pub const Field = struct {
    name: []const u8,
    type: Type,

    pub fn deinit(self: *Field, allocator: std.mem.Allocator) void {
        self.type.deinit(allocator);
    }
};

/// Custom type definition
pub const TypeDef = struct {
    name: []const u8,
    kind: TypeDefKind,

    pub fn deinit(self: *TypeDef, allocator: std.mem.Allocator) void {
        switch (self.kind) {
            .struct_def => |fields| {
                for (fields) |*field| {
                    field.deinit(allocator);
                }
                allocator.free(fields);
            },
            .enum_def => |variants| {
                allocator.free(variants);
            },
        }
    }
};

pub const TypeDefKind = union(enum) {
    struct_def: []Field,
    enum_def: [][]const u8, // Variant names
};

/// Event definition
pub const Event = struct {
    name: []const u8,
    fields: []Field,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
    }
};

/// Chain-agnostic transaction representation
pub const Transaction = struct {
    chain: ChainType,
    from: ?[]const u8 = null,
    to: []const u8,
    data: []const u8, // Serialized instruction/calldata
    value: ?u128 = null, // Native token amount (lamports/wei)
    gas_limit: ?u64 = null,
    gas_price: ?u64 = null,
    nonce: ?u64 = null,
    metadata: std.json.Value, // Chain-specific fields

    pub fn deinit(self: *Transaction, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Function call request
pub const FunctionCall = struct {
    contract: []const u8,
    function: []const u8,
    args: std.json.Value,
    signer: ?[]const u8 = null,
    options: CallOptions = .{},
};

/// Call options
pub const CallOptions = struct {
    value: ?u128 = null,
    gas: ?u64 = null,
    simulate: bool = false,
};

/// Data query for on-chain data
pub const DataQuery = struct {
    chain: ChainType,
    query_type: QueryType,
    address: []const u8,
    params: std.json.Value,
};

pub const QueryType = enum {
    account_info, // Get account/contract state
    token_balance,
    transaction,
    block,
    logs,
    storage_slot, // EVM-specific
    program_account, // Solana-specific
};

/// Universal ChainProvider interface
/// All blockchain providers must implement this interface via vtable
pub const ChainProvider = struct {
    const Self = @This();

    chain_type: ChainType,
    vtable: *const VTable,
    context: *anyopaque, // Provider-specific state

    /// Virtual table for polymorphic dispatch
    pub const VTable = struct {
        /// Fetch contract metadata (IDL/ABI)
        getContractMeta: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            address: []const u8,
        ) anyerror!ContractMeta,

        /// Generate MCP tools from metadata
        generateTools: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            meta: *const ContractMeta,
        ) anyerror![]mcp.tools.Tool,

        /// Build unsigned transaction
        buildTransaction: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            call: FunctionCall,
        ) anyerror!Transaction,

        /// Read on-chain account/state data
        readOnchainData: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            query: DataQuery,
        ) anyerror![]const u8,

        /// Cleanup
        deinit: *const fn (ctx: *anyopaque) void,
    };

    /// Public API - delegates to vtable

    pub fn getContractMeta(
        self: *Self,
        allocator: std.mem.Allocator,
        address: []const u8,
    ) !ContractMeta {
        return self.vtable.getContractMeta(self.context, allocator, address);
    }

    pub fn generateTools(
        self: *Self,
        allocator: std.mem.Allocator,
        meta: *const ContractMeta,
    ) ![]mcp.tools.Tool {
        return self.vtable.generateTools(self.context, allocator, meta);
    }

    pub fn buildTransaction(
        self: *Self,
        allocator: std.mem.Allocator,
        call: FunctionCall,
    ) !Transaction {
        return self.vtable.buildTransaction(self.context, allocator, call);
    }

    pub fn readOnchainData(
        self: *Self,
        allocator: std.mem.Allocator,
        query: DataQuery,
    ) ![]const u8 {
        return self.vtable.readOnchainData(self.context, allocator, query);
    }

    pub fn deinit(self: *Self) void {
        self.vtable.deinit(self.context);
    }
};

/// Provider registry for managing multiple chain providers
pub const ProviderRegistry = struct {
    allocator: std.mem.Allocator,
    providers: std.StringHashMap(*ChainProvider),

    pub fn init(allocator: std.mem.Allocator) ProviderRegistry {
        return .{
            .allocator = allocator,
            .providers = std.StringHashMap(*ChainProvider).init(allocator),
        };
    }

    pub fn deinit(self: *ProviderRegistry) void {
        var it = self.providers.valueIterator();
        while (it.next()) |provider_ptr| {
            provider_ptr.*.deinit();
        }
        self.providers.deinit();
    }

    pub fn register(self: *ProviderRegistry, chain: ChainType, provider: *ChainProvider) !void {
        try self.providers.put(chain.toString(), provider);
    }

    pub fn getProvider(self: *ProviderRegistry, chain: ChainType) ?*ChainProvider {
        return self.providers.get(chain.toString());
    }
};
