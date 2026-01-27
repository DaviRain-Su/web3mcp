const std = @import("std");
const chains = @import("./chains.zig");
const rpc_client = @import("./rpc_client.zig");
const transaction_builder = @import("./transaction_builder.zig");
const abi_resolver = @import("./abi_resolver.zig");
const tool_generator = @import("./tool_generator.zig");
const chain_provider = @import("../../core/chain_provider.zig");

const ChainProvider = chain_provider.ChainProvider;
const FunctionCall = chain_provider.FunctionCall;
const Transaction = chain_provider.Transaction;
const DataQuery = chain_provider.DataQuery;

/// EVM-specific provider implementation (supports Ethereum, BSC, Polygon, etc.)
///
/// This provider manages EVM chain interactions including:
/// - RPC communication (ethCall, ethSendTransaction, etc.)
/// - Transaction building and ABI encoding
/// - Contract metadata caching
/// - Multi-chain support (Ethereum, BSC, Polygon, Arbitrum, Optimism)
pub const EvmProvider = struct {
    allocator: std.mem.Allocator,
    chain_config: chains.ChainConfig,
    rpc_client: rpc_client.EvmRpcClient,
    tx_builder: transaction_builder.TransactionBuilder,
    abi_cache: std.StringHashMap(abi_resolver.Abi), // Cache ABIs by contract address

    /// Initialize EVM provider for a specific chain
    pub fn init(allocator: std.mem.Allocator, chain_config: chains.ChainConfig) !*EvmProvider {
        const self = try allocator.create(EvmProvider);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .chain_config = chain_config,
            .rpc_client = try rpc_client.EvmRpcClient.init(allocator, chain_config),
            .tx_builder = transaction_builder.TransactionBuilder.init(allocator),
            .abi_cache = std.StringHashMap(abi_resolver.Abi).init(allocator),
        };

        return self;
    }

    /// Initialize from chain name (e.g., "bsc", "ethereum")
    pub fn initFromChainName(allocator: std.mem.Allocator, chain_name: []const u8) !*EvmProvider {
        const chain_config = chains.getChainByName(chain_name) orelse return error.UnknownChain;
        return init(allocator, chain_config);
    }

    /// Initialize from chain ID
    pub fn initFromChainId(allocator: std.mem.Allocator, chain_id: u64) !*EvmProvider {
        const chain_config = chains.getChainById(chain_id) orelse return error.UnknownChain;
        return init(allocator, chain_config);
    }

    pub fn deinit(self: *EvmProvider) void {
        // Clean up ABI cache
        var iter = self.abi_cache.iterator();
        while (iter.next()) |entry| {
            // Free ABI contents
            for (entry.value_ptr.functions) |func| {
                self.allocator.free(func.name);
                for (func.inputs) |param| {
                    self.allocator.free(param.name);
                    self.allocator.free(param.type);
                    if (param.internal_type) |it| self.allocator.free(it);
                }
                self.allocator.free(func.inputs);
                for (func.outputs) |param| {
                    self.allocator.free(param.name);
                    self.allocator.free(param.type);
                    if (param.internal_type) |it| self.allocator.free(it);
                }
                self.allocator.free(func.outputs);
            }
            self.allocator.free(entry.value_ptr.functions);

            for (entry.value_ptr.events) |event| {
                self.allocator.free(event.name);
                for (event.inputs) |param| {
                    self.allocator.free(param.name);
                    self.allocator.free(param.type);
                    if (param.internal_type) |it| self.allocator.free(it);
                }
                self.allocator.free(event.inputs);
            }
            self.allocator.free(entry.value_ptr.events);

            // Free key
            self.allocator.free(entry.key_ptr.*);
        }
        self.abi_cache.deinit();

        self.allocator.destroy(self);
    }

    /// Convert to ChainProvider interface
    pub fn asChainProvider(self: *EvmProvider) ChainProvider {
        return .{
            .chain_type = .evm,
            .vtable = &vtable,
            .context = @ptrCast(self),
        };
    }

    /// Virtual table implementation
    const vtable = ChainProvider.VTable{
        .getContractMeta = getContractMetaImpl,
        .generateTools = generateToolsImpl,
        .buildTransaction = buildTransactionImpl,
        .readOnchainData = readOnchainDataImpl,
        .deinit = deinitImpl,
    };

    // VTable implementations

    fn getContractMetaImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        address: []const u8,
    ) anyerror!chain_provider.ContractMeta {
        const self: *EvmProvider = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = allocator;
        _ = address;

        // For EVM, we don't fetch metadata on-chain
        // ABIs are loaded from local files in registry
        // This is typically called during tool generation, not at runtime
        return error.NotImplemented;
    }

    fn generateToolsImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        meta: *const chain_provider.ContractMeta,
    ) anyerror![]const @import("mcp").tools.Tool {
        _ = ctx;
        _ = allocator;
        _ = meta;

        // Tool generation is done during startup by registry.loadEvmContracts()
        // Not called at runtime
        return error.NotImplemented;
    }

    fn buildTransactionImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        call: FunctionCall,
    ) anyerror!Transaction {
        const self: *EvmProvider = @ptrCast(@alignCast(ctx));

        // Extract contract address and function name from call
        const contract_address = call.contract;
        const function_name = call.function;

        // Get ABI from cache or error
        const abi = self.abi_cache.get(contract_address) orelse {
            std.log.err("ABI not found for contract: {s}", .{contract_address});
            return error.AbiNotFound;
        };

        // Find function in ABI
        var target_function: ?*const abi_resolver.AbiFunction = null;
        for (abi.functions) |*func| {
            if (std.mem.eql(u8, func.name, function_name)) {
                target_function = func;
                break;
            }
        }

        if (target_function == null) {
            std.log.err("Function {s} not found in ABI for {s}", .{ function_name, contract_address });
            return error.FunctionNotFound;
        }

        // Build transaction request
        const tx_options = transaction_builder.TransactionOptions{
            .from = call.signer,
            .gas = call.options.gas,
            .value = call.options.value,
        };

        const tx_request = try self.tx_builder.buildTransaction(
            contract_address,
            target_function.?,
            call.args,
            tx_options,
        );

        // Convert to Transaction format
        const tx_data = try allocator.dupe(u8, tx_request.data);

        // Create metadata JSON
        var metadata_obj = std.json.ObjectMap.init(allocator);
        errdefer metadata_obj.deinit();

        try metadata_obj.put("chain", std.json.Value{ .string = self.chain_config.name });
        try metadata_obj.put("chain_id", std.json.Value{ .integer = @intCast(self.chain_config.chain_id) });
        try metadata_obj.put("function", std.json.Value{ .string = function_name });
        if (tx_request.gas) |gas| {
            try metadata_obj.put("gas", std.json.Value{ .integer = @intCast(gas) });
        }

        return Transaction{
            .chain = .evm,
            .from = tx_request.from,
            .to = tx_request.to,
            .value = if (tx_request.value) |v| @intCast(std.fmt.parseInt(u64, v, 0) catch 0) else null,
            .data = tx_data,
            .metadata = std.json.Value{ .object = metadata_obj },
        };
    }

    fn readOnchainDataImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        query: DataQuery,
    ) anyerror![]const u8 {
        const self: *EvmProvider = @ptrCast(@alignCast(ctx));

        switch (query.query_type) {
            .account_info => {
                // Get ETH balance
                const balance = try self.rpc_client.ethGetBalance(query.address, .latest);
                return try allocator.dupe(u8, balance);
            },
            .contract_data => {
                // Call contract view function (requires more params in query)
                return error.NotImplemented;
            },
            else => {
                return error.UnsupportedQueryType;
            },
        }
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *EvmProvider = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};

// Tests
const testing = std.testing;

test "EvmProvider initialization from chain name" {
    const provider = try EvmProvider.initFromChainName(testing.allocator, "bsc");
    defer provider.deinit();

    try testing.expectEqual(@as(u64, 56), provider.chain_config.chain_id);
    try testing.expectEqualStrings("BSC", provider.chain_config.name);
}

test "EvmProvider initialization from chain ID" {
    const provider = try EvmProvider.initFromChainId(testing.allocator, 1);
    defer provider.deinit();

    try testing.expectEqual(@as(u64, 1), provider.chain_config.chain_id);
    try testing.expectEqualStrings("Ethereum", provider.chain_config.name);
}
