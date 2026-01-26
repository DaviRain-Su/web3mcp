const std = @import("std");

/// Borsh (Binary Object Representation Serializer for Hashing) implementation for Zig
/// Spec: https://borsh.io/
///
/// Borsh is a binary serialization format designed for security-critical applications.
/// Used by Solana, NEAR, and other blockchains.

pub const BorshError = error{
    OutOfMemory,
    BufferTooSmall,
    InvalidUtf8,
    Overflow,
};

/// Serialize a value to Borsh format
pub fn serialize(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    try serializeInto(allocator, &buffer, value);
    return buffer.toOwnedSlice(allocator);
}

/// Serialize a value into an existing ArrayList
pub fn serializeInto(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .bool => try serializeBool(allocator, buffer, value),
        .int => try serializeInt(allocator, buffer, value),
        .float => try serializeFloat(allocator, buffer, value),
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (ptr_info.child == u8) {
                        // Byte array
                        try serializeBytes(allocator, buffer, value);
                    } else {
                        // Array of other types
                        try serializeArray(allocator, buffer, value);
                    }
                },
                else => @compileError("Unsupported pointer type"),
            }
        },
        .array => |array_info| {
            if (array_info.child == u8) {
                try serializeBytes(allocator, buffer, &value);
            } else {
                try serializeArray(allocator, buffer, &value);
            }
        },
        .@"struct" => try serializeStruct(allocator, buffer, value),
        .optional => try serializeOptional(allocator, buffer, value),
        .@"enum" => try serializeEnum(allocator, buffer, value),
        else => @compileError("Unsupported type for Borsh serialization: " ++ @typeName(T)),
    }
}

/// Serialize boolean (1 byte: 0 or 1)
pub fn serializeBool(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: bool) !void {
    try buffer.append(allocator, if (value) 1 else 0);
}

/// Serialize integer (little-endian)
pub fn serializeInt(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T).int;
    const bytes = @divExact(type_info.bits, 8);

    var int_bytes: [16]u8 = undefined;
    std.mem.writeInt(T, int_bytes[0..bytes], value, .little);
    try buffer.appendSlice(allocator, int_bytes[0..bytes]);
}

/// Serialize float (little-endian)
fn serializeFloat(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const bytes = @sizeOf(T);

    var float_bytes: [8]u8 = undefined;
    @memcpy(float_bytes[0..bytes], std.mem.asBytes(&value));
    try buffer.appendSlice(allocator, float_bytes[0..bytes]);
}

/// Serialize string (length prefix + UTF-8 bytes)
pub fn serializeString(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: []const u8) !void {
    // Length prefix (u32 little-endian)
    try serializeInt(allocator, buffer, @as(u32, @intCast(value.len)));
    // String bytes
    try buffer.appendSlice(allocator, value);
}

/// Serialize bytes (length prefix + raw bytes)
fn serializeBytes(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: []const u8) !void {
    // Length prefix (u32 little-endian)
    try serializeInt(allocator, buffer, @as(u32, @intCast(value.len)));
    // Raw bytes
    try buffer.appendSlice(allocator, value);
}

/// Serialize array (length prefix + elements)
fn serializeArray(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    const len = value.len;
    // Length prefix (u32 little-endian)
    try serializeInt(allocator, buffer, @as(u32, @intCast(len)));

    // Serialize each element
    for (value) |item| {
        try serializeInto(allocator, buffer, item);
    }
}

/// Serialize struct (fields in declaration order)
fn serializeStruct(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const fields = @typeInfo(T).@"struct".fields;

    inline for (fields) |field| {
        const field_value = @field(value, field.name);
        try serializeInto(allocator, buffer, field_value);
    }
}

/// Serialize optional (0 for None, 1 + value for Some)
fn serializeOptional(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    if (value) |val| {
        try buffer.append(allocator, 1);
        try serializeInto(allocator, buffer, val);
    } else {
        try buffer.append(allocator, 0);
    }
}

/// Serialize enum (u8 discriminator)
fn serializeEnum(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype) !void {
    const int_value = @intFromEnum(value);
    try serializeInt(allocator, buffer, @as(u8, @intCast(int_value)));
}

/// Deserialize a value from Borsh format
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, data: []const u8) !T {
    var offset: usize = 0;
    return try deserializeFrom(T, allocator, data, &offset);
}

/// Deserialize from data with offset tracking
fn deserializeFrom(comptime T: type, allocator: std.mem.Allocator, data: []const u8, offset: *usize) !T {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .bool => return try deserializeBool(data, offset),
        .int => return try deserializeInt(T, data, offset),
        .float => return try deserializeFloat(T, data, offset),
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (ptr_info.child == u8) {
                        return try deserializeBytes(allocator, data, offset);
                    } else {
                        return try deserializeArray(ptr_info.child, allocator, data, offset);
                    }
                },
                else => @compileError("Unsupported pointer type"),
            }
        },
        .@"struct" => return try deserializeStruct(T, allocator, data, offset),
        .optional => return try deserializeOptional(T, allocator, data, offset),
        .@"enum" => return try deserializeEnum(T, data, offset),
        else => @compileError("Unsupported type for Borsh deserialization: " ++ @typeName(T)),
    }
}

fn deserializeBool(data: []const u8, offset: *usize) !bool {
    if (offset.* >= data.len) return error.BufferTooSmall;
    const value = data[offset.*];
    offset.* += 1;
    return value != 0;
}

fn deserializeInt(comptime T: type, data: []const u8, offset: *usize) !T {
    const bytes = @divExact(@typeInfo(T).int.bits, 8);
    if (offset.* + bytes > data.len) return error.BufferTooSmall;

    const value = std.mem.readInt(T, data[offset.*..][0..bytes], .little);
    offset.* += bytes;
    return value;
}

