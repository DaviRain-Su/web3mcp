//! Unified Wallet Provider Abstraction
//!
//! Provides a unified interface for signing transactions with either:
//! - Local keypair (from file or environment variable)
//! - Privy embedded wallet (via REST API)
//!
//! Usage:
//! 1. For Solana transactions:
//!    - wallet_type=local + keypair_path → sign locally with keypair
//!    - wallet_type=privy + wallet_id → sign via Privy API
//!
//! 2. For EVM transactions:
//!    - wallet_type=local + private_key → sign locally
//!    - wallet_type=privy + wallet_id → sign via Privy API

const std = @import("std");
const solana_sdk = @import("solana_sdk");
const wallet = @import("wallet.zig");
const privy_client = @import("../tools/auth/privy/client.zig");

const Keypair = solana_sdk.Keypair;

/// Wallet provider type
pub const WalletType = enum {
    local,
    privy,

    pub fn fromString(s: []const u8) ?WalletType {
        if (std.mem.eql(u8, s, "local")) return .local;
        if (std.mem.eql(u8, s, "privy")) return .privy;
        return null;
    }
};

/// Chain type for signing context
pub const ChainType = enum {
    solana,
    ethereum,

    pub fn fromString(s: []const u8) ?ChainType {
        if (std.mem.eql(u8, s, "solana")) return .solana;
        if (std.mem.eql(u8, s, "ethereum")) return .ethereum;
        if (std.mem.eql(u8, s, "evm")) return .ethereum;
        return null;
    }
};

/// Wallet configuration for signing operations
pub const WalletConfig = struct {
    wallet_type: WalletType,
    chain: ChainType,

    // Local wallet options
    keypair_path: ?[]const u8 = null, // Solana keypair file path
    private_key: ?[]const u8 = null, // EVM private key (hex)

    // Privy wallet options
    wallet_id: ?[]const u8 = null, // Privy wallet ID
    network: []const u8 = "devnet", // Network for Privy signing
    sponsor: bool = false, // Enable gas sponsorship (Privy)
};

/// Result of a signing operation
pub const SignResult = struct {
    /// Signed transaction (base64 for Solana, hex for EVM)
    signed_transaction: []const u8,
    /// Transaction signature/hash (if available after send)
    signature: ?[]const u8 = null,
    /// Whether transaction was sent (true for sign_and_send)
    sent: bool = false,
};

/// Get the public address for a wallet configuration
pub fn getWalletAddress(
    allocator: std.mem.Allocator,
    config: WalletConfig,
) ![]const u8 {
    switch (config.wallet_type) {
        .local => {
            switch (config.chain) {
                .solana => {
                    const keypair = try wallet.loadSolanaKeypair(allocator, config.keypair_path);
                    var buf: [44]u8 = undefined;
                    const address = keypair.pubkey().toBase58(&buf);
                    return allocator.dupe(u8, address);
                },
                .ethereum => {
                    const private_key = try wallet.loadEvmPrivateKey(allocator, config.private_key, config.keypair_path);
                    const address = try wallet.deriveEvmAddress(private_key);
                    // Convert to hex string
                    var hex_buf: [42]u8 = undefined;
                    hex_buf[0] = '0';
                    hex_buf[1] = 'x';
                    const hex_part = std.fmt.bytesToHex(address, .lower);
                    @memcpy(hex_buf[2..], &hex_part);
                    return allocator.dupe(u8, &hex_buf);
                },
            }
        },
        .privy => {
            // For Privy, we need to fetch wallet info via API
            const wallet_id = config.wallet_id orelse return error.MissingWalletId;
            const path = try std.fmt.allocPrint(allocator, "/wallets/{s}", .{wallet_id});
            defer allocator.free(path);

            const response = try privy_client.privyGet(allocator, path);
            defer allocator.free(response);

            // Parse response to get address
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch {
                return error.ParseError;
            };
            defer parsed.deinit();

            if (parsed.value == .object) {
                if (parsed.value.object.get("address")) |addr| {
                    if (addr == .string) {
                        return allocator.dupe(u8, addr.string);
                    }
                }
            }
            return error.AddressNotFound;
        },
    }
}

