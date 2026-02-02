//! MCP Server Implementation
//!
//! Provides the main MCP Server that handles client connections, protocol
//! negotiation, capability advertisement, and request routing for tools,
//! resources, and prompts.

const std = @import("std");
const protocol = @import("../protocol/protocol.zig");
const jsonrpc = @import("../protocol/jsonrpc.zig");
const types = @import("../protocol/types.zig");
const transport_mod = @import("../transport/transport.zig");
const tools_mod = @import("tools.zig");
const resources_mod = @import("resources.zig");
const prompts_mod = @import("prompts.zig");

/// Configuration for an MCP Server
pub const ServerConfig = struct {
    /// Server name
    name: []const u8,
    /// Server version
    version: []const u8,
    /// Optional display title
    title: ?[]const u8 = null,
    /// Optional description
    description: ?[]const u8 = null,
    /// Optional icons
    icons: ?[]const types.Icon = null,
    /// Optional website URL
    websiteUrl: ?[]const u8 = null,
    /// Optional instructions for clients
    instructions: ?[]const u8 = null,
    /// Allocator to use
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

/// Current state of the server
pub const ServerState = enum {
    /// Server is not yet initialized
    uninitialized,
    /// Server is initializing (received initialize, not yet confirmed)
    initializing,
    /// Server is ready to handle requests
    ready,
    /// Server is shutting down
    shutting_down,
    /// Server has stopped
    stopped,
};

/// MCP Server that handles client connections and routes requests
pub const Server = struct {
    config: ServerConfig,
    allocator: std.mem.Allocator,
    state: ServerState = .uninitialized,

    // Registered features
    tools: std.StringHashMap(tools_mod.Tool),
    resources: std.StringHashMap(resources_mod.Resource),
    resource_templates: std.StringHashMap(resources_mod.ResourceTemplate),
    prompts: std.StringHashMap(prompts_mod.Prompt),

    // Capabilities
    capabilities: types.ServerCapabilities = .{},

    // Client info (set during initialization)
    client_info: ?types.Implementation = null,
    client_capabilities: ?types.ClientCapabilities = null,

    // Transport
    transport: ?transport_mod.Transport = null,
    stdio_transport: ?*transport_mod.StdioTransport = null,

    // Request ID counter
    next_request_id: i64 = 1,

    // Pending requests (for tracking responses)
    pending_requests: std.AutoHashMap(i64, PendingRequest),

    // Log level
    log_level: protocol.LogLevel = .info,

    const Self = @This();

    /// Pending request information
    pub const PendingRequest = struct {
        method: []const u8,
        timestamp: i64,
    };

    /// Initialize a new MCP Server
    pub fn init(config: ServerConfig) Self {
        const allocator = config.allocator;
        return .{
            .config = config,
            .allocator = allocator,
            .tools = std.StringHashMap(tools_mod.Tool).init(allocator),
            .resources = std.StringHashMap(resources_mod.Resource).init(allocator),
            .resource_templates = std.StringHashMap(resources_mod.ResourceTemplate).init(allocator),
            .prompts = std.StringHashMap(prompts_mod.Prompt).init(allocator),
            .pending_requests = std.AutoHashMap(i64, PendingRequest).init(allocator),
        };
    }

    /// Clean up server resources
    pub fn deinit(self: *Self) void {
        self.tools.deinit();
        self.resources.deinit();
        self.resource_templates.deinit();
        self.prompts.deinit();
        self.pending_requests.deinit();

        if (self.stdio_transport) |t| {
            t.deinit();
            self.allocator.destroy(t);
        }
    }

    /// Add a tool to the server
    pub fn addTool(self: *Self, tool: tools_mod.Tool) !void {
        try self.tools.put(tool.name, tool);
        // Update capabilities
        self.capabilities.tools = .{ .listChanged = true };
    }

    /// Add a resource to the server
    pub fn addResource(self: *Self, resource: resources_mod.Resource) !void {
        try self.resources.put(resource.uri, resource);
        // Update capabilities
        self.capabilities.resources = .{ .listChanged = true, .subscribe = false };
    }

    /// Add a resource template to the server
    pub fn addResourceTemplate(self: *Self, template: resources_mod.ResourceTemplate) !void {
        try self.resource_templates.put(template.name, template);
    }

    /// Add a prompt to the server
    pub fn addPrompt(self: *Self, prompt: prompts_mod.Prompt) !void {
        try self.prompts.put(prompt.name, prompt);
        // Update capabilities
        self.capabilities.prompts = .{ .listChanged = true };
    }

    /// Enable logging capability
    pub fn enableLogging(self: *Self) void {
        self.capabilities.logging = .{};
    }

    /// Enable completion capability
    pub fn enableCompletions(self: *Self) void {
        self.capabilities.completions = .{};
    }

    /// Options for running the server
    pub const RunOptions = union(enum) {
        stdio: void,
        http: struct { port: u16 = 8080, host: []const u8 = "localhost" },
    };

    /// Run the server with the specified transport
    pub fn run(self: *Self, options: RunOptions) !void {
        switch (options) {
            .stdio => {
                self.log("Server listening on STDIO");
                const stdio = try self.allocator.create(transport_mod.StdioTransport);
                stdio.* = transport_mod.StdioTransport.init(self.allocator);
                self.stdio_transport = stdio;
                self.transport = stdio.transport();
                try self.messageLoop();
            },
            .http => |config| {
                const url = try std.fmt.allocPrint(self.allocator, "http://{s}:{d}", .{ config.host, config.port });
                defer self.allocator.free(url);

                std.log.info("Server listening on {s}", .{url});

                const http = try self.allocator.create(transport_mod.HttpTransport);
                http.* = try transport_mod.HttpTransport.init(self.allocator, url);
                self.transport = http.transport();
                try self.messageLoop();
            },
        }
    }

    /// Run the server with a custom transport
    pub fn runWithTransport(self: *Self, t: transport_mod.Transport) !void {
        self.transport = t;
        try self.messageLoop();
    }

    /// Main message processing loop
    fn messageLoop(self: *Self) !void {
        while (self.state != .stopped and self.state != .shutting_down) {
            // Receive next message
            const message_data = self.transport.?.receive() catch |err| {
                switch (err) {
                    error.EndOfStream => {
                        self.state = .shutting_down;
                        break;
                    },
                    else => {
                        self.logError("Transport receive error");
                        continue;
                    },
                }
            };

            if (message_data) |data| {
                // url is required by transport and must handle its own lifetime or leak for server duration
                // defer self.allocator.free(url);
                try self.handleMessage(data);
            }
        }

        self.state = .stopped;
    }

    /// Handle an incoming message
    fn handleMessage(self: *Self, data: []const u8) !void {
        // Parse the JSON-RPC message
        const parsed_message = jsonrpc.parseMessage(self.allocator, data) catch {
            // Send parse error response
            const error_response = jsonrpc.createParseError(null);
            try self.sendResponse(.{ .error_response = error_response });
            return;
        };
        defer parsed_message.deinit();

        switch (parsed_message.message) {
            .request => |req| try self.handleRequest(req),
            .notification => |notif| try self.handleNotification(notif),
            .response => |resp| self.handleResponse(resp),
            .error_response => |err| self.handleErrorResponse(err),
        }
    }

    /// Handle an incoming request
    fn handleRequest(self: *Self, request: jsonrpc.Request) !void {
        // Log request
        var buf: [256]u8 = undefined;
        if (std.fmt.bufPrint(&buf, "Received request: {s}", .{request.method})) |msg| {
            self.log(msg);
        } else |_| {}

        // Check if server is initialized (except for initialize request)
        if (self.state == .uninitialized and !std.mem.eql(u8, request.method, "initialize")) {
            const error_response = jsonrpc.createErrorResponse(
                request.id,
                jsonrpc.ErrorCode.SERVER_NOT_INITIALIZED,
                "Server not initialized",
                null,
            );
            try self.sendResponse(.{ .error_response = error_response });
            return;
        }

        // Route request to appropriate handler
        if (std.mem.eql(u8, request.method, "initialize")) {
            try self.handleInitialize(request);
        } else if (std.mem.eql(u8, request.method, "ping")) {
            try self.handlePing(request);
        } else if (std.mem.eql(u8, request.method, "tools/list")) {
            try self.handleToolsList(request);
        } else if (std.mem.eql(u8, request.method, "tools/call")) {
            try self.handleToolsCall(request);
        } else if (std.mem.eql(u8, request.method, "resources/list")) {
            try self.handleResourcesList(request);
        } else if (std.mem.eql(u8, request.method, "resources/read")) {
            try self.handleResourcesRead(request);
        } else if (std.mem.eql(u8, request.method, "resources/templates/list")) {
            try self.handleResourceTemplatesList(request);
        } else if (std.mem.eql(u8, request.method, "prompts/list")) {
            try self.handlePromptsList(request);
        } else if (std.mem.eql(u8, request.method, "prompts/get")) {
            try self.handlePromptsGet(request);
        } else if (std.mem.eql(u8, request.method, "logging/setLevel")) {
            try self.handleSetLogLevel(request);
        } else if (std.mem.eql(u8, request.method, "completion/complete")) {
            try self.handleCompletion(request);
        } else {
            // Method not found
            const error_response = jsonrpc.createMethodNotFound(request.id, request.method);
            try self.sendResponse(.{ .error_response = error_response });
        }
    }

    /// Handle initialize request
    fn handleInitialize(self: *Self, request: jsonrpc.Request) !void {
        self.state = .initializing;

        // Parse client info from params
        if (request.params) |params| {
            if (params == .object) {
                const obj = params.object;

                // Extract client info
                if (obj.get("clientInfo")) |client_info_val| {
                    if (client_info_val == .object) {
                        const ci = client_info_val.object;
                        self.client_info = .{
                            .name = if (ci.get("name")) |n| if (n == .string) n.string else "unknown" else "unknown",
                            .version = if (ci.get("version")) |v| if (v == .string) v.string else "0.0.0" else "0.0.0",
                        };
                    }
                }
            }
        }

        // Build response
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();

        try result.put("protocolVersion", .{ .string = protocol.VERSION });

        // Build capabilities object
        var caps = std.json.ObjectMap.init(self.allocator);
        if (self.capabilities.tools != null) {
            var tools_cap = std.json.ObjectMap.init(self.allocator);
            try tools_cap.put("listChanged", .{ .bool = true });
            try caps.put("tools", .{ .object = tools_cap });
        }
        if (self.capabilities.resources != null) {
            var res_cap = std.json.ObjectMap.init(self.allocator);
            try res_cap.put("listChanged", .{ .bool = true });
            try res_cap.put("subscribe", .{ .bool = false });
            try caps.put("resources", .{ .object = res_cap });
        }
        if (self.capabilities.prompts != null) {
            var prompts_cap = std.json.ObjectMap.init(self.allocator);
            try prompts_cap.put("listChanged", .{ .bool = true });
            try caps.put("prompts", .{ .object = prompts_cap });
        }
        if (self.capabilities.logging != null) {
            try caps.put("logging", .{ .object = std.json.ObjectMap.init(self.allocator) });
        }
        try result.put("capabilities", .{ .object = caps });

        // Build server info
        var server_info = std.json.ObjectMap.init(self.allocator);
        try server_info.put("name", .{ .string = self.config.name });
        try server_info.put("version", .{ .string = self.config.version });
        if (self.config.title) |t| {
            try server_info.put("title", .{ .string = t });
        }
        if (self.config.description) |d| {
            try server_info.put("description", .{ .string = d });
        }
        try result.put("serverInfo", .{ .object = server_info });

        if (self.config.instructions) |inst| {
            try result.put("instructions", .{ .string = inst });
        }

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    /// Handle ping request
    fn handlePing(self: *Self, request: jsonrpc.Request) !void {
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    /// Handle tools/list request
    fn handleToolsList(self: *Self, request: jsonrpc.Request) !void {
        var tools_array = std.json.Array.init(self.allocator);

        var iter = self.tools.iterator();
        while (iter.next()) |entry| {
            var tool_obj = std.json.ObjectMap.init(self.allocator);
            try tool_obj.put("name", .{ .string = entry.value_ptr.name });
            if (entry.value_ptr.description) |desc| {
                try tool_obj.put("description", .{ .string = desc });
            }
            if (entry.value_ptr.title) |t| {
                try tool_obj.put("title", .{ .string = t });
            }

            // Add input schema
            // First check if tool has its own inputSchema (e.g., for dynamic tools)
            var schema_opt = entry.value_ptr.inputSchema;
            // Fall back to name-based schema for specific tools
            if (schema_opt == null) {
                schema_opt = buildToolInputSchema(self.allocator, entry.value_ptr.name);
            }
            // Last resort: derive from description
            if (schema_opt == null) {
                if (entry.value_ptr.description) |desc| {
                    schema_opt = deriveSchemaFromDescription(self.allocator, desc);
                }
            }
            const tool_schema = schema_opt orelse types.InputSchema{};
            var input_schema = std.json.ObjectMap.init(self.allocator);
            _ = input_schema.put("type", .{ .string = tool_schema.type }) catch {};
            if (tool_schema.properties) |props| {
                _ = input_schema.put("properties", props) catch {};
            }
            if (tool_schema.required) |req| {
                var req_arr = std.json.Array.init(self.allocator);
                for (req) |name| _ = req_arr.append(.{ .string = name }) catch {};
                _ = input_schema.put("required", .{ .array = req_arr }) catch {};
            }
            if (tool_schema.description) |desc| {
                _ = input_schema.put("description", .{ .string = desc }) catch {};
            }

            _ = tool_obj.put("inputSchema", .{ .object = input_schema }) catch {};

            // Add metadata if present (for MCP Apps UI support)
            if (entry.value_ptr.metadata) |meta| {
                _ = tool_obj.put("_meta", meta) catch {};
            }

            try tools_array.append(.{ .object = tool_obj });
        }

        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("tools", .{ .array = tools_array });

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    fn buildToolInputSchema(allocator: std.mem.Allocator, tool_name: []const u8) ?types.InputSchema {
        // Only provide detailed schemas for Privy wallet tools right now.
        if (std.mem.eql(u8, tool_name, "privy_create_wallet")) {
            return makeSchema(allocator, &.{
                .{ .name = "chain_type", .desc = "Target chain type", .required = true, .enum_values = &.{
                    "ethereum", "solana", "cosmos", "stellar", "sui", "aptos", "movement", "tron", "bitcoin-segwit", "near", "ton", "starknet", "spark",
                } },
                .{ .name = "user_id", .desc = "Privy user id (did:privy:xxx)", .required = false, .enum_values = null },
            });
        }
        if (std.mem.eql(u8, tool_name, "privy_list_wallets")) {
            return makeSchema(allocator, &.{
                .{ .name = "chain_type", .desc = "Filter by chain type", .required = false, .enum_values = &.{
                    "ethereum", "solana", "cosmos", "stellar", "sui", "aptos", "movement", "tron", "bitcoin-segwit", "near", "ton", "starknet", "spark",
                } },
                .{ .name = "cursor", .desc = "Pagination cursor", .required = false, .enum_values = null },
                .{ .name = "limit", .desc = "Max results (default 100)", .required = false, .enum_values = null },
            });
        }
        if (std.mem.eql(u8, tool_name, "privy_sign_message")) {
            return makeSchema(allocator, &.{
                .{ .name = "wallet_id", .desc = "Privy wallet id", .required = true, .enum_values = null },
                .{ .name = "message", .desc = "Message to sign", .required = true, .enum_values = null },
                .{ .name = "chain_type", .desc = "solana or ethereum", .required = true, .enum_values = &.{ "solana", "ethereum" } },
                .{ .name = "network", .desc = "mainnet/devnet/testnet (default mainnet)", .required = false, .enum_values = null },
            });
        }
        if (std.mem.eql(u8, tool_name, "privy_sign_transaction")) {
            return makeSchema(allocator, &.{
                .{ .name = "wallet_id", .desc = "Privy wallet id", .required = true, .enum_values = null },
                .{ .name = "transaction", .desc = "Base64 encoded transaction", .required = true, .enum_values = null },
                .{ .name = "chain_type", .desc = "solana or ethereum", .required = true, .enum_values = &.{ "solana", "ethereum" } },
                .{ .name = "network", .desc = "mainnet/devnet/testnet (default mainnet)", .required = false, .enum_values = null },
            });
        }
        if (std.mem.eql(u8, tool_name, "privy_sign_and_send_transaction")) {
            return makeSchema(allocator, &.{
                .{ .name = "wallet_id", .desc = "Privy wallet id", .required = true, .enum_values = null },
                .{ .name = "transaction", .desc = "Base64 encoded transaction", .required = true, .enum_values = null },
                .{ .name = "chain_type", .desc = "solana or ethereum", .required = true, .enum_values = &.{ "solana", "ethereum" } },
                .{ .name = "network", .desc = "mainnet/devnet/testnet (default mainnet)", .required = false, .enum_values = null },
                .{ .name = "sponsor", .desc = "Enable gas sponsorship (true/false)", .required = false, .enum_values = null },
            });
        }
        return null;
    }

    const Field = struct {
        name: []const u8,
        desc: ?[]const u8,
        required: bool,
        enum_values: ?[]const []const u8,
    };

    fn makeSchema(allocator: std.mem.Allocator, fields: []const Field) types.InputSchema {
        var properties = std.json.ObjectMap.init(allocator);
        var required = std.ArrayList([]const u8).empty;

        for (fields) |field| {
            var prop = std.json.ObjectMap.init(allocator);
            _ = prop.put("type", .{ .string = "string" }) catch {};
            if (field.desc) |d| _ = prop.put("description", .{ .string = d }) catch {};
            if (field.enum_values) |vals| {
                var arr = std.json.Array.init(allocator);
                for (vals) |v| _ = arr.append(.{ .string = v }) catch {};
                _ = prop.put("enum", .{ .array = arr }) catch {};
            }
            _ = properties.put(field.name, .{ .object = prop }) catch {};
            if (field.required) {
                _ = required.append(allocator, field.name) catch {};
            }
        }

        return .{
            .type = "object",
            .properties = .{ .object = properties },
            .required = required.toOwnedSlice(allocator) catch null,
        };
    }

    fn deriveSchemaFromDescription(allocator: std.mem.Allocator, desc: []const u8) ?types.InputSchema {
        const marker = "Parameters:";
        const start_idx = std.mem.indexOf(u8, desc, marker) orelse return null;
        var rest = desc[start_idx + marker.len ..];
        if (std.mem.indexOfScalar(u8, rest, '.')) |dot| {
            rest = rest[0..dot];
        }
        if (std.mem.indexOfScalar(u8, rest, '\n')) |nl| {
            rest = rest[0..nl];
        }

        var properties = std.json.ObjectMap.init(allocator);
        var required = std.ArrayList([]const u8).empty;

        var it = std.mem.splitScalar(u8, rest, ',');
        while (it.next()) |seg_raw| {
            var seg = std.mem.trim(u8, seg_raw, " \t\r\n");
            if (seg.len == 0) continue;

            const optional = std.ascii.indexOfIgnoreCase(seg, "optional") != null;
            // take name before space or '(' if present
            if (std.mem.indexOfAny(u8, seg, " (")) |cut| {
                seg = seg[0..cut];
            }
            if (seg.len == 0) continue;

            var prop = std.json.ObjectMap.init(allocator);
            _ = prop.put("type", .{ .string = "string" }) catch {};
            _ = properties.put(seg, .{ .object = prop }) catch {};
            if (!optional) {
                _ = required.append(allocator, seg) catch {};
            }
        }

        if (properties.count() == 0) return null;
        return .{
            .type = "object",
            .properties = .{ .object = properties },
            .required = required.toOwnedSlice(allocator) catch null,
        };
    }

    /// Handle tools/call request
    fn handleToolsCall(self: *Self, request: jsonrpc.Request) !void {
        // Parse tool name and arguments from params
        var tool_name: []const u8 = "";
        var arguments: ?std.json.Value = null;

        if (request.params) |params| {
            if (params == .object) {
                if (params.object.get("name")) |name_val| {
                    if (name_val == .string) {
                        tool_name = name_val.string;
                    }
                }
                if (params.object.get("arguments")) |args_val| {
                    arguments = args_val;
                } else {
                    // Some clients pass arguments at the top-level of params.
                    arguments = params;
                }
            }
        }

        // Find the tool
        if (self.tools.get(tool_name)) |tool| {
            // Inject tool_name into arguments for dynamic tool handlers
            // This allows handlers to identify which tool is being called
            var modified_arguments = arguments;
            if (arguments) |args| {
                if (args == .object) {
                    // Clone the object and add _tool_name
                    var args_obj = std.json.ObjectMap.init(self.allocator);
                    var it = args.object.iterator();
                    while (it.next()) |entry| {
                        try args_obj.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                    try args_obj.put("_tool_name", .{ .string = tool_name });
                    modified_arguments = .{ .object = args_obj };
                }
            } else {
                // No arguments, create object with just tool_name
                var args_obj = std.json.ObjectMap.init(self.allocator);
                try args_obj.put("_tool_name", .{ .string = tool_name });
                modified_arguments = .{ .object = args_obj };
            }

            // Execute the tool
            const tool_result = tool.handler(self.allocator, modified_arguments) catch |err| {
                // Return error result
                var content_array = std.json.Array.init(self.allocator);
                var text_obj = std.json.ObjectMap.init(self.allocator);
                try text_obj.put("type", .{ .string = "text" });
                try text_obj.put("text", .{ .string = @errorName(err) });
                try content_array.append(.{ .object = text_obj });

                var result = std.json.ObjectMap.init(self.allocator);
                try result.put("content", .{ .array = content_array });
                try result.put("isError", .{ .bool = true });

                const response = jsonrpc.createResponse(request.id, .{ .object = result });
                try self.sendResponse(.{ .response = response });
                return;
            };

            // Build success response
            var content_array = std.json.Array.init(self.allocator);
            for (tool_result.content) |content_item| {
                var item_obj = std.json.ObjectMap.init(self.allocator);
                switch (content_item) {
                    .text => |text| {
                        try item_obj.put("type", .{ .string = "text" });
                        try item_obj.put("text", .{ .string = text.text });
                    },
                    .image => |img| {
                        try item_obj.put("type", .{ .string = "image" });
                        try item_obj.put("data", .{ .string = img.data });
                        try item_obj.put("mimeType", .{ .string = img.mimeType });
                    },
                    .resource => |res| {
                        try item_obj.put("type", .{ .string = "resource" });
                        var resource_obj = std.json.ObjectMap.init(self.allocator);
                        try resource_obj.put("uri", .{ .string = res.resource.uri });
                        if (res.resource.mimeType) |mt| {
                            try resource_obj.put("mimeType", .{ .string = mt });
                        }
                        if (res.resource.text) |text| {
                            try resource_obj.put("text", .{ .string = text });
                        }
                        if (res.resource.blob) |blob| {
                            try resource_obj.put("blob", .{ .string = blob });
                        }
                        try item_obj.put("resource", .{ .object = resource_obj });
                    },
                }
                try content_array.append(.{ .object = item_obj });
            }

            var result = std.json.ObjectMap.init(self.allocator);
            try result.put("content", .{ .array = content_array });
            try result.put("isError", .{ .bool = tool_result.is_error });

            const response = jsonrpc.createResponse(request.id, .{ .object = result });
            try self.sendResponse(.{ .response = response });
        } else {
            // Tool not found
            const error_response = jsonrpc.createInvalidParams(request.id, "Tool not found");
            try self.sendResponse(.{ .error_response = error_response });
        }
    }

    /// Handle resources/list request
    fn handleResourcesList(self: *Self, request: jsonrpc.Request) !void {
        var resources_array = std.json.Array.init(self.allocator);

        var iter = self.resources.iterator();
        while (iter.next()) |entry| {
            var resource_obj = std.json.ObjectMap.init(self.allocator);
            try resource_obj.put("uri", .{ .string = entry.value_ptr.uri });
            try resource_obj.put("name", .{ .string = entry.value_ptr.name });
            if (entry.value_ptr.description) |desc| {
                try resource_obj.put("description", .{ .string = desc });
            }
            if (entry.value_ptr.mimeType) |mime| {
                try resource_obj.put("mimeType", .{ .string = mime });
            }
            try resources_array.append(.{ .object = resource_obj });
        }

        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("resources", .{ .array = resources_array });

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    /// Handle resources/read request
    fn handleResourcesRead(self: *Self, request: jsonrpc.Request) !void {
        var uri: []const u8 = "";

        if (request.params) |params| {
            if (params == .object) {
                if (params.object.get("uri")) |uri_val| {
                    if (uri_val == .string) {
                        uri = uri_val.string;
                    }
                }
            }
        }

        const resource_opt = self.resources.get(uri) orelse blk: {
            if (std.mem.indexOfScalar(u8, uri, '?')) |pos| {
                break :blk self.resources.get(uri[0..pos]);
            }
            break :blk null;
        };

        if (resource_opt) |resource| {
            const content = resource.handler(self.allocator, uri) catch |err| {
                const error_response = jsonrpc.createInternalError(request.id, .{ .string = @errorName(err) });
                try self.sendResponse(.{ .error_response = error_response });
                return;
            };

            var contents_array = std.json.Array.init(self.allocator);
            var content_obj = std.json.ObjectMap.init(self.allocator);
            try content_obj.put("uri", .{ .string = uri });
            if (content.text) |text| {
                try content_obj.put("text", .{ .string = text });
            }
            if (content.mimeType) |mime| {
                try content_obj.put("mimeType", .{ .string = mime });
            }
            try contents_array.append(.{ .object = content_obj });

            var result = std.json.ObjectMap.init(self.allocator);
            try result.put("contents", .{ .array = contents_array });

            const response = jsonrpc.createResponse(request.id, .{ .object = result });
            try self.sendResponse(.{ .response = response });
        } else {
            const error_response = jsonrpc.createInvalidParams(request.id, "Resource not found");
            try self.sendResponse(.{ .error_response = error_response });
        }
    }

    /// Handle resources/templates/list request
    fn handleResourceTemplatesList(self: *Self, request: jsonrpc.Request) !void {
        var templates_array = std.json.Array.init(self.allocator);

        var iter = self.resource_templates.iterator();
        while (iter.next()) |entry| {
            var template_obj = std.json.ObjectMap.init(self.allocator);
            try template_obj.put("uriTemplate", .{ .string = entry.value_ptr.uriTemplate });
            try template_obj.put("name", .{ .string = entry.value_ptr.name });
            if (entry.value_ptr.description) |desc| {
                try template_obj.put("description", .{ .string = desc });
            }
            if (entry.value_ptr.mimeType) |mime| {
                try template_obj.put("mimeType", .{ .string = mime });
            }
            try templates_array.append(.{ .object = template_obj });
        }

        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("resourceTemplates", .{ .array = templates_array });

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    /// Handle prompts/list request
    fn handlePromptsList(self: *Self, request: jsonrpc.Request) !void {
        var prompts_array = std.json.Array.init(self.allocator);

        var iter = self.prompts.iterator();
        while (iter.next()) |entry| {
            var prompt_obj = std.json.ObjectMap.init(self.allocator);
            try prompt_obj.put("name", .{ .string = entry.value_ptr.name });
            if (entry.value_ptr.description) |desc| {
                try prompt_obj.put("description", .{ .string = desc });
            }
            if (entry.value_ptr.title) |t| {
                try prompt_obj.put("title", .{ .string = t });
            }

            // Add arguments if present
            if (entry.value_ptr.arguments) |args| {
                var args_array = std.json.Array.init(self.allocator);
                for (args) |arg| {
                    var arg_obj = std.json.ObjectMap.init(self.allocator);
                    try arg_obj.put("name", .{ .string = arg.name });
                    if (arg.description) |d| {
                        try arg_obj.put("description", .{ .string = d });
                    }
                    try arg_obj.put("required", .{ .bool = arg.required });
                    try args_array.append(.{ .object = arg_obj });
                }
                try prompt_obj.put("arguments", .{ .array = args_array });
            }

            try prompts_array.append(.{ .object = prompt_obj });
        }

        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("prompts", .{ .array = prompts_array });

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    /// Handle prompts/get request
    fn handlePromptsGet(self: *Self, request: jsonrpc.Request) !void {
        var prompt_name: []const u8 = "";
        var arguments: ?std.json.Value = null;

        if (request.params) |params| {
            if (params == .object) {
                if (params.object.get("name")) |name_val| {
                    if (name_val == .string) {
                        prompt_name = name_val.string;
                    }
                }
                arguments = params.object.get("arguments");
            }
        }

        if (self.prompts.get(prompt_name)) |prompt| {
            const messages = prompt.handler(self.allocator, arguments) catch |err| {
                const error_response = jsonrpc.createInternalError(request.id, .{ .string = @errorName(err) });
                try self.sendResponse(.{ .error_response = error_response });
                return;
            };

            var messages_array = std.json.Array.init(self.allocator);
            for (messages) |msg| {
                var msg_obj = std.json.ObjectMap.init(self.allocator);
                try msg_obj.put("role", .{ .string = msg.role });
                var content_obj = std.json.ObjectMap.init(self.allocator);
                try content_obj.put("type", .{ .string = "text" });
                try content_obj.put("text", .{ .string = msg.content.asText() orelse "" });
                try msg_obj.put("content", .{ .object = content_obj });
                try messages_array.append(.{ .object = msg_obj });
            }

            var result = std.json.ObjectMap.init(self.allocator);
            try result.put("messages", .{ .array = messages_array });
            if (prompt.description) |desc| {
                try result.put("description", .{ .string = desc });
            }

            const response = jsonrpc.createResponse(request.id, .{ .object = result });
            try self.sendResponse(.{ .response = response });
        } else {
            const error_response = jsonrpc.createInvalidParams(request.id, "Prompt not found");
            try self.sendResponse(.{ .error_response = error_response });
        }
    }

    /// Handle logging/setLevel request
    fn handleSetLogLevel(self: *Self, request: jsonrpc.Request) !void {
        if (request.params) |params| {
            if (params == .object) {
                if (params.object.get("level")) |level_val| {
                    if (level_val == .string) {
                        const level_str = level_val.string;
                        if (std.mem.eql(u8, level_str, "debug")) {
                            self.log_level = .debug;
                        } else if (std.mem.eql(u8, level_str, "info")) {
                            self.log_level = .info;
                        } else if (std.mem.eql(u8, level_str, "warning")) {
                            self.log_level = .warning;
                        } else if (std.mem.eql(u8, level_str, "error")) {
                            self.log_level = .@"error";
                        }
                    }
                }
            }
        }

        const result = std.json.ObjectMap.init(self.allocator);
        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    /// Handle completion/complete request
    fn handleCompletion(self: *Self, request: jsonrpc.Request) !void {
        // Return empty completion for now
        var completion = std.json.ObjectMap.init(self.allocator);

        const values_array = std.json.Array.init(self.allocator);
        try completion.put("values", .{ .array = values_array });
        try completion.put("hasMore", .{ .bool = false });

        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("completion", .{ .object = completion });

        const response = jsonrpc.createResponse(request.id, .{ .object = result });
        try self.sendResponse(.{ .response = response });
    }

    // ========================================================================
    // Notification Handling
    // ========================================================================

    /// Handle incoming notifications
    fn handleNotification(self: *Self, notification: jsonrpc.Notification) !void {
        if (std.mem.eql(u8, notification.method, "notifications/initialized")) {
            self.state = .ready;
            self.log("Server initialized and ready");
        } else if (std.mem.eql(u8, notification.method, "notifications/cancelled")) {
            // Handle cancellation
            if (notification.params) |params| {
                if (params == .object) {
                    if (params.object.get("requestId")) |req_id| {
                        _ = req_id;
                        // Cancel the request if possible
                    }
                }
            }
        }
    }

    /// Handle incoming response to a request we sent
    fn handleResponse(self: *Self, response: jsonrpc.Response) void {
        // Find and remove pending request
        const id = switch (response.id) {
            .integer => |i| i,
            .string => return, // We only use integer IDs
        };
        _ = self.pending_requests.remove(id);
    }

    /// Handle incoming error response
    fn handleErrorResponse(self: *Self, err: jsonrpc.ErrorResponse) void {
        if (err.id) |id| {
            const int_id = switch (id) {
                .integer => |i| i,
                .string => return,
            };
            _ = self.pending_requests.remove(int_id);
        }
        self.logError(err.@"error".message);
    }

    // ========================================================================
    // Server-initiated Messages
    // ========================================================================

    /// Send a notification to the client
    pub fn sendNotification(self: *Self, method: []const u8, params: ?std.json.Value) !void {
        const notification = jsonrpc.createNotification(method, params);
        try self.sendResponse(.{ .notification = notification });
    }

    /// Send a log message notification
    pub fn sendLogMessage(self: *Self, level: protocol.LogLevel, message: []const u8) !void {
        if (@intFromEnum(level) < @intFromEnum(self.log_level)) return;

        var params = std.json.ObjectMap.init(self.allocator);
        try params.put("level", .{ .string = level.toString() });
        try params.put("data", .{ .string = message });

        try self.sendNotification("notifications/message", .{ .object = params });
    }

    /// Notify clients that tools have changed
    pub fn notifyToolsChanged(self: *Self) !void {
        try self.sendNotification("notifications/tools/list_changed", null);
    }

    /// Notify clients that resources have changed
    pub fn notifyResourcesChanged(self: *Self) !void {
        try self.sendNotification("notifications/resources/list_changed", null);
    }

    /// Notify clients that prompts have changed
    pub fn notifyPromptsChanged(self: *Self) !void {
        try self.sendNotification("notifications/prompts/list_changed", null);
    }

    // ========================================================================
    // Transport
    // ========================================================================

    /// Send a response message
    fn sendResponse(self: *Self, message: jsonrpc.Message) !void {
        if (self.transport) |t| {
            const json = try jsonrpc.serializeMessage(self.allocator, message);
            defer self.allocator.free(json);
            t.send(json) catch {};
        }
    }

    // ========================================================================
    // Logging (to stderr for STDIO transport)
    // ========================================================================

    fn log(self: *Self, message: []const u8) void {
        if (self.stdio_transport) |t| {
            t.writeStderr(message);
        }
    }

    fn logError(self: *Self, message: []const u8) void {
        if (self.stdio_transport) |t| {
            var buf: [512]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "ERROR: {s}", .{message}) catch message;
            t.writeStderr(formatted);
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Server initialization" {
    var server = Server.init(.{
        .name = "test-server",
        .version = "1.0.0",
        .allocator = std.testing.allocator,
    });
    defer server.deinit();

    try std.testing.expectEqual(ServerState.uninitialized, server.state);
    try std.testing.expectEqualStrings("test-server", server.config.name);
}

test "Server add tool" {
    var server = Server.init(.{
        .name = "test-server",
        .version = "1.0.0",
        .allocator = std.testing.allocator,
    });
    defer server.deinit();

    const tool = tools_mod.Tool{
        .name = "test_tool",
        .description = "A test tool",
        .handler = struct {
            fn handler(_: std.mem.Allocator, _: ?std.json.Value) !tools_mod.ToolResult {
                return .{ .content = &.{} };
            }
        }.handler,
    };

    try server.addTool(tool);
    try std.testing.expect(server.tools.contains("test_tool"));
}
