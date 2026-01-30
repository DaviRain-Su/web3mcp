const std = @import("std");
const http = std.http;
const json = std.json;
pub const types = @import("types.zig");
pub const filters = @import("filters.zig");
const Io = std.Io;

pub const RpcError = error{
    TransportUnavailable,
    InvalidJsonRpcResponse,
    InvalidUtf8,
};

pub const Transport = struct {
    ctx: *anyopaque,
    sendFn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, request: []const u8) anyerror![]u8,

    pub fn send(self: Transport, allocator: std.mem.Allocator, request: []const u8) anyerror![]u8 {
        return self.sendFn(self.ctx, allocator, request);
    }
};

pub const HttpTransport = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    client: http.Client,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, endpoint: []const u8) HttpTransport {
        return .{
            .allocator = allocator,
            .endpoint = endpoint,
            .client = .{ .allocator = allocator, .io = io },
        };
    }

    pub fn deinit(self: *HttpTransport) void {
        self.client.deinit();
        self.* = undefined;
    }

    pub fn transport(self: *HttpTransport) Transport {
        return .{ .ctx = self, .sendFn = sendHttp };
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    transport: ?Transport,
    next_id: u64,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) Client {
        return .{ .allocator = allocator, .endpoint = endpoint, .transport = null, .next_id = 1 };
    }

    pub fn initWithTransport(allocator: std.mem.Allocator, endpoint: []const u8, transport: Transport) Client {
        return .{ .allocator = allocator, .endpoint = endpoint, .transport = transport, .next_id = 1 };
    }

    pub fn setTransport(self: *Client, transport: Transport) void {
        self.transport = transport;
    }

    pub fn callRaw(self: *Client, method: []const u8, params_json: []const u8, id: u64) anyerror![]u8 {
        const transport = self.transport orelse return RpcError.TransportUnavailable;
        var request = std.ArrayList(u8).initCapacity(self.allocator, 128) catch return error.OutOfMemory;
        defer request.deinit(self.allocator);

        try writeRequest(&request, self.allocator, method, params_json, id);
        const payload = try request.toOwnedSlice(self.allocator);
        defer self.allocator.free(payload);

        return try transport.send(self.allocator, payload);
    }

    pub fn call(self: *Client, method: []const u8, params_json: []const u8) anyerror![]u8 {
        const id = self.next_id;
        self.next_id += 1;
        return self.callRaw(method, params_json, id);
    }

    pub fn getReferenceGasPrice(self: *Client) anyerror![]u8 {
        return self.call("suix_getReferenceGasPrice", "[]");
    }

    pub fn getLatestSuiSystemState(self: *Client) anyerror![]u8 {
        return self.call("suix_getLatestSuiSystemState", "[]");
    }

    pub fn getChainIdentifier(self: *Client) anyerror![]u8 {
        return self.call("sui_getChainIdentifier", "[]");
    }

    pub fn getObject(self: *Client, object_id: []const u8) anyerror![]u8 {
        const params = try paramsSingleString(self.allocator, object_id);
        defer self.allocator.free(params);
        return self.call("sui_getObject", params);
    }

    pub fn getOwnedObjects(self: *Client, owner: []const u8, options_json: []const u8) anyerror![]u8 {
        const params = try paramsOwnedObjects(self.allocator, owner, options_json);
        defer self.allocator.free(params);
        return self.call("suix_getOwnedObjects", params);
    }

    pub fn getOwnedObjectsWithQuery(
        self: *Client,
        owner: []const u8,
        query: filters.OwnedObjectsQuery,
        cursor_json: ?[]const u8,
        limit: ?u64,
    ) anyerror![]u8 {
        const query_json = try query.toJson(self.allocator);
        defer self.allocator.free(query_json);
        const params = try paramsOwnedObjectsQuery(self.allocator, owner, query_json, cursor_json, limit);
        defer self.allocator.free(params);
        return self.call("suix_getOwnedObjects", params);
    }

    pub fn executeTransactionBlock(
        self: *Client,
        tx_bytes_base64: []const u8,
        signatures_json: []const u8,
        options_json: []const u8,
        request_type: []const u8,
    ) anyerror![]u8 {
        const params = try paramsExecuteTransactionBlock(
            self.allocator,
            tx_bytes_base64,
            signatures_json,
            options_json,
            request_type,
        );
        defer self.allocator.free(params);
        return self.call("sui_executeTransactionBlock", params);
    }

    pub fn getEvents(self: *Client, tx_digest: []const u8) anyerror![]u8 {
        const params = try paramsSingleString(self.allocator, tx_digest);
        defer self.allocator.free(params);
        return self.call("sui_getEvents", params);
    }

    pub fn getTransactionBlock(self: *Client, digest: []const u8, options_json: []const u8) anyerror![]u8 {
        const params = try paramsTwoStringRaw(self.allocator, digest, options_json);
        defer self.allocator.free(params);
        return self.call("sui_getTransactionBlock", params);
    }

    pub fn tryGetPastObject(self: *Client, object_id: []const u8, version: u64) anyerror![]u8 {
        const params = try paramsPastObject(self.allocator, object_id, version);
        defer self.allocator.free(params);
        return self.call("sui_tryGetPastObject", params);
    }

    pub fn getCoins(
        self: *Client,
        owner: []const u8,
        coin_type: ?[]const u8,
        cursor_json: ?[]const u8,
        limit: ?u64,
    ) anyerror![]u8 {
        const params = try paramsGetCoins(self.allocator, owner, coin_type, cursor_json, limit);
        defer self.allocator.free(params);
        return self.call("suix_getCoins", params);
    }

    pub fn getCoinsRaw(
        self: *Client,
        owner: []const u8,
        coin_type_json: ?[]const u8,
        cursor_json: ?[]const u8,
        limit: ?u64,
    ) anyerror![]u8 {
        const params = try paramsGetCoinsRaw(self.allocator, owner, coin_type_json, cursor_json, limit);
        defer self.allocator.free(params);
        return self.call("suix_getCoins", params);
    }

    pub fn getCoinsWithFilter(
        self: *Client,
        owner: []const u8,
        filter: filters.CoinFilter,
        cursor_json: ?[]const u8,
        limit: ?u64,
    ) anyerror![]u8 {
        const filter_json = try filter.toJson(self.allocator);
        defer self.allocator.free(filter_json);
        const params = try paramsGetCoinsRaw(self.allocator, owner, filter_json, cursor_json, limit);
        defer self.allocator.free(params);
        return self.call("suix_getCoins", params);
    }

    pub fn getBalance(self: *Client, owner: []const u8, coin_type: ?[]const u8) anyerror![]u8 {
        const params = try paramsGetBalance(self.allocator, owner, coin_type);
        defer self.allocator.free(params);
        return self.call("suix_getBalance", params);
    }

    pub fn getAllBalances(self: *Client, owner: []const u8) anyerror![]u8 {
        const params = try paramsSingleString(self.allocator, owner);
        defer self.allocator.free(params);
        return self.call("suix_getAllBalances", params);
    }

    pub fn getLatestCheckpointSequenceNumber(self: *Client) anyerror![]u8 {
        return self.call("sui_getLatestCheckpointSequenceNumber", "[]");
    }

    pub fn getDynamicFields(
        self: *Client,
        parent_object_id: []const u8,
        cursor_json: ?[]const u8,
        limit: ?u64,
    ) anyerror![]u8 {
        const params = try paramsDynamicFields(self.allocator, parent_object_id, cursor_json, limit);
        defer self.allocator.free(params);
        return self.call("suix_getDynamicFields", params);
    }

    pub fn getDynamicFieldObject(
        self: *Client,
        parent_object_id: []const u8,
        name_json: []const u8,
    ) anyerror![]u8 {
        const params = try paramsTwoStringRaw(self.allocator, parent_object_id, name_json);
        defer self.allocator.free(params);
        return self.call("suix_getDynamicFieldObject", params);
    }

    pub fn getTotalSupply(self: *Client, coin_type: []const u8) anyerror![]u8 {
        const params = try paramsSingleString(self.allocator, coin_type);
        defer self.allocator.free(params);
        return self.call("suix_getTotalSupply", params);
    }

    pub fn getCoinMetadata(self: *Client, coin_type: []const u8) anyerror![]u8 {
        const params = try paramsSingleString(self.allocator, coin_type);
        defer self.allocator.free(params);
        return self.call("suix_getCoinMetadata", params);
    }

    pub fn multiGetTransactionBlocks(
        self: *Client,
        digests: []const []const u8,
        options_json: []const u8,
    ) anyerror![]u8 {
        const digests_json = try jsonArrayOfStrings(self.allocator, digests);
        defer self.allocator.free(digests_json);
        const params = try paramsTwoRaw(self.allocator, digests_json, options_json);
        defer self.allocator.free(params);
        return self.call("sui_multiGetTransactionBlocks", params);
    }

    pub fn getNormalizedMoveModulesByPackage(self: *Client, package: []const u8) anyerror![]u8 {
        const params = try paramsSingleString(self.allocator, package);
        defer self.allocator.free(params);
        return self.call("sui_getNormalizedMoveModulesByPackage", params);
    }

    pub fn getNormalizedMoveModule(self: *Client, package: []const u8, module: []const u8) anyerror![]u8 {
        const params = try paramsTwoStrings(self.allocator, package, module);
        defer self.allocator.free(params);
        return self.call("sui_getNormalizedMoveModule", params);
    }

    pub fn getNormalizedMoveFunction(
        self: *Client,
        package: []const u8,
        module: []const u8,
        function: []const u8,
    ) anyerror![]u8 {
        const params = try paramsThreeStrings(self.allocator, package, module, function);
        defer self.allocator.free(params);
        return self.call("sui_getNormalizedMoveFunction", params);
    }

    pub fn getNormalizedMoveStruct(
        self: *Client,
        package: []const u8,
        module: []const u8,
        struct_name: []const u8,
    ) anyerror![]u8 {
        const params = try paramsThreeStrings(self.allocator, package, module, struct_name);
        defer self.allocator.free(params);
        return self.call("sui_getNormalizedMoveStruct", params);
    }

    pub fn multiGetObjects(self: *Client, object_ids_json: []const u8, options_json: []const u8) anyerror![]u8 {
        const params = try paramsTwoRaw(self.allocator, object_ids_json, options_json);
        defer self.allocator.free(params);
        return self.call("sui_multiGetObjects", params);
    }

    pub fn queryTransactionBlocks(
        self: *Client,
        query_json: []const u8,
        options_json: []const u8,
        cursor_json: ?[]const u8,
        limit: ?u64,
        descending: ?bool,
    ) anyerror![]u8 {
        const params = try paramsQueryTransactionBlocks(
            self.allocator,
            query_json,
            options_json,
            cursor_json,
            limit,
            descending,
        );
        defer self.allocator.free(params);
        return self.call("suix_queryTransactionBlocks", params);
    }

    pub fn queryTransactionBlocksWithFilter(
        self: *Client,
        query: filters.TransactionQuery,
        options_json: []const u8,
        cursor_json: ?[]const u8,
        limit: ?u64,
        descending: ?bool,
    ) anyerror![]u8 {
        const query_json = try query.toJson(self.allocator);
        defer self.allocator.free(query_json);
        return self.queryTransactionBlocks(query_json, options_json, cursor_json, limit, descending);
    }

    pub fn getTransactionBlocks(
        self: *Client,
        query_json: []const u8,
        cursor_json: ?[]const u8,
        limit: ?u64,
        descending: ?bool,
    ) anyerror![]u8 {
        const params = try paramsGetTransactionBlocks(
            self.allocator,
            query_json,
            cursor_json,
            limit,
            descending,
        );
        defer self.allocator.free(params);
        return self.call("sui_getTransactionBlocks", params);
    }

    pub fn getCheckpoint(self: *Client, checkpoint_id_json: []const u8) anyerror![]u8 {
        const params = try paramsSingleRaw(self.allocator, checkpoint_id_json);
        defer self.allocator.free(params);
        return self.call("sui_getCheckpoint", params);
    }
};

