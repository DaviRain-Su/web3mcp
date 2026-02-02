const std = @import("std");
const mcp = @import("mcp");
const chain_provider = @import("../../core/chain_provider.zig");
const idl_resolver = @import("./idl_resolver.zig");
const tool_generator = @import("./tool_generator.zig");
const transaction_builder = @import("./transaction_builder.zig");

const ChainProvider = chain_provider.ChainProvider;
const ChainType = chain_provider.ChainType;
const ContractMeta = chain_provider.ContractMeta;
const FunctionCall = chain_provider.FunctionCall;
const Transaction = chain_provider.Transaction;
const DataQuery = chain_provider.DataQuery;

/// Solana-specific provider implementation
pub const SolanaProvider = struct {
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    idl_cache: std.StringHashMap(ContractMeta),
    resolver: idl_resolver.IdlResolver,

    /// Initialize Solana provider
    pub fn init(allocator: std.mem.Allocator, rpc_url: []const u8, io: *const std.Io) !*SolanaProvider {
        const self = try allocator.create(SolanaProvider);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .rpc_url = rpc_url,
            .idl_cache = std.StringHashMap(ContractMeta).init(allocator),
            .resolver = try idl_resolver.IdlResolver.init(allocator, rpc_url, io),
        };

        return self;
    }

    /// Convert to ChainProvider interface
    pub fn asChainProvider(self: *SolanaProvider) ChainProvider {
        return .{
            .chain_type = .solana,
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
    ) anyerror!ContractMeta {
        const self: *SolanaProvider = @ptrCast(@alignCast(ctx));

        // Check cache first
        if (self.idl_cache.get(address)) |cached| {
            return cached;
        }

        // Resolve IDL using resolver
        const meta = try self.resolver.resolve(allocator, address);

        // Cache the result
        try self.idl_cache.put(address, meta);

        return meta;
    }

    fn generateToolsImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        meta: *const ContractMeta,
    ) anyerror![]mcp.tools.Tool {
        _ = ctx; // Provider context not needed for tool generation

        return tool_generator.generateTools(allocator, meta);
    }

    fn buildTransactionImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        call: FunctionCall,
    ) anyerror!Transaction {
        // Get contract metadata
        const meta = try getContractMetaImpl(ctx, allocator, call.contract);

        // Build transaction using transaction builder
        return transaction_builder.buildTransaction(allocator, &meta, call);
    }

    fn readOnchainDataImpl(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        query: DataQuery,
    ) anyerror![]const u8 {
        const self: *SolanaProvider = @ptrCast(@alignCast(ctx));

        // Implement different query types
        switch (query.query_type) {
            .account_info => {
                return try self.getAccountData(allocator, query.address);
            },
            .program_account => {
                // TODO: Implement program account query
                return error.NotImplemented;
            },
            else => {
                return error.UnsupportedQueryType;
            },
        }
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *SolanaProvider = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    // Helper methods

    fn getAccountData(
        self: *SolanaProvider,
        allocator: std.mem.Allocator,
        address: []const u8,
    ) ![]const u8 {
        // Build RPC request to get account info
        const request_body = try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"2.0","id":1,"method":"getAccountInfo","params":["{s}",{{"encoding":"base64"}}]}}
        , .{address});
        defer allocator.free(request_body);

        // Make RPC call
        // TODO: Implement actual RPC call using http_utils
        _ = self.rpc_url;

        // For now, return placeholder
        return error.NotImplemented;
    }

    pub fn deinit(self: *SolanaProvider) void {
        // Clean up cache
        var it = self.idl_cache.valueIterator();
        while (it.next()) |meta_ptr| {
            var meta = meta_ptr.*;
            meta.deinit(self.allocator);
        }
        self.idl_cache.deinit();

        // Clean up resolver
        self.resolver.deinit();

        // Free self
        self.allocator.destroy(self);
    }
};

// Unit tests
test "SolanaProvider init and deinit" {
    const allocator = std.testing.allocator;
    const rpc_url = "https://api.mainnet-beta.solana.com";

    // Create minimal IO for testing
    var io: std.Io = undefined;

    const provider = try SolanaProvider.init(allocator, rpc_url, &io);
    defer provider.deinit();

    const chain_provider_interface = provider.asChainProvider();
    try std.testing.expectEqual(ChainType.solana, chain_provider_interface.chain_type);
}
