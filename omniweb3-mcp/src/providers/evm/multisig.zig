//! EVM Multi-Signature Wallet Support (Gnosis Safe)
//!
//! Provides functionality to build and manage multi-signature transactions
//! compatible with Gnosis Safe contracts.

const std = @import("std");
const chain_provider = @import("../../core/chain_provider.zig");
const rpc_client = @import("./rpc_client.zig");

const FunctionCall = chain_provider.FunctionCall;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const EvmRpcClient = rpc_client.EvmRpcClient;

/// Gnosis Safe transaction operation type
pub const Operation = enum(u8) {
    /// Direct contract call
    call = 0,
    /// Delegate call (executes in Safe's context)
    delegate_call = 1,

    pub fn toU8(self: Operation) u8 {
        return @intFromEnum(self);
    }
};

/// Gnosis Safe transaction structure
pub const SafeTransaction = struct {
    /// Safe wallet address
    safe_address: []const u8,

    /// Target contract address
    to: []const u8,

    /// Value in wei to send
    value: u64,

    /// Encoded function call data
    data: []const u8,

    /// Operation type (Call or DelegateCall)
    operation: Operation,

    /// Gas that should be used for the Safe transaction
    safe_tx_gas: u64,

    /// Gas costs for data used to trigger the Safe transaction
    base_gas: u64,

    /// Maximum gas price that should be used for this transaction
    gas_price: u64,

    /// Token address (or 0x0 for ETH) for payment
    gas_token: []const u8,

    /// Address that should receive the payment (or 0x0 for tx.origin)
    refund_receiver: []const u8,

    /// Nonce of the Safe transaction
    nonce: u64,

    /// Signatures from Safe owners (bytes)
    signatures: ?[]const u8 = null,

    /// Free allocated memory
    pub fn deinit(self: SafeTransaction, allocator: std.mem.Allocator) void {
        allocator.free(self.safe_address);
        allocator.free(self.to);
        allocator.free(self.data);
        allocator.free(self.gas_token);
        allocator.free(self.refund_receiver);
        if (self.signatures) |sigs| {
            allocator.free(sigs);
        }
    }
};

/// Safe transaction hash for signing
pub const SafeTransactionHash = struct {
    /// The hash to be signed by Safe owners
    hash: [32]u8,

    /// Domain separator for EIP-712
    domain_separator: [32]u8,
};

