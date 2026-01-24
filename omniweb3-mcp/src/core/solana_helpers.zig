const std = @import("std");
const solana_sdk = @import("solana_sdk");
const endpoints = @import("endpoints.zig");

const PublicKey = solana_sdk.PublicKey;
const Signature = solana_sdk.Signature;

/// Resolve Solana RPC endpoint by network name.
/// Delegates to centralized endpoint configuration.
pub fn resolveEndpoint(network: []const u8) []const u8 {
    return endpoints.solana.resolve(network);
}

pub fn parsePublicKey(address: []const u8) !PublicKey {
    return PublicKey.fromBase58(address);
}

pub fn parseSignature(signature: []const u8) !Signature {
    return Signature.fromBase58(signature);
}

pub fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .emit_null_optional_fields = false },
    };

    try stringify.write(value);
    return out.toOwnedSlice();
}

pub fn base64EncodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const out_len = encoder.calcSize(input.len);
    const buffer = try allocator.alloc(u8, out_len);
    const written = encoder.encode(buffer, input);
    return buffer[0..written.len];
}
