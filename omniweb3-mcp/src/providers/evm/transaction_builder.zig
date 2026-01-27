//! EVM Transaction Builder
//!
//! Builds and encodes EVM transactions with ABI-encoded function calls.
//! Handles function selector calculation, parameter encoding, and transaction construction.

const std = @import("std");
const abi_resolver = @import("abi_resolver.zig");
const rpc_client = @import("rpc_client.zig");

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
        _ = params; // TODO: Implement parameter encoding

        // Get function selector
        const selector = try self.calculateFunctionSelector(function);

        // Start with selector
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

        // TODO: Encode and append parameters using zabi encoding library
        // For now, just return selector

        return data.toOwnedSlice(self.allocator);
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

    const params = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };

    const data = try builder.encodeFunctionCall(&function, params);
    defer allocator.free(data);

    // Should start with "0x"
    try testing.expect(std.mem.startsWith(u8, data, "0x"));

    // Should have at least selector (4 bytes = 8 hex chars + "0x" = 10 chars)
    try testing.expect(data.len >= 10);
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