/// Multi-signature wallet builder
pub const MultiSigBuilder = struct {
    allocator: std.mem.Allocator,

    /// Initialize multi-sig builder
    pub fn init(allocator: std.mem.Allocator) MultiSigBuilder {
        return .{ .allocator = allocator };
    }

    /// Build Safe transaction from encoded call data
    ///
    /// Parameters:
    /// - safe_address: Address of the Gnosis Safe contract
    /// - to: Target contract address
    /// - value: ETH value to send (in wei)
    /// - data: Encoded function call data (from TransactionBuilder.encodeFunctionCall)
    /// - operation: Call or DelegateCall
    /// - nonce: Safe transaction nonce (fetch from Safe.nonce() if unknown)
    ///
    /// Note: For production use, you should:
    /// 1. Fetch current nonce from Safe contract (Safe.nonce())
    /// 2. Estimate gas for the transaction
    /// 3. Set appropriate gas price for faster execution
    pub fn buildSafeTransaction(
        self: *MultiSigBuilder,
        safe_address: []const u8,
        to: []const u8,
        value: u64,
        data: []const u8,
        operation: Operation,
        nonce: u64,
    ) !SafeTransaction {
        // Use defaults for gas parameters (can be customized via buildSafeTransactionWithGas)
        const safe_tx_gas: u64 = 0; // 0 means estimate
        const base_gas: u64 = 0;
        const gas_price: u64 = 0; // 0 means current gas price
        const gas_token = "0x0000000000000000000000000000000000000000"; // ETH
        const refund_receiver = "0x0000000000000000000000000000000000000000"; // tx.origin

        return SafeTransaction{
            .safe_address = try self.allocator.dupe(u8, safe_address),
            .to = try self.allocator.dupe(u8, to),
            .value = value,
            .data = try self.allocator.dupe(u8, data),
            .operation = operation,
            .safe_tx_gas = safe_tx_gas,
            .base_gas = base_gas,
            .gas_price = gas_price,
            .gas_token = try self.allocator.dupe(u8, gas_token),
            .refund_receiver = try self.allocator.dupe(u8, refund_receiver),
            .nonce = nonce,
        };
    }

    /// Build Safe transaction with custom gas parameters
    pub fn buildSafeTransactionWithGas(
        self: *MultiSigBuilder,
        safe_address: []const u8,
        to: []const u8,
        value: u64,
        data: []const u8,
        operation: Operation,
        nonce: u64,
        safe_tx_gas: u64,
        base_gas: u64,
        gas_price: u64,
        gas_token: []const u8,
        refund_receiver: []const u8,
    ) !SafeTransaction {
        return SafeTransaction{
            .safe_address = try self.allocator.dupe(u8, safe_address),
            .to = try self.allocator.dupe(u8, to),
            .value = value,
            .data = try self.allocator.dupe(u8, data),
            .operation = operation,
            .safe_tx_gas = safe_tx_gas,
            .base_gas = base_gas,
            .gas_price = gas_price,
            .gas_token = try self.allocator.dupe(u8, gas_token),
            .refund_receiver = try self.allocator.dupe(u8, refund_receiver),
            .nonce = nonce,
        };
    }

    /// Calculate Safe transaction hash for signing (EIP-712)
    pub fn calculateTransactionHash(
        self: *MultiSigBuilder,
        safe_tx: *const SafeTransaction,
        chain_id: u64,
    ) !SafeTransactionHash {
        // EIP-712 Domain Separator
        // keccak256(EIP712_DOMAIN_TYPEHASH || Safe address || chain_id)
        const domain_typehash = try self.hashString(
            "EIP712Domain(uint256 chainId,address verifyingContract)",
        );

        var domain_data = try self.allocator.alloc(u8, 32 + 32 + 32); // typehash + padded_chainId + padded_address
        defer self.allocator.free(domain_data);

        // Copy domain typehash
        @memcpy(domain_data[0..32], &domain_typehash);

        // Encode chain_id (left-padded to 32 bytes)
        @memset(domain_data[32..64], 0);
        std.mem.writeInt(u64, domain_data[56..64], chain_id, .big);

        // Encode Safe address (right-padded to 32 bytes)
        @memset(domain_data[64..96], 0);
        const safe_addr_bytes = try self.parseAddressToBytes(safe_tx.safe_address);
        @memcpy(domain_data[76..96], &safe_addr_bytes); // 20 bytes at right

        var domain_separator: [32]u8 = undefined;
        Keccak256.hash(domain_data, &domain_separator, .{});

        // Safe Transaction TypeHash
        const tx_typehash = try self.hashString(
            "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)",
        );

        // Encode Safe transaction data
        // Total: 32 (typehash) + 32 (to) + 32 (value) + 32 (data hash) + 32 (operation) + 32*5 (gas params) + 32 (nonce)
        var tx_data = try self.allocator.alloc(u8, 32 * 11);
        defer self.allocator.free(tx_data);

        @memset(tx_data, 0);

        // TypeHash
        @memcpy(tx_data[0..32], &tx_typehash);

        // to address (right-aligned in 32 bytes)
        const to_bytes = try self.parseAddressToBytes(safe_tx.to);
        @memcpy(tx_data[44..64], &to_bytes); // 20 bytes at right of 32-byte word

        // value (big-endian u64 in 32 bytes)
        std.mem.writeInt(u64, tx_data[88..96], safe_tx.value, .big);

        // data hash (keccak256 of data)
        var data_hash: [32]u8 = undefined;
        Keccak256.hash(safe_tx.data, &data_hash, .{});
        @memcpy(tx_data[96..128], &data_hash);

        // operation (u8 in 32 bytes)
        tx_data[159] = safe_tx.operation.toU8();

        // safeTxGas
        std.mem.writeInt(u64, tx_data[184..192], safe_tx.safe_tx_gas, .big);

        // baseGas
        std.mem.writeInt(u64, tx_data[216..224], safe_tx.base_gas, .big);

        // gasPrice
        std.mem.writeInt(u64, tx_data[248..256], safe_tx.gas_price, .big);

        // gasToken address
        const gas_token_bytes = try self.parseAddressToBytes(safe_tx.gas_token);
        @memcpy(tx_data[268..288], &gas_token_bytes);

        // refundReceiver address
        const refund_bytes = try self.parseAddressToBytes(safe_tx.refund_receiver);
        @memcpy(tx_data[300..320], &refund_bytes);

        // nonce
        std.mem.writeInt(u64, tx_data[344..352], safe_tx.nonce, .big);

        // Hash transaction data
        var tx_hash_inner: [32]u8 = undefined;
        Keccak256.hash(tx_data, &tx_hash_inner, .{});

        // Final EIP-712 hash: keccak256("\x19\x01" || domainSeparator || txHash)
        var final_data = try self.allocator.alloc(u8, 2 + 32 + 32);
        defer self.allocator.free(final_data);

        final_data[0] = 0x19;
        final_data[1] = 0x01;
        @memcpy(final_data[2..34], &domain_separator);
        @memcpy(final_data[34..66], &tx_hash_inner);

        var hash: [32]u8 = undefined;
        Keccak256.hash(final_data, &hash, .{});

        return SafeTransactionHash{
            .hash = hash,
            .domain_separator = domain_separator,
        };
    }

    /// Hash a string with keccak256
    fn hashString(self: *MultiSigBuilder, s: []const u8) ![32]u8 {
        _ = self;
        var hash: [32]u8 = undefined;
        Keccak256.hash(s, &hash, .{});
        return hash;
    }

    /// Parse hex address string to 20 bytes
    fn parseAddressToBytes(self: *MultiSigBuilder, addr: []const u8) ![20]u8 {
        _ = self;
        var result: [20]u8 = undefined;

        // Remove "0x" prefix if present
        const hex_str = if (addr.len >= 2 and addr[0] == '0' and (addr[1] == 'x' or addr[1] == 'X'))
            addr[2..]
        else
            addr;

        // Parse hex string to bytes
        if (hex_str.len != 40) {
            return error.InvalidAddressLength;
        }

        _ = std.fmt.hexToBytes(&result, hex_str) catch return error.InvalidHexAddress;
        return result;
    }

    /// Encode execTransaction call data
    pub fn encodeExecTransaction(
        self: *MultiSigBuilder,
        safe_tx: *const SafeTransaction,
    ) ![]const u8 {
        // Function signature: execTransaction(
        //     address to,
        //     uint256 value,
        //     bytes data,
        //     uint8 operation,
        //     uint256 safeTxGas,
        //     uint256 baseGas,
        //     uint256 gasPrice,
        //     address gasToken,
        //     address refundReceiver,
        //     bytes signatures
        // )
        // Selector: 0x6a761202

        // Calculate function selector
        const selector_bytes = [_]u8{ 0x6a, 0x76, 0x12, 0x02 };

        // ABI encoding:
        // 1. Static parameters (to, value) encoded in place
        // 2. Dynamic parameters (data, signatures) have offset pointers
        // 3. Dynamic data appended at end

        // Calculate offsets for dynamic parameters
        // Head = 32 * 10 (10 parameters) = 320 bytes
        const data_offset: usize = 320;
        const signatures_offset: usize = data_offset + 32 + ((safe_tx.data.len + 31) / 32) * 32;

        // Allocate buffer for encoding
        // Head (320) + data_length (32) + data_padded + sig_length (32) + sig_padded
        const sig_len = if (safe_tx.signatures) |sigs| sigs.len else 0;
        const data_padded_len = ((safe_tx.data.len + 31) / 32) * 32;
        const sig_padded_len = ((sig_len + 31) / 32) * 32;
        const total_len = 320 + 32 + data_padded_len + 32 + sig_padded_len;

        var encoded = try self.allocator.alloc(u8, total_len);
        @memset(encoded, 0);

        var offset: usize = 0;

        // Parameter 1: to (address)
        const to_bytes = try self.parseAddressToBytes(safe_tx.to);
        @memcpy(encoded[offset + 12 .. offset + 32], &to_bytes);
        offset += 32;

        // Parameter 2: value (uint256)
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], safe_tx.value, .big);
        offset += 32;

        // Parameter 3: data offset (uint256)
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], data_offset, .big);
        offset += 32;

        // Parameter 4: operation (uint8)
        encoded[offset + 31] = safe_tx.operation.toU8();
        offset += 32;

        // Parameter 5: safeTxGas (uint256)
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], safe_tx.safe_tx_gas, .big);
        offset += 32;

        // Parameter 6: baseGas (uint256)
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], safe_tx.base_gas, .big);
        offset += 32;

        // Parameter 7: gasPrice (uint256)
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], safe_tx.gas_price, .big);
        offset += 32;

        // Parameter 8: gasToken (address)
        const gas_token_bytes = try self.parseAddressToBytes(safe_tx.gas_token);
        @memcpy(encoded[offset + 12 .. offset + 32], &gas_token_bytes);
        offset += 32;

        // Parameter 9: refundReceiver (address)
        const refund_bytes = try self.parseAddressToBytes(safe_tx.refund_receiver);
        @memcpy(encoded[offset + 12 .. offset + 32], &refund_bytes);
        offset += 32;

        // Parameter 10: signatures offset (uint256)
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], signatures_offset, .big);
        offset += 32;

        // Dynamic data: bytes data
        // Length
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], safe_tx.data.len, .big);
        offset += 32;
        // Data (padded to 32-byte boundary)
        if (safe_tx.data.len > 0) {
            @memcpy(encoded[offset .. offset + safe_tx.data.len], safe_tx.data);
        }
        offset += data_padded_len;

        // Dynamic data: bytes signatures
        // Length
        std.mem.writeInt(u64, encoded[offset + 24 .. offset + 32], sig_len, .big);
        offset += 32;
        // Signatures (padded to 32-byte boundary)
        if (safe_tx.signatures) |sigs| {
            if (sigs.len > 0) {
                @memcpy(encoded[offset .. offset + sigs.len], sigs);
            }
        }

        // Build final hex string: 0x + selector + encoded
        const hex_len = 2 + (selector_bytes.len + encoded.len) * 2;
        var result = try self.allocator.alloc(u8, hex_len);
        errdefer self.allocator.free(result);

        result[0] = '0';
        result[1] = 'x';

        const hex_chars = "0123456789abcdef";
        var hex_offset: usize = 2;

        // Encode selector
        for (selector_bytes) |byte| {
            result[hex_offset] = hex_chars[byte >> 4];
            result[hex_offset + 1] = hex_chars[byte & 0x0F];
            hex_offset += 2;
        }

        // Encode parameters
        for (encoded) |byte| {
            result[hex_offset] = hex_chars[byte >> 4];
            result[hex_offset + 1] = hex_chars[byte & 0x0F];
            hex_offset += 2;
        }

        self.allocator.free(encoded);

        return result;
    }
};

