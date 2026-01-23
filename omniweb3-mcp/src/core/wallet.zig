const std = @import("std");

pub const WalletKind = enum { ed25519, secp256k1, unknown };

pub const Wallet = struct {
    kind: WalletKind,
    secret: []const u8,

    pub fn fromBytes(kind: WalletKind, secret: []const u8) Wallet {
        return .{ .kind = kind, .secret = secret };
    }
};