fn writeRequest(list: *std.ArrayList(u8), allocator: std.mem.Allocator, method: []const u8, params_json: []const u8, id: u64) !void {
    try list.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeUnsigned(list, allocator, id);
    try list.appendSlice(allocator, ",\"method\":");
    try writeJsonString(list, allocator, method);
    try list.appendSlice(allocator, ",\"params\":");
    try list.appendSlice(allocator, params_json);
    try list.append(allocator, '}');
}

fn writeUnsigned(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [20]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{}", .{value}) catch return error.OutOfMemory;
    try list.appendSlice(allocator, slice);
}

fn writeJsonString(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try list.append(allocator, '"');
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        const c = value[i];
        switch (c) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => try list.append(allocator, c),
        }
    }
    try list.append(allocator, '"');
}

pub fn paramsSingleString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, value.len + 4);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, value);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsSingleRaw(allocator: std.mem.Allocator, value_json: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, value_json.len + 2);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try list.appendSlice(allocator, value_json);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsTwoStringRaw(allocator: std.mem.Allocator, first: []const u8, second_raw: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, first.len + second_raw.len + 6);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, first);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, second_raw);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsTwoStrings(allocator: std.mem.Allocator, first: []const u8, second: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, first.len + second.len + 6);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, first);
    try list.append(allocator, ',');
    try writeJsonString(&list, allocator, second);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsArrayRaw(allocator: std.mem.Allocator, values: []const []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 16);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        if (i != 0) try list.append(allocator, ',');
        try list.appendSlice(allocator, values[i]);
    }
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsTwoRaw(allocator: std.mem.Allocator, first: []const u8, second: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, first.len + second.len + 4);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try list.appendSlice(allocator, first);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, second);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsOwnedObjects(allocator: std.mem.Allocator, owner: []const u8, options_json: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, owner.len + options_json.len + 8);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, owner);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, options_json);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsOwnedObjectsQuery(
    allocator: std.mem.Allocator,
    owner: []const u8,
    query_json: []const u8,
    cursor_json: ?[]const u8,
    limit: ?u64,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, owner.len + query_json.len + 24);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, owner);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, query_json);
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, cursor_json);
    try list.append(allocator, ',');
    try writeOptionalU64Json(&list, allocator, limit);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsExecuteTransactionBlock(
    allocator: std.mem.Allocator,
    tx_bytes_base64: []const u8,
    signatures_json: []const u8,
    options_json: []const u8,
    request_type: []const u8,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, tx_bytes_base64.len + signatures_json.len + options_json.len + request_type.len + 12);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, tx_bytes_base64);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, signatures_json);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, options_json);
    try list.append(allocator, ',');
    try writeJsonString(&list, allocator, request_type);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsQueryTransactionBlocks(
    allocator: std.mem.Allocator,
    query_json: []const u8,
    options_json: []const u8,
    cursor_json: ?[]const u8,
    limit: ?u64,
    descending: ?bool,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, query_json.len + options_json.len + 32);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try list.appendSlice(allocator, query_json);
    try list.append(allocator, ',');
    try list.appendSlice(allocator, options_json);
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, cursor_json);
    try list.append(allocator, ',');
    try writeOptionalU64Json(&list, allocator, limit);
    try list.append(allocator, ',');
    try writeOptionalBoolJson(&list, allocator, descending);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsGetTransactionBlocks(
    allocator: std.mem.Allocator,
    query_json: []const u8,
    cursor_json: ?[]const u8,
    limit: ?u64,
    descending: ?bool,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, query_json.len + 24);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try list.appendSlice(allocator, query_json);
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, cursor_json);
    try list.append(allocator, ',');
    try writeOptionalU64Json(&list, allocator, limit);
    try list.append(allocator, ',');
    try writeOptionalBoolJson(&list, allocator, descending);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsThreeStrings(
    allocator: std.mem.Allocator,
    first: []const u8,
    second: []const u8,
    third: []const u8,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, first.len + second.len + third.len + 8);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, first);
    try list.append(allocator, ',');
    try writeJsonString(&list, allocator, second);
    try list.append(allocator, ',');
    try writeJsonString(&list, allocator, third);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsPastObject(allocator: std.mem.Allocator, object_id: []const u8, version: u64) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, object_id.len + 24);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, object_id);
    try list.append(allocator, ',');
    try writeUnsigned(&list, allocator, version);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsGetCoins(
    allocator: std.mem.Allocator,
    owner: []const u8,
    coin_type: ?[]const u8,
    cursor_json: ?[]const u8,
    limit: ?u64,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, owner.len + 32);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, owner);
    try list.append(allocator, ',');
    if (coin_type) |value| {
        try writeJsonString(&list, allocator, value);
    } else {
        try list.appendSlice(allocator, "null");
    }
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, cursor_json);
    try list.append(allocator, ',');
    try writeOptionalU64Json(&list, allocator, limit);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsGetCoinsRaw(
    allocator: std.mem.Allocator,
    owner: []const u8,
    coin_type_json: ?[]const u8,
    cursor_json: ?[]const u8,
    limit: ?u64,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, owner.len + 32);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, owner);
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, coin_type_json);
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, cursor_json);
    try list.append(allocator, ',');
    try writeOptionalU64Json(&list, allocator, limit);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsGetBalance(allocator: std.mem.Allocator, owner: []const u8, coin_type: ?[]const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, owner.len + 16);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, owner);
    try list.append(allocator, ',');
    if (coin_type) |value| {
        try writeJsonString(&list, allocator, value);
    } else {
        try list.appendSlice(allocator, "null");
    }
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn paramsDynamicFields(
    allocator: std.mem.Allocator,
    parent_object_id: []const u8,
    cursor_json: ?[]const u8,
    limit: ?u64,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, parent_object_id.len + 24);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    try writeJsonString(&list, allocator, parent_object_id);
    try list.append(allocator, ',');
    try writeOptionalRaw(&list, allocator, cursor_json);
    try list.append(allocator, ',');
    try writeOptionalU64Json(&list, allocator, limit);
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn jsonArrayOfStrings(allocator: std.mem.Allocator, values: []const []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 16);
    errdefer list.deinit(allocator);
    try list.append(allocator, '[');
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        if (i != 0) try list.append(allocator, ',');
        try writeJsonString(&list, allocator, values[i]);
    }
    try list.append(allocator, ']');
    return list.toOwnedSlice(allocator);
}

