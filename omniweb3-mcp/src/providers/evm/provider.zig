const std = @import("std");
const chains = @import("./chains.zig");
const rpc_client = @import("./rpc_client.zig");
const transaction_builder = @import("./transaction_builder.zig");

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

    /// Initialize EVM provider for a specific chain
    pub fn init(allocator: std.mem.Allocator, chain_config: chains.ChainConfig) !*EvmProvider {
        const self = try allocator.create(EvmProvider);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .chain_config = chain_config,
            .rpc_client = try rpc_client.EvmRpcClient.init(allocator, chain_config),
            .tx_builder = transaction_builder.TransactionBuilder.init(allocator),
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
        self.allocator.destroy(self);
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
