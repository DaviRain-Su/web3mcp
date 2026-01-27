//! EVM JSON-RPC Client
//!
//! Generic JSON-RPC client for all EVM-compatible chains (BSC, Ethereum, Polygon, etc.)
//! Implements standard Ethereum JSON-RPC methods: https://ethereum.org/en/developers/docs/apis/json-rpc/

const std = @import("std");
const chains = @import("chains.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const evm_helpers = @import("../../core/evm_helpers.zig");

/// JSON-RPC request
const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: u64,
    method: []const u8,
    params: std.json.Value,
};

/// JSON-RPC response
const JsonRpcResponse = struct {
    jsonrpc: []const u8,
    id: u64,
    result: ?std.json.Value = null,
    @"error": ?JsonRpcError = null,
};

/// JSON-RPC error
const JsonRpcError = struct {
    code: i64,
    message: []const u8,
    data: ?std.json.Value = null,
};

/// EVM RPC Client
pub const EvmRpcClient = struct {
    allocator: std.mem.Allocator,
    chain_config: chains.ChainConfig,
    rpc_url: []const u8,
    next_request_id: u64,

    /// Initialize EVM RPC client
    pub fn init(
        allocator: std.mem.Allocator,
        chain_config: chains.ChainConfig,
    ) !EvmRpcClient {
        return EvmRpcClient{
            .allocator = allocator,
            .chain_config = chain_config,
            .rpc_url = chain_config.rpc_url,
            .next_request_id = 1,
        };
    }

    /// Initialize with custom RPC URL
    pub fn initWithUrl(
        allocator: std.mem.Allocator,
        chain_config: chains.ChainConfig,
        rpc_url: []const u8,
    ) !EvmRpcClient {
        return EvmRpcClient{
            .allocator = allocator,
            .chain_config = chain_config,
            .rpc_url = rpc_url,
            .next_request_id = 1,
        };
    }

    /// Get next request ID
    fn getNextRequestId(self: *EvmRpcClient) u64 {
        const id = self.next_request_id;
        self.next_request_id += 1;
        return id;
    }

    /// Make JSON-RPC call
    fn call(
        self: *EvmRpcClient,
        method: []const u8,
        params: std.json.Value,
    ) !std.json.Value {
        const request = JsonRpcRequest{
            .id = self.getNextRequestId(),
            .method = method,
            .params = params,
        };

        // Serialize request
        const request_value = std.json.Value{
            .object = blk: {
                var obj = std.json.ObjectMap.init(self.allocator);
                try obj.put("jsonrpc", .{ .string = request.jsonrpc });
                try obj.put("id", .{ .integer = @intCast(request.id) });
                try obj.put("method", .{ .string = request.method });
                try obj.put("params", request.params);
                break :blk obj;
            },
        };
        const request_json = try evm_helpers.jsonStringifyAlloc(self.allocator, request_value);
        defer self.allocator.free(request_json);

        // Make HTTP POST request
        var client = std.http.Client{ .allocator = self.allocator, .io = evm_runtime.io() };
        defer client.deinit();

        var response_buf: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer response_buf.deinit();

        const headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };

        const fetch_result = client.fetch(.{
            .location = .{ .url = self.rpc_url },
            .method = .POST,
            .payload = request_json,
            .response_writer = &response_buf.writer,
            .extra_headers = &headers,
        }) catch |err| {
            response_buf.deinit();
            std.log.err("RPC request failed: {}", .{err});
            return error.RpcRequestFailed;
        };

        if (fetch_result.status.class() != .success) {
            response_buf.deinit();
            std.log.err("RPC request returned status: {}", .{fetch_result.status});
            return error.RpcRequestFailed;
        }

        const response_data = try response_buf.toOwnedSlice();
        defer self.allocator.free(response_data);

        // Parse JSON-RPC response
        const parsed = try std.json.parseFromSlice(
            JsonRpcResponse,
            self.allocator,
            response_data,
            .{ .allocate = .alloc_always },
        );
        errdefer parsed.deinit();

        // Check for JSON-RPC error
        if (parsed.value.@"error") |rpc_error| {
            std.log.err("RPC error {d}: {s}", .{ rpc_error.code, rpc_error.message });
            parsed.deinit();
            return error.RpcError;
        }

        // Return result (caller must deinit the parsed value)
        if (parsed.value.result) |result| {
            // Transfer ownership - caller must call deinit on parsed
            return result;
        }

        parsed.deinit();
        return error.RpcNoResult;
    }

    // ============ Standard Ethereum JSON-RPC Methods ============

    /// eth_chainId - Returns the chain ID
    pub fn ethChainId(self: *EvmRpcClient) !u64 {
        var params_array = std.json.Array.init(self.allocator);
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_chainId", params);

        if (result == .string) {
            return try parseHexU64(result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_blockNumber - Returns the current block number
    pub fn ethBlockNumber(self: *EvmRpcClient) !u64 {
        var params_array = std.json.Array.init(self.allocator);
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_blockNumber", params);

        if (result == .string) {
            return try parseHexU64(result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_getBalance - Returns the balance of an account
    pub fn ethGetBalance(
        self: *EvmRpcClient,
        address: []const u8,
        block_tag: BlockTag,
    ) ![]const u8 {
        var params_array = std.json.Array.init(self.allocator);
        try params_array.append( .{ .string = address });
        try params_array.append( .{ .string = block_tag.toString() });
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_getBalance", params);

        if (result == .string) {
            // Return owned copy of the balance string
            return try self.allocator.dupe(u8, result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_getTransactionCount - Returns the nonce of an account
    pub fn ethGetTransactionCount(
        self: *EvmRpcClient,
        address: []const u8,
        block_tag: BlockTag,
    ) !u64 {
        var params_array = std.json.Array.init(self.allocator);
        try params_array.append( .{ .string = address });
        try params_array.append( .{ .string = block_tag.toString() });
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_getTransactionCount", params);

        if (result == .string) {
            return try parseHexU64(result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_gasPrice - Returns the current gas price in wei (as hex string)
    pub fn ethGasPrice(self: *EvmRpcClient) ![]const u8 {
        var params_array = std.json.Array.init(self.allocator);
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_gasPrice", params);

        if (result == .string) {
            return try self.allocator.dupe(u8, result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_estimateGas - Estimates gas for a transaction
    pub fn ethEstimateGas(
        self: *EvmRpcClient,
        transaction: TransactionRequest,
    ) !u64 {
        var params_array = std.json.Array.init(self.allocator);
        defer params_array.deinit();

        // Serialize transaction to JSON object
        const tx_obj = try serializeTransactionRequest(self.allocator, transaction);
        try params_array.append( .{ .object = tx_obj });

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_estimateGas", params);

        if (result == .string) {
            return try parseHexU64(result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_call - Executes a read-only call
    pub fn ethCall(
        self: *EvmRpcClient,
        transaction: TransactionRequest,
        block_tag: BlockTag,
    ) ![]const u8 {
        var params_array = std.json.Array.init(self.allocator);
        defer params_array.deinit();

        // Serialize transaction to JSON object
        const tx_obj = try serializeTransactionRequest(self.allocator, transaction);
        try params_array.append( .{ .object = tx_obj });
        try params_array.append( .{ .string = block_tag.toString() });

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_call", params);

        if (result == .string) {
            return try self.allocator.dupe(u8, result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_sendRawTransaction - Sends a signed transaction
    pub fn ethSendRawTransaction(
        self: *EvmRpcClient,
        signed_tx: []const u8,
    ) ![]const u8 {
        var params_array = std.json.Array.init(self.allocator);
        try params_array.append( .{ .string = signed_tx });
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_sendRawTransaction", params);

        if (result == .string) {
            return try self.allocator.dupe(u8, result.string);
        }

        return error.InvalidResponse;
    }

    /// eth_getTransactionReceipt - Gets transaction receipt
    pub fn ethGetTransactionReceipt(
        self: *EvmRpcClient,
        tx_hash: []const u8,
    ) !?TransactionReceipt {
        var params_array = std.json.Array.init(self.allocator);
        try params_array.append( .{ .string = tx_hash });
        defer params_array.deinit();

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_getTransactionReceipt", params);

        // Receipt can be null if transaction not yet mined
        if (result == .null) {
            return null;
        }

        if (result == .object) {
            // Parse receipt object
            const obj = result.object;

            const tx_hash_str = if (obj.get("transactionHash")) |h| h.string else return error.InvalidReceipt;
            const block_hash_str = if (obj.get("blockHash")) |h| h.string else return error.InvalidReceipt;
            const from_str = if (obj.get("from")) |f| f.string else return error.InvalidReceipt;

            const tx_index = if (obj.get("transactionIndex")) |idx| try parseHexU64(idx.string) else return error.InvalidReceipt;
            const block_num = if (obj.get("blockNumber")) |bn| try parseHexU64(bn.string) else return error.InvalidReceipt;
            const gas_used = if (obj.get("gasUsed")) |gu| try parseHexU64(gu.string) else return error.InvalidReceipt;
            const cumulative_gas = if (obj.get("cumulativeGasUsed")) |cg| try parseHexU64(cg.string) else return error.InvalidReceipt;
            const status = if (obj.get("status")) |s| try parseHexU64(s.string) else return error.InvalidReceipt;

            const to_str = if (obj.get("to")) |t| if (t == .string) t.string else null else null;
            const contract_addr = if (obj.get("contractAddress")) |ca| if (ca == .string) ca.string else null else null;

            return TransactionReceipt{
                .transactionHash = try self.allocator.dupe(u8, tx_hash_str),
                .transactionIndex = tx_index,
                .blockHash = try self.allocator.dupe(u8, block_hash_str),
                .blockNumber = block_num,
                .from = try self.allocator.dupe(u8, from_str),
                .to = if (to_str) |t| try self.allocator.dupe(u8, t) else null,
                .cumulativeGasUsed = cumulative_gas,
                .gasUsed = gas_used,
                .contractAddress = if (contract_addr) |ca| try self.allocator.dupe(u8, ca) else null,
                .status = status,
                .logs = &[_]Log{}, // TODO: Parse logs array
            };
        }

        return error.InvalidResponse;
    }

    /// eth_getBlockByNumber - Gets block by number
    pub fn ethGetBlockByNumber(
        self: *EvmRpcClient,
        block_number: u64,
        include_transactions: bool,
    ) !?Block {
        var params_array = std.json.Array.init(self.allocator);
        defer params_array.deinit();

        const block_hex = try std.fmt.allocPrint(self.allocator, "0x{x}", .{block_number});
        defer self.allocator.free(block_hex);

        try params_array.append( .{ .string = block_hex });
        try params_array.append( .{ .bool = include_transactions });

        const params = std.json.Value{ .array = params_array };
        const result = try self.call("eth_getBlockByNumber", params);

        // Block can be null if not found
        if (result == .null) {
            return null;
        }

        if (result == .object) {
            const obj = result.object;

            const hash_str = if (obj.get("hash")) |h| h.string else return error.InvalidBlock;
            const parent_hash_str = if (obj.get("parentHash")) |ph| ph.string else return error.InvalidBlock;

            const number = if (obj.get("number")) |n| try parseHexU64(n.string) else return error.InvalidBlock;
            const timestamp = if (obj.get("timestamp")) |ts| try parseHexU64(ts.string) else return error.InvalidBlock;
            const gas_limit = if (obj.get("gasLimit")) |gl| try parseHexU64(gl.string) else return error.InvalidBlock;
            const gas_used = if (obj.get("gasUsed")) |gu| try parseHexU64(gu.string) else return error.InvalidBlock;

            const base_fee = if (obj.get("baseFeePerGas")) |bf|
                if (bf == .string) try self.allocator.dupe(u8, bf.string) else null
            else
                null;

            return Block{
                .number = number,
                .hash = try self.allocator.dupe(u8, hash_str),
                .parentHash = try self.allocator.dupe(u8, parent_hash_str),
                .timestamp = timestamp,
                .gasLimit = gas_limit,
                .gasUsed = gas_used,
                .baseFeePerGas = base_fee,
                .transactions = "", // TODO: Parse transactions array
            };
        }

        return error.InvalidResponse;
    }

    /// Serialize TransactionRequest to JSON object
    fn serializeTransactionRequest(
        allocator: std.mem.Allocator,
        tx: TransactionRequest,
    ) !std.json.ObjectMap {
        var obj = std.json.ObjectMap.init(allocator);

        if (tx.from) |from| {
            try obj.put("from", .{ .string = from });
        }

        if (tx.to) |to| {
            try obj.put("to", .{ .string = to });
        }

        if (tx.gas) |gas| {
            const gas_hex = try formatHexU64(allocator, gas);
            try obj.put("gas", .{ .string = gas_hex });
        }

        if (tx.gasPrice) |gas_price| {
            try obj.put("gasPrice", .{ .string = gas_price });
        }

        if (tx.value) |value| {
            try obj.put("value", .{ .string = value });
        }

        if (tx.data) |data| {
            try obj.put("data", .{ .string = data });
        }

        if (tx.nonce) |nonce| {
            const nonce_hex = try formatHexU64(allocator, nonce);
            try obj.put("nonce", .{ .string = nonce_hex });
        }

        return obj;
    }
};

/// Block tag for specifying block number
pub const BlockTag = enum {
    latest,
    earliest,
    pending,
    safe,
    finalized,

    pub fn toString(self: BlockTag) []const u8 {
        return switch (self) {
            .latest => "latest",
            .earliest => "earliest",
            .pending => "pending",
            .safe => "safe",
            .finalized => "finalized",
        };
    }
};

/// Transaction request for eth_call and eth_estimateGas
pub const TransactionRequest = struct {
    from: ?[]const u8 = null,
    to: ?[]const u8 = null,
    gas: ?u64 = null,
    gasPrice: ?[]const u8 = null,
    value: ?[]const u8 = null,
    data: ?[]const u8 = null,
    nonce: ?u64 = null,
};

/// Transaction receipt
pub const TransactionReceipt = struct {
    transactionHash: []const u8,
    transactionIndex: u64,
    blockHash: []const u8,
    blockNumber: u64,
    from: []const u8,
    to: ?[]const u8,
    cumulativeGasUsed: u64,
    gasUsed: u64,
    contractAddress: ?[]const u8,
    status: u64, // 1 for success, 0 for failure
    logs: []Log,

    /// Free allocated fields
    pub fn deinit(self: TransactionReceipt, allocator: std.mem.Allocator) void {
        allocator.free(self.transactionHash);
        allocator.free(self.blockHash);
        allocator.free(self.from);
        if (self.to) |to| allocator.free(to);
        if (self.contractAddress) |ca| allocator.free(ca);
        // Note: logs array cleanup not implemented yet
    }
};

/// Event log
pub const Log = struct {
    address: []const u8,
    topics: [][]const u8,
    data: []const u8,
    blockNumber: u64,
    transactionHash: []const u8,
    transactionIndex: u64,
    blockHash: []const u8,
    logIndex: u64,
    removed: bool,
};

/// Block information
pub const Block = struct {
    number: u64,
    hash: []const u8,
    parentHash: []const u8,
    timestamp: u64,
    gasLimit: u64,
    gasUsed: u64,
    baseFeePerGas: ?[]const u8,
    transactions: []const u8, // Array of tx hashes or full txs

    /// Free allocated fields
    pub fn deinit(self: Block, allocator: std.mem.Allocator) void {
        allocator.free(self.hash);
        allocator.free(self.parentHash);
        if (self.baseFeePerGas) |fee| allocator.free(fee);
        // Note: transactions array cleanup not implemented yet
    }
};

// ============ Utility Functions ============

/// Parse hex string to u64
pub fn parseHexU64(hex_str: []const u8) !u64 {
    // Remove "0x" prefix if present
    const str = if (std.mem.startsWith(u8, hex_str, "0x"))
        hex_str[2..]
    else
        hex_str;

    if (str.len == 0) return 0;

    return try std.fmt.parseInt(u64, str, 16);
}

/// Format u64 to hex string with "0x" prefix
pub fn formatHexU64(allocator: std.mem.Allocator, value: u64) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "0x{x}", .{value});
}

/// Parse hex string to bytes (for addresses, hashes, etc.)
pub fn parseHexBytes(allocator: std.mem.Allocator, hex_str: []const u8) ![]u8 {
    // Remove "0x" prefix if present
    const str = if (std.mem.startsWith(u8, hex_str, "0x"))
        hex_str[2..]
    else
        hex_str;

    if (str.len % 2 != 0) return error.InvalidHexLength;

    const bytes = try allocator.alloc(u8, str.len / 2);
    errdefer allocator.free(bytes);

    var i: usize = 0;
    while (i < str.len) : (i += 2) {
        bytes[i / 2] = try std.fmt.parseInt(u8, str[i .. i + 2], 16);
    }

    return bytes;
}

/// Format bytes to hex string with "0x" prefix
pub fn formatHexBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, 2 + bytes.len * 2);
    result[0] = '0';
    result[1] = 'x';

    const hex_chars = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        result[2 + i * 2] = hex_chars[byte >> 4];
        result[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    return result;
}

// Tests
const testing = std.testing;

test "EvmRpcClient initialization" {
    const allocator = testing.allocator;

    var client = try EvmRpcClient.init(allocator, chains.BSC_MAINNET);
    try testing.expectEqual(@as(u64, 56), client.chain_config.chain_id);
    try testing.expectEqualStrings("BSC", client.chain_config.name);
}

test "EvmRpcClient with custom URL" {
    const allocator = testing.allocator;

    var client = try EvmRpcClient.initWithUrl(
        allocator,
        chains.BSC_MAINNET,
        "https://custom-rpc.example.com",
    );
    try testing.expectEqualStrings("https://custom-rpc.example.com", client.rpc_url);
}

test "request ID increments" {
    const allocator = testing.allocator;

    var client = try EvmRpcClient.init(allocator, chains.BSC_MAINNET);
    const id1 = client.getNextRequestId();
    const id2 = client.getNextRequestId();
    const id3 = client.getNextRequestId();

    try testing.expectEqual(@as(u64, 1), id1);
    try testing.expectEqual(@as(u64, 2), id2);
    try testing.expectEqual(@as(u64, 3), id3);
}

test "BlockTag toString" {
    try testing.expectEqualStrings("latest", BlockTag.latest.toString());
    try testing.expectEqualStrings("earliest", BlockTag.earliest.toString());
    try testing.expectEqualStrings("pending", BlockTag.pending.toString());
    try testing.expectEqualStrings("safe", BlockTag.safe.toString());
    try testing.expectEqualStrings("finalized", BlockTag.finalized.toString());
}

test "parseHexU64" {
    try testing.expectEqual(@as(u64, 0), try parseHexU64("0x0"));
    try testing.expectEqual(@as(u64, 255), try parseHexU64("0xff"));
    try testing.expectEqual(@as(u64, 4096), try parseHexU64("0x1000"));
    try testing.expectEqual(@as(u64, 56), try parseHexU64("0x38")); // BSC chain ID
    try testing.expectEqual(@as(u64, 1), try parseHexU64("0x1")); // Ethereum chain ID

    // Without 0x prefix
    try testing.expectEqual(@as(u64, 255), try parseHexU64("ff"));
    try testing.expectEqual(@as(u64, 4096), try parseHexU64("1000"));
}

test "formatHexU64" {
    const allocator = testing.allocator;

    const hex0 = try formatHexU64(allocator, 0);
    defer allocator.free(hex0);
    try testing.expectEqualStrings("0x0", hex0);

    const hex255 = try formatHexU64(allocator, 255);
    defer allocator.free(hex255);
    try testing.expectEqualStrings("0xff", hex255);

    const hex56 = try formatHexU64(allocator, 56);
    defer allocator.free(hex56);
    try testing.expectEqualStrings("0x38", hex56);
}

test "parseHexBytes" {
    const allocator = testing.allocator;

    // Empty bytes
    const empty = try parseHexBytes(allocator, "0x");
    defer allocator.free(empty);
    try testing.expectEqual(@as(usize, 0), empty.len);

    // Single byte
    const single = try parseHexBytes(allocator, "0xff");
    defer allocator.free(single);
    try testing.expectEqual(@as(usize, 1), single.len);
    try testing.expectEqual(@as(u8, 0xff), single[0]);

    // Address (20 bytes)
    const addr = try parseHexBytes(allocator, "0x" ++ "00" ** 20);
    defer allocator.free(addr);
    try testing.expectEqual(@as(usize, 20), addr.len);
}

test "formatHexBytes" {
    const allocator = testing.allocator;

    // Empty bytes
    const empty = try formatHexBytes(allocator, &[_]u8{});
    defer allocator.free(empty);
    try testing.expectEqualStrings("0x", empty);

    // Single byte
    const single = try formatHexBytes(allocator, &[_]u8{0xff});
    defer allocator.free(single);
    try testing.expectEqualStrings("0xff", single);

    // Multiple bytes
    const multi = try formatHexBytes(allocator, &[_]u8{ 0xde, 0xad, 0xbe, 0xef });
    defer allocator.free(multi);
    try testing.expectEqualStrings("0xdeadbeef", multi);
}

test "serializeTransactionRequest minimal" {
    const allocator = testing.allocator;

    const tx = TransactionRequest{
        .to = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
    };

    var obj = try EvmRpcClient.serializeTransactionRequest(allocator, tx);
    defer obj.deinit();

    try testing.expect(obj.contains("to"));
    try testing.expect(!obj.contains("from"));
    try testing.expect(!obj.contains("value"));
}

test "serializeTransactionRequest full" {
    const allocator = testing.allocator;

    const tx = TransactionRequest{
        .from = "0x1234567890123456789012345678901234567890",
        .to = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
        .gas = 21000,
        .gasPrice = "0x3b9aca00", // 1 gwei
        .value = "0xde0b6b3a7640000", // 1 ETH
        .data = "0x",
        .nonce = 42,
    };

    var obj = try EvmRpcClient.serializeTransactionRequest(allocator, tx);
    defer {
        // Free allocated hex strings
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, "gas") or
                std.mem.eql(u8, entry.key_ptr.*, "nonce"))
            {
                if (entry.value_ptr.* == .string) {
                    allocator.free(entry.value_ptr.*.string);
                }
            }
        }
        obj.deinit();
    }

    try testing.expect(obj.contains("from"));
    try testing.expect(obj.contains("to"));
    try testing.expect(obj.contains("gas"));
    try testing.expect(obj.contains("gasPrice"));
    try testing.expect(obj.contains("value"));
    try testing.expect(obj.contains("data"));
    try testing.expect(obj.contains("nonce"));

    try testing.expectEqual(@as(usize, 7), obj.count());
}
