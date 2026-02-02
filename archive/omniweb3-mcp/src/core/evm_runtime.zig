const std = @import("std");

var runtime: ?Runtime = null;

pub const Runtime = struct {
    threaded_io: std.Io.Threaded,

    pub fn deinit(self: *Runtime) void {
        self.threaded_io.deinit();
    }
};

/// Initialize EVM runtime for zabi HTTP clients.
/// Must be called once at startup before using EVM tools.
pub fn init(allocator: std.mem.Allocator, environ: std.process.Environ) !void {
    if (runtime != null) return;

    const threaded_io = std.Io.Threaded.init(allocator, .{ .environ = environ });
    runtime = .{ .threaded_io = threaded_io };
}

/// Cleanup EVM runtime resources.
pub fn deinit() void {
    if (runtime) |*state| {
        state.deinit();
        runtime = null;
    }
}

/// Get the shared Io implementation for zabi clients.
pub fn io() std.Io {
    if (runtime) |*state| {
        return state.threaded_io.io();
    }
    @panic("EVM runtime not initialized");
}
