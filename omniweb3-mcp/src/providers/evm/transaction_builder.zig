//! EVM Transaction Builder
//!
//! Builds and encodes EVM transactions with ABI-encoded function calls.
//! Handles function selector calculation, parameter encoding, and transaction construction.

const std = @import("std");
const abi_resolver = @import("abi_resolver.zig");
const rpc_client = @import("rpc_client.zig");
const zabi = @import("zabi");

const AbiFunction = abi_resolver.AbiFunction;
const AbiParam = abi_resolver.AbiParam;
const TransactionRequest = rpc_client.TransactionRequest;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Transaction builder for EVM transactions
pub const TransactionBuilder = struct {
    allocator: std.mem.Allocator,

    /// Initialize transaction builder
    pub fn init(allocator: std.mem.Allocator) TransactionBuilder {
        return TransactionBuilder{
            .allocator = allocator,
        };
    }

    /// Calculate function selector (first 4 bytes of keccak256 hash of signature)
    /// Example: transfer(address,uint256) -> 0xa9059cbb
    pub fn calculateFunctionSelector(
        self: TransactionBuilder,
        function: *const AbiFunction,
    ) ![4]u8 {
        // Build function signature: "functionName(type1,type2,...)"
        var signature: std.ArrayList(u8) = .{};
        defer signature.deinit(self.allocator);

        try signature.appendSlice(self.allocator, function.name);
        try signature.append(self.allocator, '(');

        for (function.inputs, 0..) |param, i| {
            if (i > 0) try signature.append(self.allocator, ',');
            try signature.appendSlice(self.allocator, param.type);
        }
        try signature.append(self.allocator, ')');

        std.log.debug("Function signature: {s}", .{signature.items});

        // Calculate keccak256 hash
        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(signature.items, &hashed, .{});

        // Return first 4 bytes as function selector
        return hashed[0..4].*;
    }

    /// Encode function call data (selector + encoded parameters)
    pub fn encodeFunctionCall(
        self: TransactionBuilder,
        function: *const AbiFunction,
        params: std.json.Value,
    ) ![]const u8 {
        // Get function selector
        const selector = try self.calculateFunctionSelector(function);

        // Encode parameters
        const encoded_params = try self.encodeParameters(function.inputs, params);
        defer self.allocator.free(encoded_params);

        // Build final data: 0x + selector_hex + params_hex
        var data: std.ArrayList(u8) = .{};
        errdefer data.deinit(self.allocator);

        // Add "0x" prefix
        try data.appendSlice(self.allocator, "0x");

        // Add selector (4 bytes as hex)
        const hex_chars = "0123456789abcdef";
        for (selector) |byte| {
            try data.append(self.allocator, hex_chars[byte >> 4]);
            try data.append(self.allocator, hex_chars[byte & 0x0F]);
        }

        // Add encoded parameters (already in hex)
        try data.appendSlice(self.allocator, encoded_params);

        return data.toOwnedSlice(self.allocator);
    }

    /// Encode parameters according to ABI specification
    fn encodeParameters(
        self: TransactionBuilder,
        params_spec: []const AbiParam,
        params_json: std.json.Value,
    ) ![]const u8 {
        // If no parameters, return empty string
        if (params_spec.len == 0) {
            return try self.allocator.dupe(u8, "");
        }

        // Build array of encoded values (each 32 bytes)
        var encoded_parts: std.ArrayList([]const u8) = .{};
        defer {
            for (encoded_parts.items) |part| {
                self.allocator.free(part);
            }
            encoded_parts.deinit(self.allocator);
        }

        // Extract parameters from JSON (either object with named params or array)
        const params_obj = if (params_json == .object)
            params_json.object
        else
            null;

        for (params_spec, 0..) |param_spec, i| {
            // Get parameter value from JSON
            const param_value = if (params_obj) |obj|
                obj.get(param_spec.name) orelse return error.MissingParameter
            else if (params_json == .array and i < params_json.array.items.len)
                params_json.array.items[i]
            else
                return error.MissingParameter;

            // Encode based on type
            const encoded = try self.encodeParameter(param_spec.type, param_value);
            try encoded_parts.append(self.allocator, encoded);
        }

        // Concatenate all encoded parts
        var total_len: usize = 0;
        for (encoded_parts.items) |part| {
            total_len += part.len;
        }

        var result = try self.allocator.alloc(u8, total_len);
        var offset: usize = 0;
        for (encoded_parts.items) |part| {
            @memcpy(result[offset..][0..part.len], part);
            offset += part.len;
        }

        return result;
    }

    /// Encode a single parameter value
    fn encodeParameter(
        self: TransactionBuilder,
        param_type: []const u8,
        value: std.json.Value,
    ) ![]const u8 {
        // Address: 20 bytes, left-padded to 32 bytes
        if (std.mem.eql(u8, param_type, "address")) {
            if (value != .string) return error.InvalidParameterType;
            return try self.encodeAddress(value.string);
        }

        // Unsigned integers: uint8 to uint256
        if (std.mem.startsWith(u8, param_type, "uint")) {
            const num_value = switch (value) {
                .integer => |i| @as(u256, @intCast(i)),
                .string => |s| try std.fmt.parseInt(u256, s, 10),
                else => return error.InvalidParameterType,
            };
            return try self.encodeUint256(num_value);
        }

        // Signed integers: int8 to int256
        if (std.mem.startsWith(u8, param_type, "int")) {
            const num_value = switch (value) {
                .integer => |i| @as(i256, @intCast(i)),
                .string => |s| try std.fmt.parseInt(i256, s, 10),
                else => return error.InvalidParameterType,
            };
            return try self.encodeInt256(num_value);
        }

        // Boolean: 0 or 1, padded to 32 bytes
        if (std.mem.eql(u8, param_type, "bool")) {
            if (value != .bool) return error.InvalidParameterType;
            return try self.encodeBool(value.bool);
        }

        // Fixed-size bytes: bytes1 to bytes32
        if (std.mem.startsWith(u8, param_type, "bytes") and param_type.len > 5) {
            const size_str = param_type[5..];
            const size = std.fmt.parseInt(u8, size_str, 10) catch {
                // Dynamic bytes type, handle below
                if (value != .string) return error.InvalidParameterType;
                return try self.encodeDynamicBytes(value.string);
            };
            if (size >= 1 and size <= 32) {
                if (value != .string) return error.InvalidParameterType;
                return try self.encodeFixedBytes(value.string, size);
            }
        }

        // Dynamic types (string, bytes, arrays) - simplified for now
        if (std.mem.eql(u8, param_type, "string")) {
            if (value != .string) return error.InvalidParameterType;
            return try self.encodeString(value.string);
        }

        if (std.mem.eql(u8, param_type, "bytes")) {
            if (value != .string) return error.InvalidParameterType;
            return try self.encodeDynamicBytes(value.string);
        }

        // Unsupported type for now (arrays, tuples, etc.)
        std.log.warn("Unsupported parameter type: {s}", .{param_type});
        return error.UnsupportedParameterType;
    }

    /// Encode address (20 bytes, left-padded to 32 bytes as hex)
    fn encodeAddress(self: TransactionBuilder, address: []const u8) ![]const u8 {
        // Remove 0x prefix if present
        const addr = if (std.mem.startsWith(u8, address, "0x"))
            address[2..]
        else
            address;

        // Validate length (should be 40 hex chars = 20 bytes)
        if (addr.len != 40) return error.InvalidAddress;

        // Left-pad to 64 hex chars (32 bytes)
        var result = try self.allocator.alloc(u8, 64);
        @memset(result[0..24], '0'); // 24 zeros = 12 bytes padding
        @memcpy(result[24..64], addr[0..40]);

        return result;
    }

    /// Encode uint256 (32 bytes, big-endian hex)
    fn encodeUint256(self: TransactionBuilder, value: u256) ![]const u8 {
        var result = try self.allocator.alloc(u8, 64); // 32 bytes = 64 hex chars

        // Convert to big-endian bytes
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &bytes, value, .big);

        // Convert to hex
        const hex_chars = "0123456789abcdef";
        for (bytes, 0..) |byte, i| {
            result[i * 2] = hex_chars[byte >> 4];
            result[i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        return result;
    }

    /// Encode int256 (32 bytes, big-endian hex, two's complement)
    fn encodeInt256(self: TransactionBuilder, value: i256) ![]const u8 {
        // Convert signed to unsigned (two's complement representation)
        const unsigned: u256 = @bitCast(value);
        return try self.encodeUint256(unsigned);
    }

    /// Encode boolean (1 or 0, padded to 32 bytes)
    fn encodeBool(self: TransactionBuilder, value: bool) ![]const u8 {
        const num: u256 = if (value) 1 else 0;
        return try self.encodeUint256(num);
    }

    /// Encode fixed-size bytes (right-padded to 32 bytes)
    fn encodeFixedBytes(self: TransactionBuilder, hex_str: []const u8, size: u8) ![]const u8 {
        _ = size;

        // Remove 0x prefix if present
        const hex = if (std.mem.startsWith(u8, hex_str, "0x"))
            hex_str[2..]
        else
            hex_str;

        // Right-pad to 64 hex chars (32 bytes)
        var result = try self.allocator.alloc(u8, 64);
        const copy_len = @min(hex.len, 64);
        @memcpy(result[0..copy_len], hex[0..copy_len]);
        if (copy_len < 64) {
            @memset(result[copy_len..64], '0'); // Right-pad with zeros
        }

        return result;
    }

    /// Encode dynamic bytes (length + data, both padded)
    fn encodeDynamicBytes(self: TransactionBuilder, hex_str: []const u8) ![]const u8 {
        // Remove 0x prefix if present
        const hex = if (std.mem.startsWith(u8, hex_str, "0x"))
            hex_str[2..]
        else
            hex_str;

        // Calculate length in bytes
        const byte_len = hex.len / 2;

        // Encode length as uint256
        const length_encoded = try self.encodeUint256(byte_len);
        defer self.allocator.free(length_encoded);

        // Pad data to multiple of 32 bytes
        const padded_len = ((byte_len + 31) / 32) * 32;
        const hex_padded_len = padded_len * 2;

        var result = try self.allocator.alloc(u8, 64 + hex_padded_len);
        @memcpy(result[0..64], length_encoded);
        @memcpy(result[64..][0..hex.len], hex);
        if (hex.len < hex_padded_len) {
            @memset(result[64 + hex.len ..], '0'); // Right-pad with zeros
        }

        return result;
    }

    /// Encode string (same as dynamic bytes, but UTF-8 encoded first)
    fn encodeString(self: TransactionBuilder, str: []const u8) ![]const u8 {
        // Convert string to hex
        var hex = try self.allocator.alloc(u8, str.len * 2);
        defer self.allocator.free(hex);

        const hex_chars = "0123456789abcdef";
        for (str, 0..) |byte, i| {
            hex[i * 2] = hex_chars[byte >> 4];
            hex[i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        return try self.encodeDynamicBytes(hex);
    }

    /// Build transaction request for contract function call
    pub fn buildFunctionCallTransaction(
        self: TransactionBuilder,
        contract_address: []const u8,
        function: *const AbiFunction,
        params: std.json.Value,
        options: TransactionOptions,
    ) !TransactionRequest {
        // Encode function call data
        const data = try self.encodeFunctionCall(function, params);

        return TransactionRequest{
            .from = options.from,
            .to = contract_address,
            .gas = options.gas,
            .gasPrice = options.gasPrice,
            .value = if (function.payable) options.value else null,
            .data = data,
            .nonce = options.nonce,
        };
    }

    /// Build simple ETH transfer transaction
    pub fn buildTransferTransaction(
        self: TransactionBuilder,
        to: []const u8,
        value: []const u8,
        options: TransactionOptions,
    ) !TransactionRequest {
        _ = self;

        return TransactionRequest{
            .from = options.from,
            .to = to,
            .gas = options.gas orelse 21000, // Standard ETH transfer gas
            .gasPrice = options.gasPrice,
            .value = value,
            .data = "0x", // Empty data for simple transfer
            .nonce = options.nonce,
        };
    }

    /// Estimate gas for a transaction
    pub fn estimateGas(
        self: TransactionBuilder,
        client: *rpc_client.EvmRpcClient,
        tx: TransactionRequest,
    ) !u64 {
        _ = self;
        return try client.ethEstimateGas(tx);
    }

    /// Get gas price from network
    pub fn getGasPrice(
        self: TransactionBuilder,
        client: *rpc_client.EvmRpcClient,
    ) ![]const u8 {
        _ = self;
        return try client.ethGasPrice();
    }

    /// Get nonce for an address
    pub fn getNonce(
        self: TransactionBuilder,
        client: *rpc_client.EvmRpcClient,
        address: []const u8,
    ) !u64 {
        _ = self;
        return try client.ethGetTransactionCount(address, .pending);
    }
};

/// Transaction options for building transactions
pub const TransactionOptions = struct {
    /// Sender address
    from: ?[]const u8 = null,

    /// Gas limit
    gas: ?u64 = null,

    /// Gas price (hex string)
    gasPrice: ?[]const u8 = null,

    /// Value to send (hex string, for payable functions)
    value: ?[]const u8 = null,

    /// Nonce
    nonce: ?u64 = null,
};

/// Parameter value for ABI encoding
pub const ParamValue = union(enum) {
    uint256: []const u8, // As hex or decimal string
    address: []const u8,
    bool: bool,
    string: []const u8,
    bytes: []const u8,
    array: []ParamValue,

    /// Convert JSON value to ParamValue
    pub fn fromJson(json: std.json.Value, param_type: []const u8) !ParamValue {
        // Simple type mapping - will be expanded
        if (std.mem.startsWith(u8, param_type, "uint") or
            std.mem.startsWith(u8, param_type, "int"))
        {
            if (json == .string) {
                return ParamValue{ .uint256 = json.string };
            }
            return error.InvalidParameterType;
        }

        if (std.mem.eql(u8, param_type, "address")) {
            if (json == .string) {
                return ParamValue{ .address = json.string };
            }
            return error.InvalidParameterType;
        }

        if (std.mem.eql(u8, param_type, "bool")) {
            if (json == .bool) {
                return ParamValue{ .bool = json.bool };
            }
            return error.InvalidParameterType;
        }

        if (std.mem.eql(u8, param_type, "string")) {
            if (json == .string) {
                return ParamValue{ .string = json.string };
            }
            return error.InvalidParameterType;
        }

        if (std.mem.startsWith(u8, param_type, "bytes")) {
            if (json == .string) {
                return ParamValue{ .bytes = json.string };
            }
            return error.InvalidParameterType;
        }

        return error.UnsupportedParameterType;
    }
};

// Tests
const testing = std.testing;

test "TransactionBuilder initialization" {
    const allocator = testing.allocator;
    const builder = TransactionBuilder.init(allocator);
    _ = builder;
}

test "calculateFunctionSelector" {
    const allocator = testing.allocator;
    const builder = TransactionBuilder.init(allocator);

    // Create a mock transfer function
    const function = AbiFunction{
        .name = "transfer",
        .inputs = &[_]AbiParam{
            .{ .name = "to", .type = "address" },
            .{ .name = "amount", .type = "uint256" },
        },
        .outputs = &[_]AbiParam{},
        .state_mutability = .nonpayable,
        .function_type = .function,
        .payable = false,
    };

    const selector = try builder.calculateFunctionSelector(&function);

    // transfer(address,uint256) selector is 0xa9059cbb
    try testing.expectEqual(@as(u8, 0xa9), selector[0]);
    try testing.expectEqual(@as(u8, 0x05), selector[1]);
    try testing.expectEqual(@as(u8, 0x9c), selector[2]);
    try testing.expectEqual(@as(u8, 0xbb), selector[3]);
}

test "calculateFunctionSelector balanceOf" {
    const allocator = testing.allocator;
    const builder = TransactionBuilder.init(allocator);

    const function = AbiFunction{
        .name = "balanceOf",
        .inputs = &[_]AbiParam{
            .{ .name = "account", .type = "address" },
        },
        .outputs = &[_]AbiParam{},
        .state_mutability = .view,
        .function_type = .function,
        .payable = false,
    };

    const selector = try builder.calculateFunctionSelector(&function);

    // balanceOf(address) selector is 0x70a08231
    try testing.expectEqual(@as(u8, 0x70), selector[0]);
    try testing.expectEqual(@as(u8, 0xa0), selector[1]);
    try testing.expectEqual(@as(u8, 0x82), selector[2]);
    try testing.expectEqual(@as(u8, 0x31), selector[3]);
}

test "calculateFunctionSelector approve" {
    const allocator = testing.allocator;
    const builder = TransactionBuilder.init(allocator);

    const function = AbiFunction{
        .name = "approve",
        .inputs = &[_]AbiParam{
            .{ .name = "spender", .type = "address" },
            .{ .name = "amount", .type = "uint256" },
        },
        .outputs = &[_]AbiParam{},
        .state_mutability = .nonpayable,
        .function_type = .function,
        .payable = false,
    };

    const selector = try builder.calculateFunctionSelector(&function);

    // approve(address,uint256) selector is 0x095ea7b3
    try testing.expectEqual(@as(u8, 0x09), selector[0]);
    try testing.expectEqual(@as(u8, 0x5e), selector[1]);
    try testing.expectEqual(@as(u8, 0xa7), selector[2]);
    try testing.expectEqual(@as(u8, 0xb3), selector[3]);
}

test "encodeFunctionCall basic" {
    const allocator = testing.allocator;
    const builder = TransactionBuilder.init(allocator);

    const function = AbiFunction{
        .name = "balanceOf",
        .inputs = &[_]AbiParam{
            .{ .name = "account", .type = "address" },
        },
        .outputs = &[_]AbiParam{},
        .state_mutability = .view,
        .function_type = .function,
        .payable = false,
    };

    // Create params object with account parameter
    var params_obj = std.json.ObjectMap.init(allocator);
    defer params_obj.deinit();
    try params_obj.put("account", std.json.Value{
        .string = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb4",
    });
    const params = std.json.Value{ .object = params_obj };

    const data = try builder.encodeFunctionCall(&function, params);
    defer allocator.free(data);

    // Should start with "0x"
    try testing.expect(std.mem.startsWith(u8, data, "0x"));

    // Should have selector (8 hex) + address parameter (64 hex) = 72 hex + "0x" = 74 chars
    try testing.expect(data.len >= 74);

    // Should start with balanceOf selector: 0x70a08231
    try testing.expect(std.mem.startsWith(u8, data[2..], "70a08231"));
}

test "buildTransferTransaction" {
    const allocator = testing.allocator;
    const builder = TransactionBuilder.init(allocator);

    const tx = try builder.buildTransferTransaction(
        "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
        "0xde0b6b3a7640000", // 1 ETH
        .{
            .from = "0x1234567890123456789012345678901234567890",
            .gasPrice = "0x3b9aca00",
        },
    );

    try testing.expect(tx.to != null);
    try testing.expectEqualStrings("0x742d35Cc6634C0532925a3b844Bc454e4438f44e", tx.to.?);
    try testing.expectEqualStrings("0xde0b6b3a7640000", tx.value.?);
    try testing.expectEqual(@as(u64, 21000), tx.gas.?);
    try testing.expectEqualStrings("0x", tx.data.?);
}

test "ParamValue fromJson address" {
    var obj = std.json.ObjectMap.init(testing.allocator);
    defer obj.deinit();

    const addr = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e";
    const value = std.json.Value{ .string = addr };

    const param = try ParamValue.fromJson(value, "address");
    try testing.expectEqualStrings(addr, param.address);
}

test "ParamValue fromJson uint256" {
    const value = std.json.Value{ .string = "1000000000000000000" };

    const param = try ParamValue.fromJson(value, "uint256");
    try testing.expectEqualStrings("1000000000000000000", param.uint256);
}

test "ParamValue fromJson bool" {
    const value_true = std.json.Value{ .bool = true };
    const param_true = try ParamValue.fromJson(value_true, "bool");
    try testing.expect(param_true.bool);

    const value_false = std.json.Value{ .bool = false };
    const param_false = try ParamValue.fromJson(value_false, "bool");
    try testing.expect(!param_false.bool);
}
