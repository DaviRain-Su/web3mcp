const std = @import("std");
const bcs = @import("bcs.zig");

pub const AddressParseError = error{
    InvalidLength,
    InvalidHex,
};

pub const Address = struct {
    pub const LENGTH: usize = 32;
    pub const ZERO: Address = .{ .bytes = [_]u8{0} ** 32 };
    pub const TWO: Address = fromU8(2);
    pub const THREE: Address = fromU8(3);

    bytes: [32]u8,

    pub fn fromBytes(bytes: [32]u8) Address {
        return .{ .bytes = bytes };
    }

    pub fn fromSlice(bytes: []const u8) AddressParseError!Address {
        if (bytes.len != LENGTH) return AddressParseError.InvalidLength;
        var out: [32]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }

    pub fn asBytes(self: Address) [32]u8 {
        return self.bytes;
    }

    pub fn parseHex(input: []const u8) AddressParseError!Address {
        var hex = input;
        if (std.mem.startsWith(u8, hex, "0x") or std.mem.startsWith(u8, hex, "0X")) {
            hex = hex[2..];
        }
        if (hex.len != 64) return AddressParseError.InvalidLength;

        var out: [32]u8 = undefined;
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const hi = try parseHexNibble(hex[i * 2]);
            const lo = try parseHexNibble(hex[i * 2 + 1]);
            out[i] = (hi << 4) | lo;
        }
        return .{ .bytes = out };
    }

    pub fn parseHexLenient(input: []const u8) AddressParseError!Address {
        var hex = input;
        if (std.mem.startsWith(u8, hex, "0x") or std.mem.startsWith(u8, hex, "0X")) {
            hex = hex[2..];
        }
        if (hex.len == 0 or hex.len > 64) return AddressParseError.InvalidLength;

        var out: [32]u8 = [_]u8{0} ** 32;
        var i: usize = hex.len;
        var out_index: usize = 32;
        while (i >= 2) : (i -= 2) {
            const hi = try parseHexNibble(hex[i - 2]);
            const lo = try parseHexNibble(hex[i - 1]);
            out_index -= 1;
            out[out_index] = (hi << 4) | lo;
            if (i == 2) break;
        }

        if (i == 1) {
            const lo = try parseHexNibble(hex[0]);
            out_index -= 1;
            out[out_index] = lo;
        }

        return .{ .bytes = out };
    }

    pub fn toHexLower(self: Address, buffer: []u8) ![]const u8 {
        if (buffer.len < 66) return error.NoSpaceLeft;
        buffer[0] = '0';
        buffer[1] = 'x';
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const b = self.bytes[i];
            buffer[2 + i * 2] = toHexLowerNibble(b >> 4);
            buffer[2 + i * 2 + 1] = toHexLowerNibble(b & 0x0f);
        }
        return buffer[0..66];
    }

    pub fn encodeBcs(self: Address, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Address {
        const bytes = try reader.readFixedBytes(32);
        var out: [32]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

fn fromU8(byte: u8) Address {
    var out = Address.ZERO;
    out.bytes[31] = byte;
    return out;
}

fn parseHexNibble(c: u8) AddressParseError!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => AddressParseError.InvalidHex,
    };
}

fn toHexLowerNibble(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}
