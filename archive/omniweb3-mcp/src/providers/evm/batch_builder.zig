//! EVM Batch Transaction Builder
//!
//! Provides functionality to build multiple transactions in a single call
//! with optimized gas estimation and cost calculation.

const std = @import("std");
const provider = @import("./provider.zig");
const gas_oracle = @import("./gas_oracle.zig");
const chain_provider = @import("../../core/chain_provider.zig");

const EvmProvider = provider.EvmProvider;
const GasOracle = gas_oracle.GasOracle;
const GasTier = gas_oracle.GasTier;
const Transaction = chain_provider.Transaction;
const FunctionCall = chain_provider.FunctionCall;

/// Batch transaction result
pub const BatchTransaction = struct {
    /// Array of built transactions
    transactions: []Transaction,

    /// Total estimated gas for all transactions
    total_gas_estimate: u64,

    /// Total estimated cost in wei
    total_cost_estimate: u64,

    /// Individual gas estimates for each transaction
    individual_gas: []u64,

    /// Individual cost estimates for each transaction
    individual_cost: []u64,

    /// Free allocated memory
    pub fn deinit(self: BatchTransaction, allocator: std.mem.Allocator) void {
        for (self.transactions) |tx| {
            allocator.free(tx.data);
            // Note: tx.metadata is managed by caller
        }
        allocator.free(self.transactions);
        allocator.free(self.individual_gas);
        allocator.free(self.individual_cost);
    }
};

/// Batch builder for constructing multiple transactions
pub const BatchBuilder = struct {
    allocator: std.mem.Allocator,
    evm_provider: *EvmProvider,
    gas_tier: GasTier = .standard,
    safety_margin: u8 = 20, // 20% safety margin

    /// Initialize batch builder
    pub fn init(
        allocator: std.mem.Allocator,
        evm_provider: *EvmProvider,
    ) BatchBuilder {
        return .{
            .allocator = allocator,
            .evm_provider = evm_provider,
        };
    }

    /// Set gas tier for all transactions in batch
    pub fn setGasTier(self: *BatchBuilder, tier: GasTier) void {
        self.gas_tier = tier;
    }

    /// Set safety margin percentage for gas estimates
    pub fn setSafetyMargin(self: *BatchBuilder, margin: u8) void {
        self.safety_margin = margin;
    }

    /// Build batch of transactions
    pub fn buildBatch(
        self: *BatchBuilder,
        calls: []const FunctionCall,
    ) !BatchTransaction {
        if (calls.len == 0) {
            return error.EmptyBatch;
        }

        // Allocate arrays
        var transactions = try self.allocator.alloc(Transaction, calls.len);
        errdefer {
            for (transactions[0..transactions.len]) |tx| {
                self.allocator.free(tx.data);
            }
            self.allocator.free(transactions);
        }

        var individual_gas = try self.allocator.alloc(u64, calls.len);
        errdefer self.allocator.free(individual_gas);

        var individual_cost = try self.allocator.alloc(u64, calls.len);
        errdefer self.allocator.free(individual_cost);

        // Initialize gas oracle
        var oracle = GasOracle.init(self.allocator, &self.evm_provider.rpc_client);

        // Get gas price for the tier
        const gas_price = try oracle.getGasPrice(self.gas_tier);

        var total_gas: u64 = 0;
        var total_cost: u64 = 0;

        // Build each transaction
        for (calls, 0..) |call, i| {
            // Build transaction
            const tx = try self.evm_provider.asChainProvider().buildTransaction(
                self.allocator,
                call,
            );
            errdefer self.allocator.free(tx.data);

            transactions[i] = tx;

            // Estimate gas for this transaction
            const tx_request = try self.buildTransactionRequest(call, tx);
            const gas_estimate = try oracle.estimateGas(tx_request, self.safety_margin);

            individual_gas[i] = gas_estimate.recommended_limit;

            // Calculate cost based on gas price
            const tx_cost = switch (gas_price) {
                .eip1559 => |eip| gas_estimate.recommended_limit * eip.max_fee_per_gas,
                .legacy => |leg| gas_estimate.recommended_limit * leg.gas_price,
            };

            individual_cost[i] = tx_cost;
            total_gas += gas_estimate.recommended_limit;
            total_cost += tx_cost;
        }

        return BatchTransaction{
            .transactions = transactions,
            .total_gas_estimate = total_gas,
            .total_cost_estimate = total_cost,
            .individual_gas = individual_gas,
            .individual_cost = individual_cost,
        };
    }

    /// Build batch with custom gas estimates
    pub fn buildBatchWithGas(
        self: *BatchBuilder,
        calls: []const FunctionCall,
        gas_limits: []const u64,
    ) !BatchTransaction {
        if (calls.len != gas_limits.len) {
            return error.MismatchedArrayLengths;
        }

        if (calls.len == 0) {
            return error.EmptyBatch;
        }

        var transactions = try self.allocator.alloc(Transaction, calls.len);
        errdefer {
            for (transactions[0..transactions.len]) |tx| {
                self.allocator.free(tx.data);
            }
            self.allocator.free(transactions);
        }

        var individual_gas = try self.allocator.alloc(u64, calls.len);
        errdefer self.allocator.free(individual_gas);

        var individual_cost = try self.allocator.alloc(u64, calls.len);
        errdefer self.allocator.free(individual_cost);

        var oracle = GasOracle.init(self.allocator, &self.evm_provider.rpc_client);
        const gas_price = try oracle.getGasPrice(self.gas_tier);

        var total_gas: u64 = 0;
        var total_cost: u64 = 0;

        for (calls, 0..) |call, i| {
            const tx = try self.evm_provider.asChainProvider().buildTransaction(
                self.allocator,
                call,
            );
            errdefer self.allocator.free(tx.data);

            transactions[i] = tx;
            individual_gas[i] = gas_limits[i];

            const tx_cost = switch (gas_price) {
                .eip1559 => |eip| gas_limits[i] * eip.max_fee_per_gas,
                .legacy => |leg| gas_limits[i] * leg.gas_price,
            };

            individual_cost[i] = tx_cost;
            total_gas += gas_limits[i];
            total_cost += tx_cost;
        }

        return BatchTransaction{
            .transactions = transactions,
            .total_gas_estimate = total_gas,
            .total_cost_estimate = total_cost,
            .individual_gas = individual_gas,
            .individual_cost = individual_cost,
        };
    }

    /// Helper to build TransactionRequest from FunctionCall and Transaction
    fn buildTransactionRequest(
        self: *BatchBuilder,
        call: FunctionCall,
        tx: Transaction,
    ) !@import("./rpc_client.zig").TransactionRequest {
        return .{
            .from = call.signer,
            .to = tx.to,
            .data = tx.data,
            .value = if (tx.value) |v| blk: {
                const hex = try std.fmt.allocPrint(self.allocator, "0x{x}", .{v});
                break :blk hex;
            } else null,
        };
    }
};

