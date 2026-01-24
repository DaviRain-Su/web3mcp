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
const TokenAccountFilter = solana_client.RpcClient.TokenAccountFilter;
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

    pub fn sendTransaction(self: *SolanaAdapter, transaction: []const u8) !Signature {
        return self.client.sendTransactionWithConfig(transaction, .{ .skip_preflight = true });
    }
};
