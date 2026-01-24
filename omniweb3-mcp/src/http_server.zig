const std = @import("std");
const mcp = @import("mcp");
const httpz = @import("httpz");

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

const App = struct {
    allocator: std.mem.Allocator,
    workers: []Worker,
    next_worker: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator, setup: ServerSetup, workers_count: usize) !App {
        const workers = try allocator.alloc(Worker, workers_count);
        for (workers, 0..) |*worker, i| {
            worker.* = try Worker.init(allocator, setup, i);
        }
        return .{
            .allocator = allocator,
            .workers = workers,
            .next_worker = std.atomic.Value(usize).init(0),
        };
    }

    pub fn deinit(self: *App) void {
        for (self.workers) |*worker| worker.deinit();
        self.allocator.free(self.workers);
    }

    fn submit(self: *App, body: []u8) ![]u8 {
        const idx = self.next_worker.fetchAdd(1, .monotonic) % self.workers.len;
        return self.workers[idx].transport.submit(body);
    }

    pub fn handle(self: *App, req: *httpz.Request, res: *httpz.Response) void {
        const path = req.url.path;
        const method = req.method;

        if (method == .GET and std.mem.eql(u8, path, "/health")) {
            res.setStatus(.ok);
            res.body = "ok";
            return;
        }

        if (method == .GET and (std.mem.eql(u8, path, "/") or std.mem.startsWith(u8, path, "/.well-known/oauth"))) {
            res.setStatus(.not_found);
            res.body = "Not Found";
            return;
        }

        if (method != .POST or !std.mem.eql(u8, path, "/")) {
            res.setStatus(.method_not_allowed);
            res.body = "Method Not Allowed";
            return;
        }

        const body = req.body() orelse {
            res.setStatus(.bad_request);
            res.body = "Missing Body";
            return;
        };

        const request_body = self.allocator.dupe(u8, body) catch {
            res.setStatus(.internal_server_error);
            res.body = "Internal Server Error";
            return;
        };
        defer self.allocator.free(request_body);

        const response_body = self.submit(request_body) catch |err| {
            if (err == error.RequestTimeout) {
                res.setStatus(.gateway_timeout);
                res.body = "Gateway Timeout";
            } else {
                res.setStatus(.internal_server_error);
                res.body = "Internal Server Error";
            }
            return;
        };
        defer self.allocator.free(response_body);

        const out = res.arena.dupe(u8, response_body) catch {
            res.setStatus(.internal_server_error);
            res.body = "Internal Server Error";
            return;
        };

        res.header("content-type", "application/json");
        res.setStatus(.ok);
        res.body = out;
    }
};

pub fn runHttpServer(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: RunOptions,
) !void {
    _ = io;
    var app = try App.init(allocator, options.setup, options.workers);
    defer app.deinit();

    var server = try httpz.Server(*App).init(allocator, .{
        .port = options.port,
        .address = options.host,
        .workers = .{ .count = @intCast(options.workers) },
        .request = .{ .max_body_size = 16 * 1024 * 1024 },
    }, &app);
    defer {
        server.stop();
        server.deinit();
    }

    std.log.info("HTTP MCP listening on http://{s}:{d}", .{ options.host, options.port });
    try server.listen();
}

fn serverLoop(server: *mcp.Server, transport: mcp.Transport, index: usize) !void {
    std.log.info("worker {d} ready", .{index});
    try server.runWithTransport(transport);
}
