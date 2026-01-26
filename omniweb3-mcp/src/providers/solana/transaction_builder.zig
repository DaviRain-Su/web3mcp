const std = @import("std");
const chain_provider = @import("../../core/chain_provider.zig");
const borsh = @import("../../core/borsh.zig");

const ContractMeta = chain_provider.ContractMeta;
const Function = chain_provider.Function;
const FunctionCall = chain_provider.FunctionCall;
const Transaction = chain_provider.Transaction;
const ChainType = chain_provider.ChainType;

/// Build Solana transaction from function call
pub fn buildTransaction(
    allocator: std.mem.Allocator,
    meta: *const ContractMeta,
    call: FunctionCall,
) !Transaction {
    // 1. Find the function in metadata
    const func = try findFunction(meta, call.function);

    // 2. Compute instruction discriminator (SHA256 hash of "global:function_name")
    const discriminator = try computeDiscriminator(allocator, call.function);

    // 3. Serialize arguments using Borsh
    const args_data = try serializeArguments(allocator, func, call.args);
    defer allocator.free(args_data);

    // 4. Combine discriminator + args
    var instruction_data = try allocator.alloc(u8, 8 + args_data.len);
    @memcpy(instruction_data[0..8], discriminator[0..8]);
    @memcpy(instruction_data[8..], args_data);

    // 5. Build metadata (accounts would be resolved from args or derived)
    // For now, we'll create a simple metadata structure
    var metadata = std.json.ObjectMap.init(allocator);
    try metadata.put("program_id", std.json.Value{ .string = meta.address });
    try metadata.put("function", std.json.Value{ .string = call.function });

    // 6. Return transaction
    return Transaction{
        .chain = ChainType.solana,
        .from = call.signer,
        .to = meta.address,
        .data = instruction_data,
        .value = call.options.value,
        .metadata = std.json.Value{ .object = metadata },
    };
}

/// Find function by name in contract metadata
fn findFunction(meta: *const ContractMeta, function_name: []const u8) !*const Function {
    for (meta.functions) |*func| {
        if (std.mem.eql(u8, func.name, function_name)) {
            return func;
        }
    }
    return error.FunctionNotFound;
}

/// Compute Anchor instruction discriminator
/// Discriminator = first 8 bytes of SHA256("global:function_name")
pub fn computeDiscriminator(allocator: std.mem.Allocator, function_name: []const u8) ![8]u8 {
    // Build the string "global:function_name"
    const discriminator_str = try std.fmt.allocPrint(
        allocator,
        "global:{s}",
        .{function_name},
    );
    defer allocator.free(discriminator_str);

    // Compute SHA256 hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(discriminator_str, &hash, .{});

    // Return first 8 bytes
    var result: [8]u8 = undefined;
    @memcpy(&result, hash[0..8]);
    return result;
}

/// Serialize function arguments using Borsh
fn serializeArguments(
    allocator: std.mem.Allocator,
    func: *const Function,
    args: std.json.Value,
) ![]u8 {
    // For now, we'll implement a simple version that handles basic types
    // A full implementation would need to recursively serialize based on the function's parameter types

    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    // If args is an object, serialize each parameter in order
    if (args == .object) {
        for (func.inputs) |param| {
            if (args.object.get(param.name)) |arg_value| {
                try serializeParameter(allocator, &buffer, arg_value, param.type);
            } else {
                if (!param.optional) {
                    return error.MissingRequiredParameter;
                }
                // For optional parameters, serialize as None (0 byte)
                try buffer.append(allocator, 0);
            }
        }
    }

    return buffer.toOwnedSlice(allocator);
}

/// Serialize a single parameter based on its type
fn serializeParameter(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    value: std.json.Value,
    param_type: chain_provider.Type,
) !void {
    switch (param_type) {
        .primitive => |prim| {
            try serializePrimitive(allocator, buffer, value, prim);
        },
        .array => |inner_type| {
            // Serialize array length (u32)
            if (value != .array) return error.TypeMismatch;
            const len = value.array.items.len;
            try borsh.serializeInt(allocator, buffer, @as(u32, @intCast(len)));

            // Serialize each element
            for (value.array.items) |item| {
                try serializeParameter(allocator, buffer, item, inner_type.*);
            }
        },
        .option => |inner_type| {
            if (value == .null) {
                // None: serialize as 0
                try buffer.append(allocator, 0);
            } else {
                // Some: serialize as 1 + value
                try buffer.append(allocator, 1);
                try serializeParameter(allocator, buffer, value, inner_type.*);
            }
        },
        .struct_type => |fields| {
            // Serialize struct fields in order
            if (value != .object) return error.TypeMismatch;

            for (fields) |field| {
                if (value.object.get(field.name)) |field_value| {
                    try serializeParameter(allocator, buffer, field_value, field.type);
                } else {
                    return error.MissingStructField;
                }
            }
        },
        .custom => {
            // For custom types, we'd need to look up the TypeDef and serialize accordingly
            // For now, treat as a generic object
            return error.CustomTypeNotSupported;
        },
    }
}

