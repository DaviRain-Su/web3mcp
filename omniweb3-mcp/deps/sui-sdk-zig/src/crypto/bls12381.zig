const std = @import("std");
const bcs = @import("../types/bcs.zig");
const build_options = @import("build_options");

const ffi = struct {
    extern fn sui_bls_verify(
        public_key_ptr: [*]const u8,
        public_key_len: usize,
        signature_ptr: [*]const u8,
        signature_len: usize,
        message_ptr: [*]const u8,
        message_len: usize,
    ) std.c.int;
    extern fn sui_zklogin_last_error_message(buf: ?[*]u8, buf_len: usize) usize;
    extern fn sui_zklogin_clear_error() void;
};

pub const Bls12381PublicKey = struct {
    pub const LENGTH: usize = 96;
    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Bls12381PublicKey {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Bls12381PublicKey) [LENGTH]u8 {
        return self.bytes;
    }

    pub fn encodeBcs(self: Bls12381PublicKey, writer: *bcs.Writer) !void {
        try writer.writeBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Bls12381PublicKey {
        const bytes = try reader.readBytes();
        if (bytes.len != LENGTH) return error.InvalidSignature;
        var out: [LENGTH]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

pub const Bls12381Signature = struct {
    pub const LENGTH: usize = 48;
    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Bls12381Signature {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Bls12381Signature) [LENGTH]u8 {
        return self.bytes;
    }

    pub fn encodeBcs(self: Bls12381Signature, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Bls12381Signature {
        const bytes = try reader.readFixedBytes(LENGTH);
        var out: [LENGTH]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

pub fn verify(signature: Bls12381Signature, message: []const u8, public_key: Bls12381PublicKey) !void {
    ffi.sui_zklogin_clear_error();
    const result = ffi.sui_bls_verify(
        public_key.bytes[0..].ptr,
        Bls12381PublicKey.LENGTH,
        signature.bytes[0..].ptr,
        Bls12381Signature.LENGTH,
        message.ptr,
        message.len,
    );
    if (result != 0) {
        return error.InvalidSignature;
    }
}

pub fn lastErrorMessage(allocator: std.mem.Allocator) !?[]u8 {
    const needed = ffi.sui_zklogin_last_error_message(null, 0);
    if (needed == 0) return null;
    const buf = try allocator.alloc(u8, needed);
    errdefer allocator.free(buf);
    _ = ffi.sui_zklogin_last_error_message(buf.ptr, buf.len);
    return buf;
}

const BlsFixture = struct {
    message: []u8,
    public_key: Bls12381PublicKey,
    signature: Bls12381Signature,

    pub fn deinit(self: *BlsFixture, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        self.* = undefined;
    }
};

fn loadFixture(allocator: std.mem.Allocator, path: []const u8) !BlsFixture {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_hex: []const u8,
        public_key_hex: []const u8,
        signature_hex: []const u8,
    };

    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeHexAlloc(allocator, parsed.value.message_hex);
    const public_key = Bls12381PublicKey.init(try decodeHexFixed(Bls12381PublicKey.LENGTH, parsed.value.public_key_hex));
    const signature = Bls12381Signature.init(try decodeHexFixed(Bls12381Signature.LENGTH, parsed.value.signature_hex));

    return .{ .message = message, .public_key = public_key, .signature = signature };
}

fn decodeHexAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len % 2 != 0) return error.InvalidHex;
    const out = try allocator.alloc(u8, input.len / 2);
    errdefer allocator.free(out);
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = try hexNibble(input[i * 2]);
        const lo = try hexNibble(input[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn decodeHexFixed(comptime n: usize, input: []const u8) ![n]u8 {
    if (input.len != n * 2) return error.InvalidHex;
    var out: [n]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const hi = try hexNibble(input[i * 2]);
        const lo = try hexNibble(input[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn hexNibble(byte: u8) !u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => error.InvalidHex,
    };
}

test "bls verify fixture" {
    if (!build_options.zklogin_ffi) return;
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/bls_fixture.json";
    var fixture = loadFixture(allocator, fixture_path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer fixture.deinit(allocator);

    try verify(fixture.signature, fixture.message, fixture.public_key);
}
