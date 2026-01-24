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
const chain_mod = @import("chain.zig");
const wallet = @import("wallet.zig");
const privy_client = @import("../tools/auth/privy/client.zig");

const Keypair = solana_sdk.Keypair;
const Signature = solana_sdk.Signature;
const PublicKey = solana_sdk.PublicKey;
const short_vec = solana_sdk.short_vec;

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
    network: []const u8 = "mainnet", // Network for Privy signing
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
            const keypair = try wallet.loadSolanaKeypair(allocator, config.keypair_path);
            const signed = try signLocalSolanaTransactionBytes(allocator, keypair, unsigned_transaction_b64);
            defer allocator.free(signed.signed_bytes);

            const encoded_len = std.base64.standard.Encoder.calcSize(signed.signed_bytes.len);
            const signed_b64 = try allocator.alloc(u8, encoded_len);
            errdefer allocator.free(signed_b64);
            _ = std.base64.standard.Encoder.encode(signed_b64, signed.signed_bytes);

            var sig_buf: [solana_sdk.signature.MAX_BASE58_LEN]u8 = undefined;
            const sig_str = signed.signature.toBase58(&sig_buf);

            return SignResult{
                .signed_transaction = signed_b64,
                .signature = try allocator.dupe(u8, sig_str),
                .sent = false,
            };
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
            const keypair = try wallet.loadSolanaKeypair(allocator, config.keypair_path);
            const signed = try signLocalSolanaTransactionBytes(allocator, keypair, unsigned_transaction_b64);
            defer allocator.free(signed.signed_bytes);

            var adapter = try chain_mod.initSolanaAdapter(allocator, config.network, null);
            defer adapter.deinit();

            const rpc_signature = try adapter.sendTransaction(signed.signed_bytes);

            var sig_buf: [solana_sdk.signature.MAX_BASE58_LEN]u8 = undefined;
            const sig_str = rpc_signature.toBase58(&sig_buf);

            const encoded_len = std.base64.standard.Encoder.calcSize(signed.signed_bytes.len);
            const signed_b64 = try allocator.alloc(u8, encoded_len);
            errdefer allocator.free(signed_b64);
            _ = std.base64.standard.Encoder.encode(signed_b64, signed.signed_bytes);

            return SignResult{
                .signed_transaction = signed_b64,
                .signature = try allocator.dupe(u8, sig_str),
                .sent = true,
            };
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

fn signLocalSolanaTransactionBytes(
    allocator: std.mem.Allocator,
    keypair: Keypair,
    unsigned_transaction_b64: []const u8,
) !struct { signed_bytes: []u8, signature: Signature } {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(unsigned_transaction_b64) catch {
        return error.InvalidBase64;
    };
    const tx_bytes = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(tx_bytes);

    std.base64.standard.Decoder.decode(tx_bytes, unsigned_transaction_b64) catch {
        return error.InvalidBase64;
    };

    const sig_len_info = short_vec.decodeU16Len(tx_bytes) catch return error.InvalidShortVec;
    if (sig_len_info.value == 0) return error.InvalidTransaction;

    const signature_count: usize = sig_len_info.value;
    const signatures_offset = sig_len_info.bytes_read;
    const signatures_len = signature_count * solana_sdk.SIGNATURE_BYTES;
    if (tx_bytes.len < signatures_offset + signatures_len + 3) {
        return error.InvalidTransaction;
    }

    const message_bytes = tx_bytes[signatures_offset + signatures_len ..];
    if (message_bytes.len < 3) return error.InvalidTransaction;

    const num_required: usize = message_bytes[0];
    const account_len_info = short_vec.decodeU16Len(message_bytes[3..]) catch return error.InvalidShortVec;
    const account_count: usize = account_len_info.value;
    const account_keys_offset = 3 + account_len_info.bytes_read;
    const account_keys_len = account_count * PublicKey.length;
    if (message_bytes.len < account_keys_offset + account_keys_len) {
        return error.InvalidTransaction;
    }

    const account_keys_bytes = message_bytes[account_keys_offset .. account_keys_offset + account_keys_len];
    const required = if (num_required > account_count) account_count else num_required;
    var signer_index: ?usize = null;
    const signer_bytes = keypair.pubkey().bytes;
    for (0..required) |i| {
        const start = i * PublicKey.length;
        const end = start + PublicKey.length;
        if (std.mem.eql(u8, account_keys_bytes[start..end], &signer_bytes)) {
            signer_index = i;
            break;
        }
    }
    if (signer_index == null) return error.MissingSigner;
    if (signer_index.? >= signature_count) return error.InvalidTransaction;

    const signature = keypair.sign(message_bytes) catch return error.SigningFailed;
    const sig_offset = signatures_offset + signer_index.? * solana_sdk.SIGNATURE_BYTES;
    @memcpy(tx_bytes[sig_offset .. sig_offset + solana_sdk.SIGNATURE_BYTES], &signature.bytes);

    return .{ .signed_bytes = tx_bytes, .signature = signature };
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
