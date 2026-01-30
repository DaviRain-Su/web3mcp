const std = @import("std");
const bcs = @import("../types/bcs.zig");

pub const Secp256k1PublicKey = struct {
    pub const LENGTH: usize = 33;
    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Secp256k1PublicKey {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Secp256k1PublicKey) [LENGTH]u8 {
        return self.bytes;
    }

    pub fn encodeBcs(self: Secp256k1PublicKey, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Secp256k1PublicKey {
        const bytes = try reader.readFixedBytes(LENGTH);
        var out: [LENGTH]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

pub const Secp256k1Signature = struct {
    pub const LENGTH: usize = 64;
    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Secp256k1Signature {
        return .{ .bytes = bytes };
    }

    pub fn asBytes(self: Secp256k1Signature) [LENGTH]u8 {
        return self.bytes;
    }

    pub fn encodeBcs(self: Secp256k1Signature, writer: *bcs.Writer) !void {
        try writer.writeFixedBytes(&self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Secp256k1Signature {
        const bytes = try reader.readFixedBytes(LENGTH);
        var out: [LENGTH]u8 = undefined;
        std.mem.copyForwards(u8, &out, bytes);
        return .{ .bytes = out };
    }
};

pub fn verify(signature: Secp256k1Signature, message: []const u8, public_key: Secp256k1PublicKey) !void {
    const Ecdsa = std.crypto.ecdsa.EcdsaSecp256k1Sha256;
    var sig_bytes: [Ecdsa.Signature.encoded_length]u8 = undefined;
    std.mem.copyForwards(u8, &sig_bytes, &signature.bytes);
    const sig = Ecdsa.Signature.fromBytes(sig_bytes);
    const pk = try Ecdsa.PublicKey.fromSec1(&public_key.bytes);
    try sig.verify(message, pk);
}

pub fn signDeterministic(private_key: [32]u8, message: []const u8) !Secp256k1Signature {
    const Ecdsa = std.crypto.ecdsa.EcdsaSecp256k1Sha256;
    const secret = try Ecdsa.SecretKey.fromBytes(private_key);
    const key_pair = try Ecdsa.KeyPair.fromSecretKey(secret);
    const sig = try Ecdsa.KeyPair.sign(key_pair, message, null);
    return Secp256k1Signature.init(sig.toBytes());
}

pub fn derivePublicKey(private_key: [32]u8) !Secp256k1PublicKey {
    const Ecdsa = std.crypto.ecdsa.EcdsaSecp256k1Sha256;
    const secret = try Ecdsa.SecretKey.fromBytes(private_key);
    const key_pair = try Ecdsa.KeyPair.fromSecretKey(secret);
    return Secp256k1PublicKey.init(key_pair.public_key.toCompressedSec1());
}
