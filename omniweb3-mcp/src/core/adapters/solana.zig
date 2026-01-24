const std = @import("std");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../solana_helpers.zig");

const RpcClient = solana_client.RpcClient;
const PublicKey = solana_sdk.PublicKey;
const Signature = solana_sdk.Signature;
const AccountInfo = solana_client.AccountInfo;
const TransactionStatus = solana_client.TransactionStatus;
const TransactionWithMeta = solana_client.types.TransactionWithMeta;
const TokenBalance = solana_client.types.TokenBalance;
const TokenAccount = solana_client.types.TokenAccount;
const Block = solana_client.types.Block;
const PerformanceSample = solana_client.types.PerformanceSample;
const SignatureInfo = solana_client.types.SignatureInfo;
const TokenSupply = solana_client.types.TokenSupply;
const TokenLargestAccount = solana_client.types.TokenLargestAccount;
const Supply = solana_client.types.Supply;
const RpcVersionInfo = solana_client.types.RpcVersionInfo;
const ProgramAccount = solana_client.types.ProgramAccount;
const VoteAccounts = solana_client.types.VoteAccounts;
const TokenAccountFilter = solana_client.RpcClient.TokenAccountFilter;
const GetBlockConfig = solana_client.RpcClient.GetBlockConfig;
const TOKEN_PROGRAM_ID = solana_sdk.spl.token.instruction.TOKEN_PROGRAM_ID;

pub const SolanaAdapter = struct {
    allocator: std.mem.Allocator,
    client: RpcClient,
    endpoint: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        network: []const u8,
        endpoint_override: ?[]const u8,
    ) !SolanaAdapter {
        const endpoint_value = endpoint_override orelse solana_helpers.resolveEndpoint(network);
        const endpoint = try allocator.dupe(u8, endpoint_value);

        return .{
            .allocator = allocator,
            .client = RpcClient.init(allocator, endpoint),
            .endpoint = endpoint,
        };
    }

    pub fn deinit(self: *SolanaAdapter) void {
        self.client.deinit();
        self.allocator.free(self.endpoint);
    }

    pub fn getBalance(self: *SolanaAdapter, pubkey: PublicKey) !u64 {
        return self.client.getBalance(pubkey);
    }

    pub fn getAccountInfo(self: *SolanaAdapter, pubkey: PublicKey) !?AccountInfo {
        return self.client.getAccountInfo(pubkey);
    }

    pub fn getSignatureStatus(self: *SolanaAdapter, signature: Signature) !?TransactionStatus {
        const statuses = try self.client.getSignatureStatusesWithHistory(&.{signature});
        defer self.allocator.free(statuses);

        return if (statuses.len > 0) statuses[0] else null;
    }

    pub fn getTransaction(self: *SolanaAdapter, signature: Signature) !?TransactionWithMeta {
        return self.client.getTransaction(signature);
    }

    pub fn getTokenAccountBalance(self: *SolanaAdapter, token_account: PublicKey) !TokenBalance {
        return self.client.getTokenAccountBalance(token_account);
    }

    pub fn getTokenAccountsByOwner(
        self: *SolanaAdapter,
        owner: PublicKey,
        mint: ?PublicKey,
    ) ![]TokenAccount {
        const filter: TokenAccountFilter = if (mint) |mint_pubkey| blk: {
            break :blk .{ .mint = mint_pubkey };
        } else blk: {
            break :blk .{ .program_id = TOKEN_PROGRAM_ID };
        };

        return self.client.getTokenAccountsByOwner(owner, filter);
    }

    pub fn getLatestBlockhash(self: *SolanaAdapter) !solana_client.LatestBlockhash {
        return self.client.getLatestBlockhash();
    }

    pub fn getMinimumBalanceForRentExemption(self: *SolanaAdapter, data_len: usize) !u64 {
        return self.client.getMinimumBalanceForRentExemption(data_len);
    }

    pub fn getFeeForMessage(self: *SolanaAdapter, message: []const u8) !?u64 {
        return self.client.getFeeForMessage(message);
    }

    pub fn getProgramAccounts(self: *SolanaAdapter, program_id: PublicKey) ![]ProgramAccount {
        return self.client.getProgramAccounts(program_id);
    }

    pub fn getVoteAccounts(self: *SolanaAdapter) !VoteAccounts {
        return self.client.getVoteAccounts();
    }

    pub fn getSlot(self: *SolanaAdapter) !u64 {
        return self.client.getSlot();
    }

    pub fn getBlockHeight(self: *SolanaAdapter) !u64 {
        return self.client.getBlockHeight();
    }

    pub fn getBlock(self: *SolanaAdapter, slot: u64, include_transactions: bool) !?Block {
        const config: GetBlockConfig = .{
            .transaction_details = if (include_transactions) "full" else "none",
            .rewards = true,
            .max_supported_transaction_version = 0,
        };
        return self.client.getBlockWithConfig(slot, config);
    }

    pub fn getBlockTime(self: *SolanaAdapter, slot: u64) !?i64 {
        return self.client.getBlockTime(slot);
    }

    pub fn getEpochInfo(self: *SolanaAdapter) !solana_sdk.EpochInfo {
        return self.client.getEpochInfo();
    }

    pub fn getVersion(self: *SolanaAdapter) !RpcVersionInfo {
        return self.client.getVersion();
    }

    pub fn getSupply(self: *SolanaAdapter) !Supply {
        return self.client.getSupply();
    }

    pub fn getSignaturesForAddress(
        self: *SolanaAdapter,
        address: PublicKey,
        limit: ?u32,
        before: ?Signature,
        until: ?Signature,
    ) ![]SignatureInfo {
        return self.client.getSignaturesForAddressWithConfig(address, .{
            .limit = limit,
            .before = before,
            .until = until,
        });
    }

    pub fn getTokenSupply(self: *SolanaAdapter, mint: PublicKey) !TokenSupply {
        return self.client.getTokenSupply(mint);
    }

    pub fn getTokenLargestAccounts(self: *SolanaAdapter, mint: PublicKey) ![]TokenLargestAccount {
        return self.client.getTokenLargestAccounts(mint);
    }

    pub fn requestAirdrop(self: *SolanaAdapter, pubkey: PublicKey, lamports: u64) !Signature {
        return self.client.requestAirdrop(pubkey, lamports);
    }

    pub fn getRecentPerformanceSamples(self: *SolanaAdapter, limit: ?u64) ![]PerformanceSample {
        return self.client.getRecentPerformanceSamples(limit);
    }

    pub fn sendTransaction(self: *SolanaAdapter, transaction: []const u8) !Signature {
        return self.client.sendTransactionWithConfig(transaction, .{ .skip_preflight = true });
    }
};
