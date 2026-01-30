const std = @import("std");
const bcs = @import("../types/bcs.zig");

pub const Ed25519PublicKey = struct {
    pub const LENGTH: usize = 32;
    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Ed25519PublicKey {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Ed25519PublicKey) [LENGTH]u8 {
        return self.bytes;
    }

    pub fn encodeBcs(self: Ed25519PublicKey, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Ed25519PublicKey {
        const bytes = try reader.readFixedBytes(LENGTH);
        var out: [LENGTH]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

pub const Ed25519Signature = struct {
    pub const LENGTH: usize = 64;
    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Ed25519Signature {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Ed25519Signature) [LENGTH]u8 {
        return self.bytes;
    }

    pub fn encodeBcs(self: Ed25519Signature, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Ed25519Signature {
        const bytes = try reader.readFixedBytes(LENGTH);
        var out: [LENGTH]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

pub fn verify(signature: Ed25519Signature, message: []const u8, public_key: Ed25519PublicKey) !void {
    const Ed25519 = std.crypto.sign.Ed25519;
    const sig = Ed25519.Signature.fromBytes(signature.bytes);
    const pk = try Ed25519.PublicKey.fromBytes(public_key.bytes);
    try sig.verify(message, pk);
}

pub fn signDeterministic(seed: [32]u8, message: []const u8) !Ed25519Signature {
    const Ed25519 = std.crypto.sign.Ed25519;
    const key_pair = try Ed25519.KeyPair.generateDeterministic(seed);
    const sig = try Ed25519.KeyPair.sign(key_pair, message, null);
    return Ed25519Signature.init(sig.toBytes());
}

pub fn derivePublicKey(seed: [32]u8) !Ed25519PublicKey {
    const Ed25519 = std.crypto.sign.Ed25519;
    const key_pair = try Ed25519.KeyPair.generateDeterministic(seed);
    return Ed25519PublicKey.init(key_pair.public_key.toBytes());
}