/// Safe contract information
pub const SafeInfo = struct {
    /// Safe address
    address: []const u8,

    /// List of owner addresses
    owners: [][]const u8,

    /// Required number of signatures (threshold)
    threshold: u64,

    /// Current nonce
    nonce: u64,

    /// Safe version (e.g., "1.4.1")
    version: ?[]const u8 = null,

    /// Free allocated memory
    pub fn deinit(self: SafeInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
        for (self.owners) |owner| {
            allocator.free(owner);
        }
        allocator.free(self.owners);
        if (self.version) |v| {
            allocator.free(v);
        }
    }
};

/// ECDSA signature components
pub const Signature = struct {
    /// r component (32 bytes)
    r: [32]u8,

    /// s component (32 bytes)
    s: [32]u8,

    /// v component (recovery id, typically 27 or 28)
    v: u8,

    /// Encode signature as bytes (r || s || v) - 65 bytes total
    pub fn toBytes(self: Signature, allocator: std.mem.Allocator) ![]u8 {
        var result = try allocator.alloc(u8, 65);
        @memcpy(result[0..32], &self.r);
        @memcpy(result[32..64], &self.s);
        result[64] = self.v;
        return result;
    }

    /// Parse signature from 65-byte array
    pub fn fromBytes(bytes: []const u8) !Signature {
        if (bytes.len != 65) {
            return error.InvalidSignatureLength;
        }

        var sig: Signature = undefined;
        @memcpy(&sig.r, bytes[0..32]);
        @memcpy(&sig.s, bytes[32..64]);
        sig.v = bytes[64];

        return sig;
    }

    /// Parse signature from hex string (0x-prefixed, 130 chars)
    pub fn fromHex(allocator: std.mem.Allocator, hex: []const u8) !Signature {
        const hex_data = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;

        if (hex_data.len != 130) {
            return error.InvalidSignatureLength;
        }

        const bytes = try allocator.alloc(u8, 65);
        defer allocator.free(bytes);

        _ = std.fmt.hexToBytes(bytes, hex_data) catch return error.InvalidHexSignature;

        return try fromBytes(bytes);
    }
};

