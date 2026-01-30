const std = @import("std");

pub const types = @import("types/mod.zig");
pub const crypto = @import("crypto/mod.zig");
pub const rpc = @import("rpc/mod.zig");
pub const transaction_builder = @import("transaction_builder/mod.zig");
pub const graphql = @import("graphql/mod.zig");

pub const version: []const u8 = "0.1.0-dev";

test "bcs uleb128 roundtrip" {
    var writer = try types.bcs.Writer.init(std.testing.allocator);
    defer writer.deinit();

    try writer.writeUleb128(624485);
    const bytes = try writer.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    var reader = types.bcs.Reader.init(bytes);
    const value = try reader.readUleb128();
    try std.testing.expectEqual(@as(u64, 624485), value);
}
