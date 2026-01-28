//! EVM Multi-Signature Wallet Support (Gnosis Safe)
//!
//! Provides functionality to build and manage multi-signature transactions
//! compatible with Gnosis Safe contracts.

const std = @import("std");
const chain_provider = @import("../../core/chain_provider.zig");

const FunctionCall = chain_provider.FunctionCall;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

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

    /// Free allocated memory
    pub fn deinit(self: SafeInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
        for (self.owners) |owner| {
            allocator.free(owner);
        }
        allocator.free(self.owners);
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