/// Safe manager with RPC integration
pub const SafeManager = struct {
    allocator: std.mem.Allocator,
    rpc_client: *EvmRpcClient,

    /// Initialize Safe manager
    pub fn init(allocator: std.mem.Allocator, client: *EvmRpcClient) SafeManager {
        return .{
            .allocator = allocator,
            .rpc_client = client,
        };
    }

    /// Get Safe contract information (nonce, threshold, owners, version)
    pub fn getSafeInfo(self: *SafeManager, safe_address: []const u8) !SafeInfo {
        // Call nonce()
        const nonce_data = "0xaffed0e0"; // nonce() selector
        const nonce_result = try self.rpc_client.ethCall(.{
            .from = null,
            .to = safe_address,
            .gas = null,
            .gasPrice = null,
            .value = null,
            .data = nonce_data,
        }, .latest);
        defer self.allocator.free(nonce_result);

        const nonce = try self.parseU256(nonce_result);

        // Call getThreshold()
        const threshold_data = "0xe75235b8"; // getThreshold() selector
        const threshold_result = try self.rpc_client.ethCall(.{
            .from = null,
            .to = safe_address,
            .gas = null,
            .gasPrice = null,
            .value = null,
            .data = threshold_data,
        }, .latest);
        defer self.allocator.free(threshold_result);

        const threshold = try self.parseU256(threshold_result);

        // Call getOwners()
        const owners_data = "0xa0e67e2b"; // getOwners() selector
        const owners_result = try self.rpc_client.ethCall(.{
            .from = null,
            .to = safe_address,
            .gas = null,
            .gasPrice = null,
            .value = null,
            .data = owners_data,
        }, .latest);
        defer self.allocator.free(owners_result);

        const owners = try self.parseAddressArray(owners_result);

        // Try to get version (may fail on older Safe contracts)
        var version: ?[]const u8 = null;
        const version_data = "0xffa1ad74"; // VERSION() selector
        if (self.rpc_client.ethCall(.{
            .from = null,
            .to = safe_address,
            .gas = null,
            .gasPrice = null,
            .value = null,
            .data = version_data,
        }, .latest)) |version_result| {
            defer self.allocator.free(version_result);
            version = try self.parseString(version_result);
        } else |_| {
            // Version call failed, assume older version
            version = try self.allocator.dupe(u8, "< 1.3.0");
        }

        return SafeInfo{
            .address = try self.allocator.dupe(u8, safe_address),
            .owners = owners,
            .threshold = threshold,
            .nonce = nonce,
            .version = version,
        };
    }

    /// Build Safe transaction with auto-fetched nonce
    pub fn buildSafeTransactionAuto(
        self: *SafeManager,
        safe_address: []const u8,
        to: []const u8,
        value: u64,
        data: []const u8,
        operation: Operation,
    ) !SafeTransaction {
        // Get Safe info to fetch current nonce
        const safe_info = try self.getSafeInfo(safe_address);
        defer safe_info.deinit(self.allocator);

        // Build transaction with fetched nonce
        var builder = MultiSigBuilder.init(self.allocator);
        return try builder.buildSafeTransaction(
            safe_address,
            to,
            value,
            data,
            operation,
            safe_info.nonce,
        );
    }

    /// Aggregate signatures for Safe transaction
    ///
    /// Signatures must be sorted by signer address (ascending order)
    /// Safe requires: sig1.signer < sig2.signer < sig3.signer
    pub fn aggregateSignatures(
        self: *SafeManager,
        signatures: []const Signature,
        signers: []const []const u8,
    ) ![]u8 {
        if (signatures.len != signers.len) {
            return error.SignerCountMismatch;
        }

        if (signatures.len == 0) {
            return error.NoSignatures;
        }

        // Create array of (signer, signature) pairs for sorting
        var pairs = try self.allocator.alloc(struct { signer: []const u8, sig: Signature }, signatures.len);
        defer self.allocator.free(pairs);

        for (signatures, signers, 0..) |sig, signer, i| {
            pairs[i] = .{ .signer = signer, .sig = sig };
        }

        // Sort by signer address (ascending)
        std.mem.sort(@TypeOf(pairs[0]), pairs, {}, struct {
            fn lessThan(_: void, a: @TypeOf(pairs[0]), b: @TypeOf(pairs[0])) bool {
                return std.mem.lessThan(u8, a.signer, b.signer);
            }
        }.lessThan);

        // Concatenate signatures: r1 || s1 || v1 || r2 || s2 || v2 || ...
        var result = try self.allocator.alloc(u8, 65 * signatures.len);
        errdefer self.allocator.free(result);

        for (pairs, 0..) |pair, i| {
            const offset = i * 65;
            const sig_bytes = try pair.sig.toBytes(self.allocator);
            defer self.allocator.free(sig_bytes);
            @memcpy(result[offset .. offset + 65], sig_bytes);
        }

        return result;
    }

    /// Verify Safe version is supported
    pub fn verifySafeVersion(self: *SafeManager, safe_address: []const u8) !bool {
        const safe_info = try self.getSafeInfo(safe_address);
        defer safe_info.deinit(self.allocator);

        if (safe_info.version == null) {
            // No version info, assume compatible
            return true;
        }

        const version = safe_info.version.?;

        // Support Safe 1.3.0 and above
        // Version format: "1.4.1", "1.3.0", etc.
        if (version.len >= 5) {
            const major = version[0] - '0';
            const minor = version[2] - '0';

            // Support version 1.3.0+
            if (major == '1' and minor >= 3) {
                return true;
            }
            // Support version 2.0.0+
            if (major >= '2') {
                return true;
            }
        }

        return false;
    }

    /// Parse uint256 from hex result
    fn parseU256(self: *SafeManager, hex: []const u8) !u64 {
        _ = self;
        const hex_str = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;

        return try std.fmt.parseInt(u64, hex_str, 16);
    }

    /// Parse address array from ABI-encoded result
    fn parseAddressArray(self: *SafeManager, hex: []const u8) ![][]const u8 {
        // Simplified parsing: assumes standard ABI encoding
        // offset (32 bytes) | length (32 bytes) | addr1 (32 bytes) | addr2 (32 bytes) | ...

        const hex_str = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;

        if (hex_str.len < 128) {
            // Need at least offset + length
            return error.InvalidAbiData;
        }

        // Parse length (at bytes 32-64, hex position 64-128)
        const length_hex = hex_str[64..128];
        const length = try std.fmt.parseInt(usize, length_hex, 16);

        if (length == 0) {
            return try self.allocator.alloc([]const u8, 0);
        }

        var addresses = try self.allocator.alloc([]const u8, length);
        errdefer {
            for (addresses[0..length]) |addr| {
                self.allocator.free(addr);
            }
            self.allocator.free(addresses);
        }

        // Each address is 32 bytes (64 hex chars), but actual address is last 20 bytes
        for (0..length) |i| {
            const addr_offset = 128 + (i * 64); // Skip offset + length
            if (addr_offset + 64 > hex_str.len) {
                return error.InvalidAbiData;
            }

            // Take last 40 hex chars (20 bytes = address)
            const addr_hex = hex_str[addr_offset + 24 .. addr_offset + 64];

            // Format as "0x" + address
            var addr = try self.allocator.alloc(u8, 42);
            addr[0] = '0';
            addr[1] = 'x';
            @memcpy(addr[2..], addr_hex);

            addresses[i] = addr;
        }

        return addresses;
    }

    /// Parse string from ABI-encoded result
    fn parseString(self: *SafeManager, hex: []const u8) ![]const u8 {
        const hex_str = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;

        if (hex_str.len < 128) {
            return error.InvalidAbiData;
        }

        // Parse length (at bytes 32-64)
        const length_hex = hex_str[64..128];
        const length = try std.fmt.parseInt(usize, length_hex, 16);

        if (length == 0) {
            return try self.allocator.alloc(u8, 0);
        }

        // String data starts at byte 64
        const data_hex = hex_str[128..];
        if (data_hex.len < length * 2) {
            return error.InvalidAbiData;
        }

        // Convert hex to string
        var result = try self.allocator.alloc(u8, length);
        errdefer self.allocator.free(result);

        for (0..length) |i| {
            const byte_hex = data_hex[i * 2 .. i * 2 + 2];
            result[i] = try std.fmt.parseInt(u8, byte_hex, 16);
        }

        return result;
    }
};