/// Serialize primitive value
fn serializePrimitive(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    value: std.json.Value,
    prim: chain_provider.PrimitiveType,
) !void {
    switch (prim) {
        .u8 => {
            const val = try jsonToInt(u8, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .u16 => {
            const val = try jsonToInt(u16, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .u32 => {
            const val = try jsonToInt(u32, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .u64 => {
            const val = try jsonToInt(u64, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .u128 => {
            const val = try jsonToInt(u128, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .i8 => {
            const val = try jsonToInt(i8, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .i16 => {
            const val = try jsonToInt(i16, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .i32 => {
            const val = try jsonToInt(i32, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .i64 => {
            const val = try jsonToInt(i64, value);
            try borsh.serializeInt(allocator, buffer, val);
        },
        .bool => {
            const val = if (value == .bool) value.bool else return error.TypeMismatch;
            try borsh.serializeBool(allocator, buffer, val);
        },
        .string => {
            const val = if (value == .string) value.string else return error.TypeMismatch;
            try borsh.serializeString(allocator, buffer, val);
        },
        .pubkey, .address => {
            // Public keys and addresses are stored as strings in JSON
            // In Borsh, they're typically 32 bytes for Solana pubkeys
            const val = if (value == .string) value.string else return error.TypeMismatch;

            // For now, just serialize the string
            // A full implementation would decode base58 (pubkey) or hex (address)
            try borsh.serializeString(allocator, buffer, val);
        },
        .bytes => {
            // Bytes are typically base64 or hex encoded in JSON
            const val = if (value == .string) value.string else return error.TypeMismatch;
            try borsh.serializeString(allocator, buffer, val);
        },
        else => {
            return error.UnsupportedPrimitiveType;
        },
    }
}

/// Convert JSON value to integer type
fn jsonToInt(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        .string => |s| try std.fmt.parseInt(T, s, 10),
        else => error.TypeMismatch,
    };
}

// Tests
test "computeDiscriminator" {
    const allocator = std.testing.allocator;

    const disc = try computeDiscriminator(allocator, "initialize");

    // Discriminator should be 8 bytes
    try std.testing.expectEqual(@as(usize, 8), disc.len);

    // Should be deterministic (same input = same output)
    const disc2 = try computeDiscriminator(allocator, "initialize");
    try std.testing.expectEqualSlices(u8, &disc, &disc2);

    // Different input should give different output
    const disc3 = try computeDiscriminator(allocator, "swap");
    try std.testing.expect(!std.mem.eql(u8, &disc, &disc3));
}

test "serializePrimitive u64" {
    const allocator = std.testing.allocator;
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    const value = std.json.Value{ .integer = 1000 };
    try serializePrimitive(allocator, &buffer, value, .u64);

    // Should be 8 bytes (little-endian)
    try std.testing.expectEqual(@as(usize, 8), buffer.items.len);

    // Verify the value
    const deserialized = std.mem.readInt(u64, buffer.items[0..8], .little);
    try std.testing.expectEqual(@as(u64, 1000), deserialized);
}

test "serializePrimitive string" {
    const allocator = std.testing.allocator;
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    const value = std.json.Value{ .string = "hello" };
    try serializePrimitive(allocator, &buffer, value, .string);

    // Should be 4 bytes (length) + 5 bytes (string)
    try std.testing.expectEqual(@as(usize, 9), buffer.items.len);

    // Verify length prefix
    const len = std.mem.readInt(u32, buffer.items[0..4], .little);
    try std.testing.expectEqual(@as(u32, 5), len);

    // Verify string content
    try std.testing.expectEqualStrings("hello", buffer.items[4..9]);
}
