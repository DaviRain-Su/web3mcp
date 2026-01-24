const std = @import("std");
const mcp = @import("mcp");

const Io = std.Io;
const net = std.Io.net;

pub const HttpBridgeTransport = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    incoming: ?[]u8 = null,
    outgoing: ?[]u8 = null,
    current_request: ?[]u8 = null,
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) *HttpBridgeTransport {
        const bridge = allocator.create(HttpBridgeTransport) catch @panic("out of memory");
        bridge.* = .{ .allocator = allocator };
        return bridge;
    }

    pub fn deinit(self: *HttpBridgeTransport) void {
        if (self.incoming) |msg| self.allocator.free(msg);
        if (self.outgoing) |msg| self.allocator.free(msg);
        if (self.current_request) |msg| self.allocator.free(msg);
        self.allocator.destroy(self);
    }

    pub fn transport(self: *HttpBridgeTransport) mcp.Transport {
        return .{
            .ptr = self,
            .vtable = &.{
                .send = sendVtable,
                .receive = receiveVtable,
                .close = closeVtable,
            },
        };
    }

    pub fn submit(self: *HttpBridgeTransport, message: []u8) ![]u8 {
        const timeout_ns = 60 * std.time.ns_per_s;
        var waited_ns: u64 = 0;

        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.incoming != null and !self.closed) {
            self.cond.timedWait(&self.mutex, std.time.ns_per_ms * 50) catch {
                waited_ns += std.time.ns_per_ms * 50;
                if (waited_ns >= timeout_ns) {
                    std.log.err("transport submit timeout waiting for incoming slot", .{});
                    return error.RequestTimeout;
                }
            };
        }
        if (self.closed) return error.ConnectionClosed;

        self.incoming = message;
        self.cond.signal();

        waited_ns = 0;
        while (self.outgoing == null and !self.closed) {
            self.cond.timedWait(&self.mutex, std.time.ns_per_ms * 50) catch {
                waited_ns += std.time.ns_per_ms * 50;
                if (waited_ns >= timeout_ns) {
                    std.log.err("transport submit timeout waiting for response", .{});
                    return error.RequestTimeout;
                }
            };
        }
        if (self.closed) return error.ConnectionClosed;

        const response = self.outgoing.?;
        self.outgoing = null;
        self.cond.signal();
        return response;
    }

    fn send(self: *HttpBridgeTransport, message: []const u8) mcp.Transport.SendError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.outgoing != null and !self.closed) {
            self.cond.wait(&self.mutex);
        }
        if (self.closed) return error.ConnectionClosed;

        const response = self.allocator.dupe(u8, message) catch return error.OutOfMemory;
        self.outgoing = response;

        self.cond.signal();
    }

    fn receive(self: *HttpBridgeTransport) mcp.Transport.ReceiveError!?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.incoming == null and !self.closed) {
            self.cond.wait(&self.mutex);
        }
        if (self.closed and self.incoming == null) return error.EndOfStream;

        const message = self.incoming.?;
        self.incoming = null;
        self.current_request = message;
        self.cond.signal();
        return message;
    }

    fn close(self: *HttpBridgeTransport) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
        self.cond.broadcast();
    }

    fn sendVtable(ptr: *anyopaque, message: []const u8) mcp.Transport.SendError!void {
        const self: *HttpBridgeTransport = @ptrCast(@alignCast(ptr));
        return self.send(message);
    }

    fn receiveVtable(ptr: *anyopaque) mcp.Transport.ReceiveError!?[]const u8 {
        const self: *HttpBridgeTransport = @ptrCast(@alignCast(ptr));
        return self.receive();
    }

    fn closeVtable(ptr: *anyopaque) void {
        const self: *HttpBridgeTransport = @ptrCast(@alignCast(ptr));
        self.close();
    }
};

pub const ServerSetup = struct {
    name: []const u8,
    version: []const u8,
    title: []const u8,
    description: []const u8,
    enable_logging: bool = true,
    register: *const fn (*mcp.Server) anyerror!void,
};

pub const RunOptions = struct {
    host: []const u8,
    port: u16,
    workers: usize = 4,
    setup: ServerSetup,
};

pub fn runHttpServer(
    allocator: std.mem.Allocator,
    io: Io,
    options: RunOptions,
) !void {
    var address = try net.IpAddress.resolve(io, options.host, options.port);
    var tcp_server = try address.listen(io, .{ .reuse_address = true });
    defer tcp_server.deinit(io);

    var workers = try allocator.alloc(Worker, options.workers);
    defer allocator.free(workers);

    for (workers, 0..) |*worker, i| {
        worker.* = try Worker.init(allocator, options.setup, i);
    }
    defer for (workers) |*worker| worker.deinit();

    var next_worker = std.atomic.Value(usize).init(0);

    std.log.info("HTTP MCP listening on http://{s}:{d}", .{ options.host, options.port });

    while (true) {
        var stream = tcp_server.accept(io) catch |err| {
            std.log.err("failed to accept connection: {s}", .{@errorName(err)});
            continue;
        };

        const idx = next_worker.fetchAdd(1, .monotonic) % workers.len;
        _ = std.Thread.spawn(.{}, connectionLoop, .{ allocator, io, &workers[idx], stream }) catch |err| {
            std.log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
            stream.close(io);
        };
    }
}

