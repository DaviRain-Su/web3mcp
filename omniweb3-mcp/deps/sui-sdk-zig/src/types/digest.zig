const std = @import("std");
const bcs = @import("bcs.zig");

pub const DigestParseError = error{
    InvalidLength,
    InvalidHex,
};

pub const Digest = struct {
    bytes: [32]u8,

    pub fn fromBytes(bytes: [32]u8) Digest {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Digest) [32]u8 {
        return self.bytes;
    }

    pub fn parseHex(input: []const u8) DigestParseError!Digest {
        var hex = input;
        if (std.mem.startsWith(u8, hex, "0x") or std.mem.startsWith(u8, hex, "0X")) {
            hex = hex[2..];
        }
        if (hex.len != 64) return DigestParseError.InvalidLength;

        var out: [32]u8 = undefined;
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const hi = try parseHexNibble(hex[i * 2]);
            const lo = try parseHexNibble(hex[i * 2 + 1]);
            out[i] = (hi << 4) | lo;
        }
        return .{ .bytes = out };
    }

    pub fn toHexLower(self: Digest, buffer: []u8) ![]const u8 {
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

    pub fn encodeBcs(self: Digest, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Digest {
        const bytes = try reader.readFixedBytes(32);
        var out: [32]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

fn parseHexNibble(c: u8) DigestParseError!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => DigestParseError.InvalidHex,
    };
}

fn toHexLowerNibble(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}
