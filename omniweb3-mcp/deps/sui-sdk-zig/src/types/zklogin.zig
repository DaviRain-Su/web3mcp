const std = @import("std");
const bcs = @import("bcs.zig");

pub const Jwk = struct {
    kty: []u8,
    e: []u8,
    n: []u8,
    alg: []u8,

    pub fn deinit(self: *Jwk, allocator: std.mem.Allocator) void {
        allocator.free(self.kty);
        allocator.free(self.e);
        allocator.free(self.n);
        allocator.free(self.alg);
        self.* = undefined;
    }

    pub fn encodeBcs(self: Jwk, writer: *bcs.Writer) !void {
        try writer.writeString(self.kty);
        try writer.writeString(self.e);
        try writer.writeString(self.n);
        try writer.writeString(self.alg);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Jwk {
        const kty = try reader.readString();
        const e = try reader.readString();
        const n = try reader.readString();
        const alg = try reader.readString();

        return .{
            .kty = try dup(allocator, kty),
            .e = try dup(allocator, e),
            .n = try dup(allocator, n),
            .alg = try dup(allocator, alg),
        };
    }
};

pub const JwkId = struct {
    iss: []u8,
    kid: []u8,

    pub fn deinit(self: *JwkId, allocator: std.mem.Allocator) void {
        allocator.free(self.iss);
        allocator.free(self.kid);
        self.* = undefined;
    }

    pub fn encodeBcs(self: JwkId, writer: *bcs.Writer) !void {
        try writer.writeString(self.iss);
        try writer.writeString(self.kid);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !JwkId {
        const iss = try reader.readString();
        const kid = try reader.readString();
        return .{ .iss = try dup(allocator, iss), .kid = try dup(allocator, kid) };
    }
};

fn dup(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, input.len);
    std.mem.copyForwards(u8, out, input);
    return out;
}
