const std = @import("std");
const zabi = @import("zabi");
const evm_helpers = @import("../evm_helpers.zig");

const HttpProvider = zabi.clients.Provider.HttpProvider;
const Wallet = zabi.clients.Wallet;
const block = zabi.types.block;
const transaction = zabi.types.transactions;
const EthCall = zabi.types.transactions.EthCall;
const Transaction = zabi.types.transactions.Transaction;
const TransactionTypes = zabi.types.transactions.TransactionTypes;
const UnpreparedTransactionEnvelope = zabi.types.transactions.UnpreparedTransactionEnvelope;
const TransactionReceipt = zabi.types.transactions.TransactionReceipt;
const FeeHistory = zabi.types.transactions.FeeHistory;
const Logs = zabi.types.log.Logs;
const LogRequest = zabi.types.log.LogRequest;
const Address = zabi.types.ethereum.Address;
const Hash = zabi.types.ethereum.Hash;
const Hex = zabi.types.ethereum.Hex;
const RPCResponse = zabi.types.ethereum.RPCResponse;
const Wei = zabi.types.ethereum.Wei;
const serialize = zabi.encoding.serialize;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

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

    fn sendTransactionHash(
        self: *EvmAdapter,
        wallet: *Wallet,
        envelope: UnpreparedTransactionEnvelope,
    ) !Hash {
        const tx_hash_response = wallet.sendTransaction(envelope) catch |err| {
            if (err == error.UnexpectedErrorFound) {
                std.log.warn("wallet.sendTransaction returned UnexpectedErrorFound; retrying with raw RPC", .{});
                return self.sendSignedTransactionRaw(wallet, envelope);
            }
            return err;
        };
        defer tx_hash_response.deinit();
        return tx_hash_response.response;
    }

    fn sendSignedTransactionRaw(
        self: *EvmAdapter,
        wallet: *Wallet,
        envelope: UnpreparedTransactionEnvelope,
    ) !Hash {
        // Manually construct prepared envelope to avoid prepareTransaction issues with BSC testnet
        const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
        const TransactionEnvelope = transaction.TransactionEnvelope;

        const prepared = switch (envelope.type) {
            .legacy => TransactionEnvelope{ .legacy = LegacyTransactionEnvelope{
                .chainId = envelope.chainId orelse @intFromEnum(wallet.rpc_client.network_config.chain_id),
                .nonce = envelope.nonce orelse 0,
                .gasPrice = envelope.gasPrice orelse 0,
                .gas = envelope.gas orelse 0,
                .to = envelope.to,
                .value = envelope.value orelse 0,
                .data = envelope.data,
            } },
            else => return error.UnsupportedTransactionType,
        };

        try wallet.assertTransaction(prepared);

        const serialized = try serialize.serializeTransaction(self.allocator, prepared, null);
        defer self.allocator.free(serialized);

        var hash_buffer: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(serialized, &hash_buffer, .{});

        const signature = try wallet.signer.sign(hash_buffer);
        const serialized_signed = try serialize.serializeTransaction(self.allocator, prepared, signature);
        defer self.allocator.free(serialized_signed);

        const raw_hex = try hexEncodePrefixed(self.allocator, serialized_signed);
        defer self.allocator.free(raw_hex);

        return self.sendRawTransactionHex(raw_hex);
    }

    fn sendRawTransactionHex(self: *EvmAdapter, raw_hex: []const u8) !Hash {
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"eth_sendRawTransaction\",\"params\":[\"{s}\"]}}",
            .{ @intFromEnum(self.provider.provider.network_config.chain_id), raw_hex },
        );
        defer self.allocator.free(request_json);

        const response = try self.provider.provider.vtable.sendRpcRequest(&self.provider.provider, request_json);
        defer response.deinit();

        if (response.value != .object) return error.InvalidRpcResponse;

        const obj = response.value.object;
        if (obj.get("result")) |value| {
            if (value == .string) {
                return evm_helpers.parseHash(value.string);
            }
            return error.InvalidRpcResponse;
        }

        if (obj.get("error")) |err_value| {
            if (err_value == .object) {
                const err_obj = err_value.object;
                const message = if (err_obj.get("message")) |msg|
                    if (msg == .string) msg.string else "RPC error"
                else
                    "RPC error";

                if (err_obj.get("data")) |data_value| {
                    const data_string = evm_helpers.jsonStringifyAlloc(self.allocator, data_value) catch null;
                    if (data_string) |data| {
                        defer self.allocator.free(data);
                        std.log.err("RPC error: {s} data={s}", .{ message, data });
                    } else {
                        std.log.err("RPC error: {s}", .{message});
                    }
                } else {
                    std.log.err("RPC error: {s}", .{message});
                }
            } else {
                std.log.err("RPC error: unexpected error payload", .{});
            }
            return error.RpcSendFailed;
        }

        return error.InvalidRpcResponse;
    }

    fn hexEncodePrefixed(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
        const hex_len = bytes.len * 2;
        var out = try allocator.alloc(u8, hex_len + 2);
        errdefer allocator.free(out);

        out[0] = '0';
        out[1] = 'x';

        const charset = "0123456789abcdef";
        var idx: usize = 2;
        for (bytes) |b| {
            out[idx] = charset[b >> 4];
            out[idx + 1] = charset[b & 0x0f];
            idx += 2;
        }

        return out;
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

    pub fn getChainId(self: *EvmAdapter) !usize {
        const response = try self.provider.provider.getChainId();
        defer response.deinit();
        return response.response;
    }

    pub fn getFeeHistory(
        self: *EvmAdapter,
        block_count: u64,
        newest_block: block.BlockNumberRequest,
        reward_percentiles: ?[]const f64,
    ) !RPCResponse(FeeHistory) {
        return self.provider.provider.feeHistory(block_count, newest_block, reward_percentiles);
    }

    pub fn getLogs(self: *EvmAdapter, request: LogRequest, tag: ?block.BalanceBlockTag) !RPCResponse(Logs) {
        return self.provider.provider.getLogs(request, tag);
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

        const tx_hash = try self.sendTransactionHash(&wallet, envelope);

        var result: TransferResult = .{ .tx_hash = tx_hash };
        if (confirmations > 0) {
            const receipt_response = try self.provider.provider.waitForTransactionReceipt(tx_hash, confirmations);
            defer receipt_response.deinit();
            result.receipt = receipt_response.response;
        }

        return result;
    }

    pub fn sendContractCall(
        self: *EvmAdapter,
        private_key: Hash,
        from: Address,
        to: Address,
        data: []const u8,
        value: Wei,
        tx_type: TransactionTypes,
        confirmations: u8,
    ) !TransferResult {
        std.log.info("Initializing wallet for contract call", .{});
        var wallet = try Wallet.init(private_key, self.allocator, &self.provider.provider, false);
        defer wallet.deinit();

        const tx_call = switch (tx_type) {
            .legacy => EthCall{ .legacy = .{ .from = from, .to = to, .value = value, .data = @constCast(data) } },
            else => EthCall{ .london = .{ .from = from, .to = to, .value = value, .data = @constCast(data) } },
        };

        const gas_estimate = try self.provider.provider.estimateGas(tx_call, .{});
        defer gas_estimate.deinit();

        // Get chain ID for transaction signing
        const chain_id_response = try self.provider.provider.getChainId();
        defer chain_id_response.deinit();
        const chain_id = chain_id_response.response;
        std.log.info("Chain ID: {}", .{chain_id});

        // Get nonce
        const nonce_response = try self.provider.provider.getAddressTransactionCount(.{
            .address = from,
            .tag = .pending,
        });
        defer nonce_response.deinit();
        const nonce = nonce_response.response;
        std.log.info("Nonce: {}", .{nonce});

        // Get gas price for legacy transactions
        const gas_price = if (tx_type == .legacy) blk: {
            const gas_price_response = try self.provider.provider.getGasPrice();
            defer gas_price_response.deinit();
            break :blk gas_price_response.response;
        } else 0;

        std.log.info("Transaction params: gas={}, gasPrice={}, value={}, nonce={}, chainId={}", .{
            gas_estimate.response,
            gas_price,
            value,
            nonce,
            chain_id,
        });

        const envelope = switch (tx_type) {
            .legacy => blk: {
                break :blk UnpreparedTransactionEnvelope{
                    .type = TransactionTypes.legacy,
                    .to = to,
                    .value = value,
                    .data = @constCast(data),
                    .gas = gas_estimate.response,
                    .gasPrice = gas_price,
                    .chainId = chain_id,
                    .nonce = nonce,
                };
            },
            else => blk: {
                const fee_estimate = try self.provider.provider.estimateFeesPerGas(tx_call, null);
                break :blk UnpreparedTransactionEnvelope{
                    .type = TransactionTypes.london,
                    .to = to,
                    .value = value,
                    .data = @constCast(data),
                    .gas = gas_estimate.response,
                    .maxPriorityFeePerGas = fee_estimate.london.max_priority_fee,
                    .maxFeePerGas = fee_estimate.london.max_fee_gas,
                };
            },
        };

        std.log.info("Sending transaction via wallet.sendTransaction...", .{});
        const tx_hash = self.sendTransactionHash(&wallet, envelope) catch |err| {
            std.log.err("wallet.sendTransaction failed: {}", .{err});
            return err;
        };
        std.log.info("Transaction sent: hash=0x{x}", .{tx_hash});

        var result: TransferResult = .{ .tx_hash = tx_hash };
        if (confirmations > 0) {
            const receipt_response = try self.provider.provider.waitForTransactionReceipt(tx_hash, confirmations);
            defer receipt_response.deinit();
            result.receipt = receipt_response.response;
        }

        return result;
    }
};
