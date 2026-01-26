const std = @import("std");

// Simple standalone test to verify Phase 1 discriminator computation
// This can be run without dependencies

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Phase 1 Component Test ===\n\n", .{});

    // Test 1: Discriminator computation
    try testDiscriminator(allocator);

    // Test 2: Borsh serialization
    try testBorsh(allocator);

    std.debug.print("\n✓ All tests passed\n\n", .{});
}

fn testDiscriminator(allocator: std.mem.Allocator) !void {
    std.debug.print("Test 1: Anchor Discriminator Computation\n", .{});

    const test_cases = [_][]const u8{
        "initialize",
        "swap",
        "transfer",
        "mint",
        "burn",
    };

    for (test_cases) |func_name| {
        const disc = try computeDiscriminator(allocator, func_name);

        std.debug.print("  {s}: ", .{func_name});
        for (disc) |byte| {
            std.debug.print("{X:0>2}", .{byte});
        }
        std.debug.print("\n", .{});

        // Verify determinism
        const disc2 = try computeDiscriminator(allocator, func_name);
        if (!std.mem.eql(u8, &disc, &disc2)) {
            return error.DiscriminatorNotDeterministic;
        }
    }

    std.debug.print("  ✓ All discriminators are deterministic\n\n", .{});
}

fn computeDiscriminator(allocator: std.mem.Allocator, function_name: []const u8) ![8]u8 {
    const discriminator_str = try std.fmt.allocPrint(
        allocator,
        "global:{s}",
        .{function_name},
    );
    defer allocator.free(discriminator_str);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(discriminator_str, &hash, .{});

    var result: [8]u8 = undefined;
    @memcpy(&result, hash[0..8]);
    return result;
}

fn testBorsh(allocator: std.mem.Allocator) !void {
    std.debug.print("Test 2: Borsh Serialization\n", .{});

    // Test integer serialization
    {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        const value: u64 = 1000000;
        try serializeInt(&buffer, value);

        if (buffer.items.len != 8) {
            return error.InvalidSerializationLength;
        }

        const deserialized = std.mem.readInt(u64, buffer.items[0..8], .little);
        if (deserialized != value) {
            return error.DeserializationMismatch;
        }

        std.debug.print("  ✓ u64 serialization: {} bytes\n", .{buffer.items.len});
    }

    // Test string serialization
    {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        const value = "Hello, Borsh!";
        try serializeString(&buffer, value);

        // Should be 4 bytes (length) + string length
        const expected_len = 4 + value.len;
        if (buffer.items.len != expected_len) {
            return error.InvalidSerializationLength;
        }

        const len = std.mem.readInt(u32, buffer.items[0..4], .little);
        if (len != value.len) {
            return error.InvalidStringLength;
        }

        std.debug.print("  ✓ string serialization: {} bytes\n", .{buffer.items.len});
    }

    // Test boolean serialization
    {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try serializeBool(&buffer, true);
        if (buffer.items.len != 1 or buffer.items[0] != 1) {
            return error.InvalidBoolSerialization;
        }

        buffer.clearRetainingCapacity();
        try serializeBool(&buffer, false);
        if (buffer.items.len != 1 or buffer.items[0] != 0) {
            return error.InvalidBoolSerialization;
        }

        std.debug.print("  ✓ bool serialization: 1 byte\n", .{});
    }

    std.debug.print("  ✓ Borsh serialization working correctly\n\n", .{});
}

fn serializeInt(buffer: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T).Int;
    const bytes = @divExact(type_info.bits, 8);

    var int_bytes: [16]u8 = undefined;
    std.mem.writeInt(T, int_bytes[0..bytes], value, .little);
    try buffer.appendSlice(int_bytes[0..bytes]);
}

fn serializeString(buffer: *std.ArrayList(u8), value: []const u8) !void {
    try serializeInt(buffer, @as(u32, @intCast(value.len)));
    try buffer.appendSlice(value);
}

fn serializeBool(buffer: *std.ArrayList(u8), value: bool) !void {
    try buffer.append(if (value) 1 else 0);
}
