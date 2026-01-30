const std = @import("std");

pub const BcsError = error{
    UnexpectedEof,
    Overflow,
    InvalidOptionTag,
    Utf8Invalid,
};

pub const Writer = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !Writer {
        return .{ .allocator = allocator, .list = try std.ArrayList(u8).initCapacity(allocator, 0) };
    }

    pub fn deinit(self: *Writer) void {
        self.list.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *Writer) ![]u8 {
        return try self.list.toOwnedSlice(self.allocator);
    }

    pub fn writeFixedBytes(self: *Writer, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn writeBytes(self: *Writer, bytes: []const u8) !void {
        try self.writeUleb128(bytes.len);
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn writeString(self: *Writer, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return BcsError.Utf8Invalid;
        try self.writeBytes(value);
    }

    pub fn writeOption(self: *Writer, comptime T: type, value: ?T, writer_fn: *const fn (*Writer, T) anyerror!void) !void {
        if (value) |v| {
            try self.list.append(self.allocator, 1);
            try writer_fn(self, v);
        } else {
            try self.list.append(self.allocator, 0);
        }
    }

    pub fn writeVector(self: *Writer, comptime T: type, values: []const T, writer_fn: *const fn (*Writer, T) anyerror!void) !void {
        try self.writeUleb128(values.len);
        for (values) |value| {
            try writer_fn(self, value);
        }
    }

    pub fn writeUleb128(self: *Writer, value: usize) !void {
        var v: usize = value;
        while (true) {
            var byte: u8 = @intCast(v & 0x7f);
            v >>= 7;
            if (v != 0) byte |= 0x80;
            try self.list.append(self.allocator, byte);
            if (v == 0) break;
        }
    }

    pub fn writeU8(self: *Writer, value: u8) !void {
        try self.list.append(self.allocator, value);
    }

    pub fn writeU16(self: *Writer, value: u16) !void {
        var buffer: [2]u8 = undefined;
        std.mem.writeInt(u16, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeU32(self: *Writer, value: u32) !void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeU64(self: *Writer, value: u64) !void {
        var buffer: [8]u8 = undefined;
        std.mem.writeInt(u64, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeU128(self: *Writer, value: u128) !void {
        var buffer: [16]u8 = undefined;
        std.mem.writeInt(u128, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeI8(self: *Writer, value: i8) !void {
        try self.list.append(self.allocator, @bitCast(value));
    }

    pub fn writeI16(self: *Writer, value: i16) !void {
        var buffer: [2]u8 = undefined;
        std.mem.writeInt(i16, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeI32(self: *Writer, value: i32) !void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(i32, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeI64(self: *Writer, value: i64) !void {
        var buffer: [8]u8 = undefined;
        std.mem.writeInt(i64, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeI128(self: *Writer, value: i128) !void {
        var buffer: [16]u8 = undefined;
        std.mem.writeInt(i128, &buffer, value, .little);
        try self.list.appendSlice(self.allocator, &buffer);
    }

    pub fn writeBool(self: *Writer, value: bool) !void {
        try self.list.append(self.allocator, if (value) 1 else 0);
    }
};

pub const Reader = struct {
    data: []const u8,
    index: usize,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data, .index = 0 };
    }

    pub fn readFixedBytes(self: *Reader, len: usize) BcsError![]const u8 {
        if (self.index + len > self.data.len) return BcsError.UnexpectedEof;
        const slice = self.data[self.index .. self.index + len];
        self.index += len;
        return slice;
    }

    pub fn readBytes(self: *Reader) BcsError![]const u8 {
        const len = try self.readUleb128();
        return self.readFixedBytes(len);
    }

    pub fn readString(self: *Reader) BcsError![]const u8 {
        const bytes = try self.readBytes();
        if (!std.unicode.utf8ValidateSlice(bytes)) return BcsError.Utf8Invalid;
        return bytes;
    }

    pub fn readOption(self: *Reader, comptime T: type, reader_fn: *const fn (*Reader) anyerror!T) !?T {
        const tag = try self.readU8();
        switch (tag) {
            0 => return null,
            1 => return try reader_fn(self),
            else => return BcsError.InvalidOptionTag,
        }
    }

    pub fn readVectorAlloc(self: *Reader, allocator: std.mem.Allocator, comptime T: type, reader_fn: *const fn (*Reader) anyerror!T) ![]T {
        const len = try self.readUleb128();
        if (len > std.math.maxInt(usize)) return BcsError.Overflow;
        var list = try std.ArrayList(T).initCapacity(allocator, len);
        errdefer list.deinit(allocator);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            try list.append(allocator, try reader_fn(self));
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn readUleb128(self: *Reader) BcsError!usize {
        var result: usize = 0;
        var shift: u8 = 0;
        while (true) {
            const byte = try self.readU8();
            const payload: usize = @intCast(byte & 0x7f);
            if (shift >= (@sizeOf(usize) * 8)) return BcsError.Overflow;
            const shift_amount: std.math.Log2Int(usize) = @intCast(shift);
            result |= payload << shift_amount;
            if ((byte & 0x80) == 0) break;
            shift += 7;
        }
        return result;
    }

    pub fn readU8(self: *Reader) BcsError!u8 {
        const slice = try self.readFixedBytes(1);
        return slice[0];
    }

    pub fn readU16(self: *Reader) BcsError!u16 {
        const slice = try self.readFixedBytes(2);
        return std.mem.readInt(u16, slice[0..2], .little);
    }

    pub fn readU32(self: *Reader) BcsError!u32 {
        const slice = try self.readFixedBytes(4);
        return std.mem.readInt(u32, slice[0..4], .little);
    }

    pub fn readU64(self: *Reader) BcsError!u64 {
        const slice = try self.readFixedBytes(8);
        return std.mem.readInt(u64, slice[0..8], .little);
    }

    pub fn readU128(self: *Reader) BcsError!u128 {
        const slice = try self.readFixedBytes(16);
        return std.mem.readInt(u128, slice[0..16], .little);
    }

    pub fn readI8(self: *Reader) BcsError!i8 {
        const value = try self.readU8();
        return @bitCast(value);
    }

    pub fn readI16(self: *Reader) BcsError!i16 {
        const slice = try self.readFixedBytes(2);
        return std.mem.readInt(i16, slice[0..2], .little);
    }

    pub fn readI32(self: *Reader) BcsError!i32 {
        const slice = try self.readFixedBytes(4);
        return std.mem.readInt(i32, slice[0..4], .little);
    }

    pub fn readI64(self: *Reader) BcsError!i64 {
        const slice = try self.readFixedBytes(8);
        return std.mem.readInt(i64, slice[0..8], .little);
    }

    pub fn readI128(self: *Reader) BcsError!i128 {
        const slice = try self.readFixedBytes(16);
        return std.mem.readInt(i128, slice[0..16], .little);
    }

    pub fn readBool(self: *Reader) BcsError!bool {
        const value = try self.readU8();
        return switch (value) {
            0 => false,
            1 => true,
            else => return BcsError.InvalidOptionTag,
        };
    }
};
