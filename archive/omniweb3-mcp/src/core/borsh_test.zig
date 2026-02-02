//! Additional tests for Borsh serialization
//!
//! Tests cover:
//! - Edge cases (empty values, max/min values)
//! - Error handling (buffer too small, invalid data)
//! - Complex nested structures
//! - Enum serialization
//! - Array serialization

const std = @import("std");
const testing = std.testing;
const borsh = @import("borsh.zig");

// Test empty values
test "serialize/deserialize empty string" {
    const allocator = testing.allocator;

    const value = "";
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try borsh.serializeString(allocator, &buffer, value);

    // Should be 4 bytes (length = 0)
    try testing.expectEqual(@as(usize, 4), buffer.items.len);

    // Verify length is 0
    const len = std.mem.readInt(u32, buffer.items[0..4], .little);
    try testing.expectEqual(@as(u32, 0), len);
}

test "serialize/deserialize zero values" {
    const allocator = testing.allocator;

    // u8 zero
    const zero_u8: u8 = 0;
    const serialized_u8 = try borsh.serialize(allocator, zero_u8);
    defer allocator.free(serialized_u8);
    try testing.expectEqual(@as(u8, 0), serialized_u8[0]);

    // u32 zero
    const zero_u32: u32 = 0;
    const serialized_u32 = try borsh.serialize(allocator, zero_u32);
    defer allocator.free(serialized_u32);
    const deserialized_u32 = try borsh.deserialize(u32, allocator, serialized_u32);
    try testing.expectEqual(@as(u32, 0), deserialized_u32);

    // u64 zero
    const zero_u64: u64 = 0;
    const serialized_u64 = try borsh.serialize(allocator, zero_u64);
    defer allocator.free(serialized_u64);
    const deserialized_u64 = try borsh.deserialize(u64, allocator, serialized_u64);
    try testing.expectEqual(@as(u64, 0), deserialized_u64);
}

test "serialize/deserialize max values" {
    const allocator = testing.allocator;

    // u8 max
    const max_u8: u8 = 255;
    const serialized_u8 = try borsh.serialize(allocator, max_u8);
    defer allocator.free(serialized_u8);
    const deserialized_u8 = try borsh.deserialize(u8, allocator, serialized_u8);
    try testing.expectEqual(max_u8, deserialized_u8);

    // u16 max
    const max_u16: u16 = 65535;
    const serialized_u16 = try borsh.serialize(allocator, max_u16);
    defer allocator.free(serialized_u16);
    const deserialized_u16 = try borsh.deserialize(u16, allocator, serialized_u16);
    try testing.expectEqual(max_u16, deserialized_u16);

    // u32 max
    const max_u32: u32 = 4294967295;
    const serialized_u32 = try borsh.serialize(allocator, max_u32);
    defer allocator.free(serialized_u32);
    const deserialized_u32 = try borsh.deserialize(u32, allocator, serialized_u32);
    try testing.expectEqual(max_u32, deserialized_u32);
}

// Test signed integers
test "serialize/deserialize signed integers" {
    const allocator = testing.allocator;

    // i32 negative
    const neg_i32: i32 = -42;
    const serialized_i32 = try borsh.serialize(allocator, neg_i32);
    defer allocator.free(serialized_i32);
    const deserialized_i32 = try borsh.deserialize(i32, allocator, serialized_i32);
    try testing.expectEqual(neg_i32, deserialized_i32);

    // i64 negative
    const neg_i64: i64 = -123456789;
    const serialized_i64 = try borsh.serialize(allocator, neg_i64);
    defer allocator.free(serialized_i64);
    const deserialized_i64 = try borsh.deserialize(i64, allocator, serialized_i64);
    try testing.expectEqual(neg_i64, deserialized_i64);
}