const Worker = struct {
    server: *mcp.Server,
    transport: *HttpBridgeTransport,
    thread: std.Thread,

    fn init(allocator: std.mem.Allocator, setup: ServerSetup, index: usize) !Worker {
        const server = allocator.create(mcp.Server) catch return error.OutOfMemory;
        server.* = mcp.Server.init(.{
            .name = setup.name,
            .version = setup.version,
            .title = setup.title,
            .description = setup.description,
            .allocator = allocator,
        });

        if (setup.enable_logging) server.enableLogging();
        try setup.register(server);

        const transport = HttpBridgeTransport.init(allocator);
        const transport_iface = transport.transport();
        const thread = try std.Thread.spawn(.{}, serverLoop, .{ server, transport_iface, index });

        return .{ .server = server, .transport = transport, .thread = thread };
    }

    fn deinit(self: *Worker) void {
        self.transport.close();
        self.thread.join();
        self.transport.deinit();
        self.server.deinit();
        self.server.allocator.destroy(self.server);
    }
};

fn serverLoop(server: *mcp.Server, transport: mcp.Transport, index: usize) !void {
    std.log.info("worker {d} ready", .{index});
    server.runWithTransport(transport) catch |err| {
        std.log.err("worker {d} exited: {s}", .{ index, @errorName(err) });
    };
}

fn handleConnection(
    allocator: std.mem.Allocator,
    io: Io,
    worker: *Worker,
    stream: net.Stream,
) !void {
    var read_buf: [16 * 1024]u8 = undefined;
    var write_buf: [16 * 1024]u8 = undefined;
    var reader = net.Stream.reader(stream, io, &read_buf);
    var writer = net.Stream.writer(stream, io, &write_buf);
    var http_server = std.http.Server.init(&reader.interface, &writer.interface);

    while (true) {
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return err,
        };

        const method_name = @tagName(request.head.method);
        const target_copy = try allocator.dupe(u8, request.head.target);
        defer allocator.free(target_copy);
        var timer = try std.time.Timer.start();

        if (request.head.method == .GET and std.mem.eql(u8, request.head.target, "/health")) {
            const status: std.http.Status = .ok;
            try request.respond("ok", .{ .status = status });
            logRequest(method_name, target_copy, status, timer.read());
            continue;
        }

        // Return 404 for OAuth discovery endpoints (tells clients OAuth is not required)
        if (request.head.method == .GET and (std.mem.startsWith(u8, request.head.target, "/.well-known/oauth") or
            std.mem.eql(u8, request.head.target, "/")))
        {
            const status: std.http.Status = .not_found;
            try request.respond("Not Found", .{ .status = status });
            logRequest(method_name, target_copy, status, timer.read());
            continue;
        }

        if (request.head.method != .POST) {
            const status: std.http.Status = .method_not_allowed;
            try request.respond("Method Not Allowed", .{ .status = status });
            logRequest(method_name, target_copy, status, timer.read());
            continue;
        }

        var body_reader_buf: [4096]u8 = undefined;
        var body_reader = request.readerExpectContinue(&body_reader_buf) catch {
            const status: std.http.Status = .expectation_failed;
            try request.respond("Expectation Failed", .{ .status = status });
            logRequest(method_name, target_copy, status, timer.read());
            continue;
        };

        const content_len_opt = request.head.content_length;
        const request_body = blk: {
            if (content_len_opt) |content_len| {
                var buf = try allocator.alloc(u8, content_len);
                var read_total: usize = 0;
                while (read_total < content_len) {
                    const n = body_reader.readSliceShort(buf[read_total..]) catch return error.ReadFailed;
                    if (n == 0) break;
                    read_total += n;
                }
                if (read_total != content_len) {
                    buf = try allocator.realloc(buf, read_total);
                }
                break :blk buf;
            }

            var allocating = std.Io.Writer.Allocating.init(allocator);
            defer allocating.deinit();

            _ = body_reader.streamRemaining(&allocating.writer) catch return error.ReadFailed;
            break :blk try allocating.toOwnedSlice();
        };

        defer allocator.free(request_body);

        const response_body = worker.transport.submit(request_body) catch |err| {
            const status: std.http.Status = if (err == error.RequestTimeout)
                .gateway_timeout
            else
                .internal_server_error;
            const body = if (status == .gateway_timeout) "Gateway Timeout" else "Internal Server Error";
            try request.respond(body, .{ .status = status });
            logRequest(method_name, target_copy, status, timer.read());
            continue;
        };
        defer allocator.free(response_body);

        const headers = [_]std.http.Header{.{
            .name = "content-type",
            .value = "application/json",
        }};
        const status: std.http.Status = .ok;
        try request.respond(response_body, .{ .status = status, .extra_headers = &headers });
        logRequest(method_name, target_copy, status, timer.read());
    }
}

fn logRequest(method: []const u8, target: []const u8, status: std.http.Status, elapsed_ns: u64) void {
    const elapsed_ms = elapsed_ns / std.time.ns_per_ms;
    std.log.info("{s} {s} -> {d} in {d}ms", .{ method, target, @intFromEnum(status), elapsed_ms });
}

fn connectionLoop(allocator: std.mem.Allocator, io: Io, worker: *Worker, stream: net.Stream) void {
    handleConnection(allocator, io, worker, stream) catch |err| {
        std.log.err("connection error: {s}", .{@errorName(err)});
    };
    stream.close(io);
}
