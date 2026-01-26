const std = @import("std");
const chain_provider = @import("../../core/chain_provider.zig");
const ContractMeta = chain_provider.ContractMeta;
const FunctionCall = chain_provider.FunctionCall;
const Transaction = chain_provider.Transaction;

/// Build Solana transaction from function call
pub fn buildTransaction(
    allocator: std.mem.Allocator,
    meta: *const ContractMeta,
    call: FunctionCall,
) !Transaction {
    _ = allocator;
    _ = meta;
    _ = call;

    // TODO: Implement transaction building
    return error.NotImplemented;
}