fn deserializeFloat(comptime T: type, data: []const u8, offset: *usize) !T {
    const bytes = @sizeOf(T);
    if (offset.* + bytes > data.len) return error.BufferTooSmall;

    var value: T = undefined;
    @memcpy(std.mem.asBytes(&value), data[offset.* .. offset.* + bytes]);
    offset.* += bytes;
    return value;
}

fn deserializeBytes(allocator: std.mem.Allocator, data: []const u8, offset: *usize) ![]u8 {
    // Read length prefix
    const len = try deserializeInt(u32, data, offset);

    if (offset.* + len > data.len) return error.BufferTooSmall;

    // Allocate and copy bytes
    const bytes = try allocator.alloc(u8, len);
    @memcpy(bytes, data[offset.* .. offset.* + len]);
    offset.* += len;

    return bytes;
}

fn deserializeArray(comptime Child: type, allocator: std.mem.Allocator, data: []const u8, offset: *usize) ![]Child {
    // Read length prefix
    const len = try deserializeInt(u32, data, offset);

    // Allocate array
    const array = try allocator.alloc(Child, len);
    errdefer allocator.free(array);

    // Deserialize each element
    for (array) |*item| {
        item.* = try deserializeFrom(Child, allocator, data, offset);
    }

    return array;
}

fn deserializeStruct(comptime T: type, allocator: std.mem.Allocator, data: []const u8, offset: *usize) !T {
    var result: T = undefined;
    const fields = @typeInfo(T).@"struct".fields;

    inline for (fields) |field| {
        @field(result, field.name) = try deserializeFrom(field.type, allocator, data, offset);
    }

    return result;
}

fn deserializeOptional(comptime T: type, allocator: std.mem.Allocator, data: []const u8, offset: *usize) !T {
    const has_value = try deserializeBool(data, offset);

    if (has_value) {
        const Child = @typeInfo(T).optional.child;
        return try deserializeFrom(Child, allocator, data, offset);
    } else {
        return null;
    }
}

fn deserializeEnum(comptime T: type, data: []const u8, offset: *usize) !T {
    const int_value = try deserializeInt(u8, data, offset);
    return @enumFromInt(int_value);
}

// Tests
test "serialize/deserialize bool" {
    const allocator = std.testing.allocator;

    const serialized = try serialize(allocator, true);
    defer allocator.free(serialized);

    try std.testing.expectEqual(@as(usize, 1), serialized.len);
    try std.testing.expectEqual(@as(u8, 1), serialized[0]);

    const deserialized = try deserialize(bool, allocator, serialized);
    try std.testing.expectEqual(true, deserialized);
}

test "serialize/deserialize integers" {
    const allocator = std.testing.allocator;

    // u32
    const value_u32: u32 = 0x12345678;
    const serialized_u32 = try serialize(allocator, value_u32);
    defer allocator.free(serialized_u32);

    try std.testing.expectEqual(@as(usize, 4), serialized_u32.len);
    const deserialized_u32 = try deserialize(u32, allocator, serialized_u32);
    try std.testing.expectEqual(value_u32, deserialized_u32);

    // u64
    const value_u64: u64 = 0x123456789ABCDEF0;
    const serialized_u64 = try serialize(allocator, value_u64);
    defer allocator.free(serialized_u64);

    try std.testing.expectEqual(@as(usize, 8), serialized_u64.len);
    const deserialized_u64 = try deserialize(u64, allocator, serialized_u64);
    try std.testing.expectEqual(value_u64, deserialized_u64);
}

test "serialize/deserialize string" {
    const allocator = std.testing.allocator;

    const value = "Hello, Borsh!";
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try serializeString(allocator, &buffer, value);

    // Should be 4 bytes (length) + 13 bytes (string)
    try std.testing.expectEqual(@as(usize, 17), buffer.items.len);

    // Deserialize
    var offset: usize = 0;
    const deserialized = try deserializeBytes(allocator, buffer.items, &offset);
    defer allocator.free(deserialized);

    try std.testing.expectEqualStrings(value, deserialized);
}

test "serialize/deserialize struct" {
    const allocator = std.testing.allocator;

    const Point = struct {
        x: u32,
        y: u32,
    };

    const point = Point{ .x = 10, .y = 20 };
    const serialized = try serialize(allocator, point);
    defer allocator.free(serialized);

    try std.testing.expectEqual(@as(usize, 8), serialized.len);

    const deserialized = try deserialize(Point, allocator, serialized);
    try std.testing.expectEqual(point.x, deserialized.x);
    try std.testing.expectEqual(point.y, deserialized.y);
}

test "serialize/deserialize optional" {
    const allocator = std.testing.allocator;

    // Some value
    const value_some: ?u32 = 42;
    const serialized_some = try serialize(allocator, value_some);
    defer allocator.free(serialized_some);

    try std.testing.expectEqual(@as(usize, 5), serialized_some.len); // 1 (flag) + 4 (u32)
    try std.testing.expectEqual(@as(u8, 1), serialized_some[0]);

    const deserialized_some = try deserialize(?u32, allocator, serialized_some);
    try std.testing.expectEqual(@as(u32, 42), deserialized_some.?);

    // None value
    const value_none: ?u32 = null;
    const serialized_none = try serialize(allocator, value_none);
    defer allocator.free(serialized_none);

    try std.testing.expectEqual(@as(usize, 1), serialized_none.len);
    try std.testing.expectEqual(@as(u8, 0), serialized_none[0]);

    const deserialized_none = try deserialize(?u32, allocator, serialized_none);
    try std.testing.expectEqual(@as(?u32, null), deserialized_none);
}