// Tests
const testing = std.testing;

test "SafeTransaction basic structure" {
    const allocator = testing.allocator;

    const safe_tx = SafeTransaction{
        .safe_address = try allocator.dupe(u8, "0x1234..."),
        .to = try allocator.dupe(u8, "0x5678..."),
        .value = 0,
        .data = &[_]u8{},
        .operation = .call,
        .safe_tx_gas = 0,
        .base_gas = 0,
        .gas_price = 0,
        .gas_token = try allocator.dupe(u8, "0x0000000000000000000000000000000000000000"),
        .refund_receiver = try allocator.dupe(u8, "0x0000000000000000000000000000000000000000"),
        .nonce = 0,
    };
    defer safe_tx.deinit(allocator);

    try testing.expectEqual(Operation.call, safe_tx.operation);
    try testing.expectEqual(@as(u64, 0), safe_tx.value);
    try testing.expectEqual(@as(u64, 0), safe_tx.nonce);
}

test "Operation enum conversion" {
    try testing.expectEqual(@as(u8, 0), Operation.call.toU8());
    try testing.expectEqual(@as(u8, 1), Operation.delegate_call.toU8());
}

test "MultiSigBuilder initialization" {
    const allocator = testing.allocator;
    const builder = MultiSigBuilder.init(allocator);

    try testing.expect(builder.allocator.ptr == allocator.ptr);
}