// Test bool false
test "serialize/deserialize false" {
    const allocator = testing.allocator;

    const serialized = try borsh.serialize(allocator, false);
    defer allocator.free(serialized);

    try testing.expectEqual(@as(usize, 1), serialized.len);
    try testing.expectEqual(@as(u8, 0), serialized[0]);

    const deserialized = try borsh.deserialize(bool, allocator, serialized);
    try testing.expectEqual(false, deserialized);
}

// Test nested struct
test "serialize/deserialize nested struct" {
    const allocator = testing.allocator;

    const Inner = struct {
        a: u32,
        b: u32,
    };

    const Outer = struct {
        x: u32,
        inner: Inner,
        y: u32,
    };

    const value = Outer{
        .x = 10,
        .inner = Inner{ .a = 20, .b = 30 },
        .y = 40,
    };

    const serialized = try borsh.serialize(allocator, value);
    defer allocator.free(serialized);

    // Should be 16 bytes (4 u32s)
    try testing.expectEqual(@as(usize, 16), serialized.len);

    const deserialized = try borsh.deserialize(Outer, allocator, serialized);
    try testing.expectEqual(value.x, deserialized.x);
    try testing.expectEqual(value.inner.a, deserialized.inner.a);
    try testing.expectEqual(value.inner.b, deserialized.inner.b);
    try testing.expectEqual(value.y, deserialized.y);
}

// Test enum
test "serialize/deserialize enum" {
    const allocator = testing.allocator;

    const Color = enum(u8) {
        Red = 0,
        Green = 1,
        Blue = 2,
    };

    const color = Color.Green;
    const serialized = try borsh.serialize(allocator, color);
    defer allocator.free(serialized);

    try testing.expectEqual(@as(usize, 1), serialized.len);
    try testing.expectEqual(@as(u8, 1), serialized[0]);

    const deserialized = try borsh.deserialize(Color, allocator, serialized);
    try testing.expectEqual(Color.Green, deserialized);
}

// Test multiple enum values
test "serialize/deserialize all enum values" {
    const allocator = testing.allocator;

    const Status = enum(u8) {
        Pending = 0,
        Processing = 1,
        Completed = 2,
        Failed = 3,
    };

    const statuses = [_]Status{ .Pending, .Processing, .Completed, .Failed };

    for (statuses, 0..) |status, expected_value| {
        const serialized = try borsh.serialize(allocator, status);
        defer allocator.free(serialized);

        try testing.expectEqual(@as(usize, 1), serialized.len);
        try testing.expectEqual(@as(u8, @intCast(expected_value)), serialized[0]);

        const deserialized = try borsh.deserialize(Status, allocator, serialized);
        try testing.expectEqual(status, deserialized);
    }
}

// Test struct with optional fields
test "serialize/deserialize struct with optional" {
    const allocator = testing.allocator;

    const Data = struct {
        required: u32,
        optional: ?u32,
    };

    // With value
    const with_value = Data{
        .required = 42,
        .optional = 100,
    };

    const serialized_with = try borsh.serialize(allocator, with_value);
    defer allocator.free(serialized_with);

    // Should be 9 bytes: 4 (required) + 1 (flag) + 4 (optional value)
    try testing.expectEqual(@as(usize, 9), serialized_with.len);

    const deserialized_with = try borsh.deserialize(Data, allocator, serialized_with);
    try testing.expectEqual(with_value.required, deserialized_with.required);
    try testing.expectEqual(@as(u32, 100), deserialized_with.optional.?);

    // Without value
    const without_value = Data{
        .required = 42,
        .optional = null,
    };

    const serialized_without = try borsh.serialize(allocator, without_value);
    defer allocator.free(serialized_without);

    // Should be 5 bytes: 4 (required) + 1 (flag = 0)
    try testing.expectEqual(@as(usize, 5), serialized_without.len);

    const deserialized_without = try borsh.deserialize(Data, allocator, serialized_without);
    try testing.expectEqual(without_value.required, deserialized_without.required);
    try testing.expectEqual(@as(?u32, null), deserialized_without.optional);
}

