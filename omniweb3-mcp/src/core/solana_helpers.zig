const std = @import("std");
const solana_sdk = @import("solana_sdk");

const PublicKey = solana_sdk.PublicKey;
const Signature = solana_sdk.Signature;

pub fn resolveEndpoint(network: []const u8) []const u8 {
    if (std.mem.eql(u8, network, "mainnet")) return "https://api.mainnet-beta.solana.com";
    if (std.mem.eql(u8, network, "testnet")) return "https://api.testnet.solana.com";
    if (std.mem.eql(u8, network, "localhost")) return "http://localhost:8899";
    return "https://api.devnet.solana.com";
}

pub fn parsePublicKey(address: []const u8) !PublicKey {
    return PublicKey.fromBase58(address);
}

pub fn parseSignature(signature: []const u8) !Signature {
    return Signature.fromBase58(signature);
}

pub fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .emit_null_optional_fields = false },
    };

    try stringify.write(value);
    return out.written();
}
