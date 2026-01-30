const std = @import("std");
const Io = std.Io;

const sui_sdk_zig = @import("sui_sdk_zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    if (args.len > 1 and std.mem.eql(u8, args[1], "version")) {
        try stdout_writer.print("sui-sdk-zig {s}\n", .{sui_sdk_zig.version});
    } else {
        try stdout_writer.print("sui-sdk-zig: core scaffolding initialized\n", .{});
    }

    try stdout_writer.flush();
}
