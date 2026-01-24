const std = @import("std");
const zabi = @import("zabi");
const evm_helpers = @import("../evm_helpers.zig");

const HttpProvider = zabi.clients.Provider.HttpProvider;
const Wallet = zabi.clients.Wallet;
const Provider = zabi.clients.Provider.Provider;
const block = zabi.types.block;
const EthCall = zabi.types.transactions.EthCall;
const Transaction = zabi.types.transactions.Transaction;
const TransactionTypes = zabi.types.transactions.TransactionTypes;
const UnpreparedTransactionEnvelope = zabi.types.transactions.UnpreparedTransactionEnvelope;
const TransactionReceipt = zabi.types.transactions.TransactionReceipt;
const Address = zabi.types.ethereum.Address;
const Hash = zabi.types.ethereum.Hash;
const Hex = zabi.types.ethereum.Hex;
const RPCResponse = zabi.types.ethereum.RPCResponse;
const Wei = zabi.types.ethereum.Wei;

pub const TransferResult = struct {
    tx_hash: Hash,
    receipt: ?TransactionReceipt = null,
};

pub const EvmAdapter = struct {
    allocator: std.mem.Allocator,
    provider: HttpProvider,
    endpoint: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        chain: []const u8,
        network: []const u8,
        endpoint_override: ?[]const u8,
    ) !EvmAdapter {
        const config_result = try evm_helpers.resolveNetworkConfig(allocator, chain, network, endpoint_override);
        errdefer allocator.free(config_result.endpoint);

        const provider = try HttpProvider.init(.{
            .allocator = allocator,
            .io = io,
            .network_config = config_result.config,
        });

        return .{
            .allocator = allocator,
            .provider = provider,
            .endpoint = config_result.endpoint,
        };
    }

    pub fn deinit(self: *EvmAdapter) void {
        self.provider.deinit();
        self.allocator.free(self.endpoint);
    }

    pub fn getBalance(self: *EvmAdapter, address: Address) !u256 {
        const response = try self.provider.provider.getAddressBalance(.{ .address = address });
        defer response.deinit();
        return response.response;
    }

    pub fn getGasPrice(self: *EvmAdapter) !u64 {
        const response = try self.provider.provider.getGasPrice();
        defer response.deinit();
        return response.response;
    }

    pub fn estimateGas(self: *EvmAdapter, eth_call: EthCall) !u64 {
        const response = try self.provider.provider.estimateGas(eth_call, .{});
        defer response.deinit();
        return response.response;
    }

    pub fn getBlockNumber(self: *EvmAdapter) !u64 {
        const response = try self.provider.provider.getBlockNumber();
        defer response.deinit();
        return response.response;
    }

    pub fn getBlockByNumber(self: *EvmAdapter, request: block.BlockRequest) !RPCResponse(block.Block) {
        return self.provider.provider.getBlockByNumber(request);
    }

    pub fn getBlockByHash(self: *EvmAdapter, request: block.BlockHashRequest) !RPCResponse(block.Block) {
        return self.provider.provider.getBlockByHash(request);
    }

    pub fn getTransactionByHash(self: *EvmAdapter, hash: Hash) !RPCResponse(Transaction) {
        return self.provider.provider.getTransactionByHash(hash);
    }

    pub fn getTransactionReceipt(self: *EvmAdapter, hash: Hash) !RPCResponse(TransactionReceipt) {
        return self.provider.provider.getTransactionReceipt(hash);
    }

    pub fn getTransactionCount(self: *EvmAdapter, request: block.BalanceRequest) !u64 {
        const response = try self.provider.provider.getAddressTransactionCount(request);
        defer response.deinit();
        return response.response;
    }

    pub fn call(self: *EvmAdapter, eth_call: EthCall, request: block.BlockNumberRequest) !RPCResponse(Hex) {
        return self.provider.provider.sendEthCall(eth_call, request);
    }

    pub fn sendTransfer(
        self: *EvmAdapter,
        private_key: Hash,
        from: Address,
        to: Address,
        amount: Wei,
        tx_type: TransactionTypes,
        confirmations: u8,
    ) !TransferResult {
        var wallet = try Wallet.init(private_key, self.allocator, &self.provider.provider, false);
        defer wallet.deinit();

        const tx_call = switch (tx_type) {
            .legacy => EthCall{ .legacy = .{ .from = from, .to = to, .value = amount } },
            else => EthCall{ .london = .{ .from = from, .to = to, .value = amount } },
        };

        const gas_estimate = try self.provider.provider.estimateGas(tx_call, .{});
        defer gas_estimate.deinit();

        const envelope = switch (tx_type) {
            .legacy => blk: {
                const fee_estimate = try self.provider.provider.estimateFeesPerGas(tx_call, null);
                break :blk UnpreparedTransactionEnvelope{
                    .type = TransactionTypes.legacy,
                    .to = to,
                    .value = amount,
                    .gas = gas_estimate.response,
                    .gasPrice = fee_estimate.legacy.gas_price,
                };
            },
            else => blk: {
                const fee_estimate = try self.provider.provider.estimateFeesPerGas(tx_call, null);
                break :blk UnpreparedTransactionEnvelope{
                    .type = TransactionTypes.london,
                    .to = to,
                    .value = amount,
                    .gas = gas_estimate.response,
                    .maxPriorityFeePerGas = fee_estimate.london.max_priority_fee,
                    .maxFeePerGas = fee_estimate.london.max_fee_gas,
                };
            },
        };

        const tx_hash_response = try wallet.sendTransaction(envelope);
        defer tx_hash_response.deinit();

        var result: TransferResult = .{ .tx_hash = tx_hash_response.response };
        if (confirmations > 0) {
            const receipt_response = try self.provider.provider.waitForTransactionReceipt(tx_hash_response.response, confirmations);
            defer receipt_response.deinit();
            result.receipt = receipt_response.response;
        }

        return result;
    }
};