pub fn parseResultAs(comptime T: type, allocator: std.mem.Allocator, response: []const u8) !json.Parsed(T) {
    var parsed = try json.parseFromSlice(json.Value, allocator, response, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return RpcError.InvalidJsonRpcResponse;
    if (root.object.get("error")) |_| {
        return RpcError.InvalidJsonRpcResponse;
    }
    const result = root.object.get("result") orelse return RpcError.InvalidJsonRpcResponse;
    return json.parseFromValue(T, allocator, result, .{});
}

pub fn parsePagedResultAs(comptime T: type, allocator: std.mem.Allocator, response: []const u8) !json.Parsed(PagedResult(T)) {
    return parseResultAs(PagedResult(T), allocator, response);
}

pub fn PagedResult(comptime T: type) type {
    return struct {
        data: []T,
        nextCursor: ?[]const u8,
        hasNextPage: bool,
    };
}

pub fn extractResultJson(allocator: std.mem.Allocator, response: []const u8) ![]u8 {
    var parsed = try json.parseFromSlice(json.Value, allocator, response, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return RpcError.InvalidJsonRpcResponse;
    if (root.object.get("error")) |_| {
        return RpcError.InvalidJsonRpcResponse;
    }
    const result = root.object.get("result") orelse return RpcError.InvalidJsonRpcResponse;

    var out: Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var stringify: json.Stringify = .{ .writer = &out.writer, .options = .{} };
    try stringify.write(result);
    return out.toOwnedSlice();
}

fn sendHttp(ctx: *anyopaque, allocator: std.mem.Allocator, request: []const u8) anyerror![]u8 {
    const self: *HttpTransport = @ptrCast(@alignCast(ctx));
    const uri = try std.Uri.parse(self.endpoint);

    var req = try self.client.request(.POST, uri, .{
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .extra_headers = &.{
            .{ .name = "accept", .value = "application/json" },
        },
        .redirect_behavior = .unhandled,
    });
    defer req.deinit();

    try req.sendBodyComplete(request);
    var redirect_buf: [256]u8 = undefined;
    const response = try req.receiveHead(&redirect_buf);
    if (response.head.status.class() != .success) return RpcError.InvalidJsonRpcResponse;

    var transfer_buf: [4096]u8 = undefined;
    var reader = response.reader(&transfer_buf);

    var body = std.ArrayList(u8).initCapacity(allocator, 256) catch return error.OutOfMemory;
    defer body.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = try reader.read(&chunk);
        if (n == 0) break;
        try body.appendSlice(allocator, chunk[0..n]);
    }

    return try body.toOwnedSlice(allocator);
}

fn writeOptionalRaw(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?[]const u8) !void {
    if (value) |raw| {
        try list.appendSlice(allocator, raw);
    } else {
        try list.appendSlice(allocator, "null");
    }
}

fn writeOptionalU64Json(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u64) !void {
    if (value) |v| {
        try writeUnsigned(list, allocator, v);
    } else {
        try list.appendSlice(allocator, "null");
    }
}

fn writeOptionalBoolJson(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?bool) !void {
    if (value) |v| {
        try list.appendSlice(allocator, if (v) "true" else "false");
    } else {
        try list.appendSlice(allocator, "null");
    }
}
