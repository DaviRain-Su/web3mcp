const std = @import("std");

pub const ChainType = enum { solana, evm, cosmos, polkadot, btc, move, unknown };

pub const ChainId = enum(u32) {
    // Solana family
    solana_mainnet = 101,
    solana_devnet = 102,

    // EVM examples
    eth_mainnet = 1,
    avalanche_c = 43114,
    avalanche_fuji = 43113,
    bnb_mainnet = 56,
    bnb_testnet = 97,

    // Extend for others
    unknown = 0,
};

pub const Address = union(ChainType) {
    solana: [32]u8,
    evm: [20]u8,
    cosmos: []const u8,
    polkadot: []const u8,
    btc: []const u8,
    move: []const u8,
    unknown: []const u8,
};

pub const TxHash = []const u8;

pub const TxStatus = enum { pending, confirmed, failed, unknown };

pub const ChainAdapter = struct {
    const Self = @This();

    vtable: *const VTable,
    ptr: *anyopaque,

    pub const VTable = struct {
        get_balance: *const fn (*anyopaque, Address) anyerror!u256,
        get_token_balance: *const fn (*anyopaque, Address, Address) anyerror!u256,
        build_transfer: *const fn (*anyopaque, TransferParams) anyerror!Transaction,
        sign_transaction: *const fn (*anyopaque, Transaction, anytype) anyerror!SignedTransaction,
        send_transaction: *const fn (*anyopaque, SignedTransaction) anyerror!TxHash,
        get_transaction_status: *const fn (*anyopaque, TxHash) anyerror!TxStatus,
        estimate_gas: *const fn (*anyopaque, Transaction) anyerror!u64,
        get_chain_id: *const fn (*anyopaque) ChainId,
        get_chain_type: *const fn (*anyopaque) ChainType,
        get_block_height: *const fn (*anyopaque) anyerror!u64,
    };

    pub fn getBalance(self: Self, addr: Address) !u256 {
        return self.vtable.get_balance(self.ptr, addr);
    }
};

pub const TransferParams = struct {
    to: Address,
    amount: u256,
};

pub const Transaction = struct {
    chain: ChainId,
    from: Address,
    to: Address,
    value: u256,
    data: []const u8,
    chain_specific: ChainSpecific,
};

pub const ChainSpecific = union(ChainType) {
    solana: SolanaSpecific,
    evm: EvmSpecific,
    cosmos: CosmosSpecific,
    polkadot: PolkadotSpecific,
    btc: BtcSpecific,
    move: MoveSpecific,
    unknown: void,
};

pub const SolanaSpecific = struct {
    recent_blockhash: [32]u8,
    instructions: []const u8,
};

pub const EvmSpecific = struct {
    nonce: u64,
    gas_limit: u64,
    max_fee_per_gas: u256,
    max_priority_fee: u256,
    chain_id: u64,
};

pub const CosmosSpecific = struct { _unused: u8 = 0 };
pub const PolkadotSpecific = struct { _unused: u8 = 0 };
pub const BtcSpecific = struct { _unused: u8 = 0 };
pub const MoveSpecific = struct { _unused: u8 = 0 };
pub const SignedTransaction = struct { raw: []const u8 };