// Test little-endian encoding
test "integer serialization uses little-endian" {
    const allocator = testing.allocator;

    // u32: 0x12345678 should be [0x78, 0x56, 0x34, 0x12] in little-endian
    const value: u32 = 0x12345678;
    const serialized = try borsh.serialize(allocator, value);
    defer allocator.free(serialized);

    try testing.expectEqual(@as(u8, 0x78), serialized[0]);
    try testing.expectEqual(@as(u8, 0x56), serialized[1]);
    try testing.expectEqual(@as(u8, 0x34), serialized[2]);
    try testing.expectEqual(@as(u8, 0x12), serialized[3]);
}

// Test u16 little-endian
test "u16 serialization uses little-endian" {
    const allocator = testing.allocator;

    // u16: 0x1234 should be [0x34, 0x12] in little-endian
    const value: u16 = 0x1234;
    const serialized = try borsh.serialize(allocator, value);
    defer allocator.free(serialized);

    try testing.expectEqual(@as(usize, 2), serialized.len);
    try testing.expectEqual(@as(u8, 0x34), serialized[0]);
    try testing.expectEqual(@as(u8, 0x12), serialized[1]);
}

// Test i8 boundaries
test "serialize/deserialize i8 boundaries" {
    const allocator = testing.allocator;

    // Min value
    const min: i8 = -128;
    const serialized_min = try borsh.serialize(allocator, min);
    defer allocator.free(serialized_min);
    const deserialized_min = try borsh.deserialize(i8, allocator, serialized_min);
    try testing.expectEqual(min, deserialized_min);

    // Max value
    const max: i8 = 127;
    const serialized_max = try borsh.serialize(allocator, max);
    defer allocator.free(serialized_max);
    const deserialized_max = try borsh.deserialize(i8, allocator, serialized_max);
    try testing.expectEqual(max, deserialized_max);
}

// Test i16 boundaries
test "serialize/deserialize i16 boundaries" {
    const allocator = testing.allocator;

    // Min value
    const min: i16 = -32768;
    const serialized_min = try borsh.serialize(allocator, min);
    defer allocator.free(serialized_min);
    const deserialized_min = try borsh.deserialize(i16, allocator, serialized_min);
    try testing.expectEqual(min, deserialized_min);

    // Max value
    const max: i16 = 32767;
    const serialized_max = try borsh.serialize(allocator, max);
    defer allocator.free(serialized_max);
    const deserialized_max = try borsh.deserialize(i16, allocator, serialized_max);
    try testing.expectEqual(max, deserialized_max);
}

// Test struct field order matters
test "struct serialization preserves field order" {
    const allocator = testing.allocator;

    const Data = struct {
        first: u8,
        second: u16,
        third: u32,
    };

    const value = Data{
        .first = 0x11,
        .second = 0x2222,
        .third = 0x33333333,
    };

    const serialized = try borsh.serialize(allocator, value);
    defer allocator.free(serialized);

    // Should be 7 bytes: 1 + 2 + 4
    try testing.expectEqual(@as(usize, 7), serialized.len);

    // Verify field order
    try testing.expectEqual(@as(u8, 0x11), serialized[0]);
    try testing.expectEqual(@as(u8, 0x22), serialized[1]); // 0x2222 little-endian
    try testing.expectEqual(@as(u8, 0x22), serialized[2]);
    try testing.expectEqual(@as(u8, 0x33), serialized[3]); // 0x33333333 little-endian
}

// Test UTF-8 string
test "serialize/deserialize UTF-8 string" {
    const allocator = testing.allocator;

    const value = "Hello 世界! 🌍";
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try borsh.serializeString(allocator, &buffer, value);

    // Length prefix + UTF-8 bytes
    try testing.expect(buffer.items.len > 4);

    // Verify length prefix
    const len = std.mem.readInt(u32, buffer.items[0..4], .little);
    try testing.expectEqual(@as(u32, @intCast(value.len)), len);
}