// Tests
const testing = std.testing;

test "BatchTransaction basic structure" {
    const allocator = testing.allocator;

    var txs = try allocator.alloc(Transaction, 2);
    defer allocator.free(txs);

    const data1 = try allocator.dupe(u8, "0x1234");
    const data2 = try allocator.dupe(u8, "0x5678");

    txs[0] = Transaction{
        .chain = .evm,
        .from = "0xabc",
        .to = "0xdef",
        .value = null,
        .data = data1,
        .metadata = undefined,
    };

    txs[1] = Transaction{
        .chain = .evm,
        .from = "0x123",
        .to = "0x456",
        .value = null,
        .data = data2,
        .metadata = undefined,
    };

    var gas = try allocator.alloc(u64, 2);
    defer allocator.free(gas);
    gas[0] = 21000;
    gas[1] = 50000;

    var cost = try allocator.alloc(u64, 2);
    defer allocator.free(cost);
    cost[0] = 21000 * 20_000_000_000; // 20 gwei
    cost[1] = 50000 * 20_000_000_000;

    const batch = BatchTransaction{
        .transactions = txs,
        .total_gas_estimate = 71000,
        .total_cost_estimate = cost[0] + cost[1],
        .individual_gas = gas,
        .individual_cost = cost,
    };

    try testing.expectEqual(@as(usize, 2), batch.transactions.len);
    try testing.expectEqual(@as(u64, 71000), batch.total_gas_estimate);
    try testing.expectEqual(@as(u64, 21000), batch.individual_gas[0]);
    try testing.expectEqual(@as(u64, 50000), batch.individual_gas[1]);

    batch.deinit(allocator);
}

test "BatchBuilder initialization" {
    const allocator = testing.allocator;

    // Note: Can't create actual EvmProvider in test without chain config
    // This just tests the structure
    var dummy_ptr: usize = 0;
    const provider_ptr: *EvmProvider = @ptrFromInt(@intFromPtr(&dummy_ptr));

    const builder = BatchBuilder.init(allocator, provider_ptr);

    try testing.expectEqual(GasTier.standard, builder.gas_tier);
    try testing.expectEqual(@as(u8, 20), builder.safety_margin);
}
