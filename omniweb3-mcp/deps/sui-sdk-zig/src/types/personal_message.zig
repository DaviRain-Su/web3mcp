const std = @import("std");
const bcs = @import("bcs.zig");

pub const PersonalMessage = struct {
    bytes: []const u8,

    pub fn init(bytes: []const u8) PersonalMessage {
        return .{ .bytes = bytes };
    }

    pub fn encodeBcs(self: PersonalMessage, writer: *bcs.Writer) !void {
        try writer.writeBytes(self.bytes);
    }
};