/// Sign a Solana transaction (returns base64 signed transaction)
pub fn signSolanaTransaction(
    allocator: std.mem.Allocator,
    config: WalletConfig,
    unsigned_transaction_b64: []const u8,
) !SignResult {
    if (config.chain != .solana) return error.ChainMismatch;

    switch (config.wallet_type) {
        .local => {
            // Load keypair and sign locally
            const keypair = try wallet.loadSolanaKeypair(allocator, config.keypair_path);

            // Decode base64 transaction
            const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(unsigned_transaction_b64) catch {
                return error.InvalidBase64;
            };
            const tx_bytes = try allocator.alloc(u8, decoded_len);
            defer allocator.free(tx_bytes);

            std.base64.standard.Decoder.decode(tx_bytes, unsigned_transaction_b64) catch {
                return error.InvalidBase64;
            };

            // Parse and sign the transaction
            // Note: This is simplified - real implementation needs proper transaction parsing
            _ = keypair;

            // For now, return error indicating local signing needs more implementation
            return error.LocalSigningNotImplemented;
        },
        .privy => {
            // Sign via Privy API
            const wallet_id = config.wallet_id orelse return error.MissingWalletId;
            const caip2 = privy_client.SolanaNetwork.fromNetwork(config.network);

            const body = try std.fmt.allocPrint(
                allocator,
                "{{\"method\":\"signTransaction\",\"caip2\":\"{s}\",\"params\":{{\"transaction\":\"{s}\",\"encoding\":\"base64\"}}}}",
                .{ caip2, unsigned_transaction_b64 },
            );
            defer allocator.free(body);

            const path = try std.fmt.allocPrint(allocator, "/wallets/{s}/rpc", .{wallet_id});
            defer allocator.free(path);

            const response = try privy_client.privyPost(allocator, path, body);

            // Parse response to get signed transaction
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch {
                allocator.free(response);
                return error.ParseError;
            };
            defer parsed.deinit();
            allocator.free(response);

            if (parsed.value == .object) {
                if (parsed.value.object.get("data")) |data| {
                    if (data == .object) {
                        if (data.object.get("signedTransaction")) |signed| {
                            if (signed == .string) {
                                return SignResult{
                                    .signed_transaction = try allocator.dupe(u8, signed.string),
                                    .sent = false,
                                };
                            }
                        }
                    }
                }
            }
            return error.SigningFailed;
        },
    }
}

/// Sign and send a Solana transaction
pub fn signAndSendSolanaTransaction(
    allocator: std.mem.Allocator,
    config: WalletConfig,
    unsigned_transaction_b64: []const u8,
) !SignResult {
    if (config.chain != .solana) return error.ChainMismatch;

    switch (config.wallet_type) {
        .local => {
            // For local signing, we need to:
            // 1. Sign the transaction
            // 2. Send it via RPC
            // This requires more infrastructure - for now, suggest using Privy
            return error.LocalSignAndSendNotImplemented;
        },
        .privy => {
            // Sign and send via Privy API
            const wallet_id = config.wallet_id orelse return error.MissingWalletId;
            const caip2 = privy_client.SolanaNetwork.fromNetwork(config.network);
            const sponsor_str = if (config.sponsor) "true" else "false";

            const body = try std.fmt.allocPrint(
                allocator,
                "{{\"method\":\"signAndSendTransaction\",\"caip2\":\"{s}\",\"params\":{{\"transaction\":\"{s}\",\"encoding\":\"base64\"}},\"sponsor\":{s}}}",
                .{ caip2, unsigned_transaction_b64, sponsor_str },
            );
            defer allocator.free(body);

            const path = try std.fmt.allocPrint(allocator, "/wallets/{s}/rpc", .{wallet_id});
            defer allocator.free(path);

            const response = try privy_client.privyPost(allocator, path, body);

            // Parse response to get signature
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch {
                allocator.free(response);
                return error.ParseError;
            };
            defer parsed.deinit();
            allocator.free(response);

            if (parsed.value == .object) {
                if (parsed.value.object.get("data")) |data| {
                    if (data == .object) {
                        if (data.object.get("hash")) |hash| {
                            if (hash == .string) {
                                return SignResult{
                                    .signed_transaction = try allocator.dupe(u8, ""), // Not returned on send
                                    .signature = try allocator.dupe(u8, hash.string),
                                    .sent = true,
                                };
                            }
                        }
                    }
                }
            }
            return error.SendFailed;
        },
    }
}

/// Check if Privy wallet is configured
pub fn isPrivyConfigured() bool {
    return privy_client.isConfigured();
}

/// Check if local wallet is available for the given chain
pub fn isLocalWalletAvailable(allocator: std.mem.Allocator, chain: ChainType) bool {
    switch (chain) {
        .solana => {
            const keypair = wallet.loadSolanaKeypair(allocator, null) catch return false;
            _ = keypair;
            return true;
        },
        .ethereum => {
            const pk = wallet.loadEvmPrivateKey(allocator, null, null) catch return false;
            _ = pk;
            return true;
        },
    }
}

/// Get available wallet types for a chain
pub fn getAvailableWalletTypes(allocator: std.mem.Allocator, chain: ChainType) ![]const WalletType {
    var types = std.ArrayList(WalletType).init(allocator);
    errdefer types.deinit();

    if (isLocalWalletAvailable(allocator, chain)) {
        try types.append(.local);
    }
    if (isPrivyConfigured()) {
        try types.append(.privy);
    }

    return types.toOwnedSlice();
}
