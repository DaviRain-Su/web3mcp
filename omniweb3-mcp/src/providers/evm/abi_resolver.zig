//! EVM ABI Resolver
//!
//! Loads and parses Ethereum ABI (Application Binary Interface) files
//! for dynamic tool generation.
//!
//! Similar to Solana IDL resolver but for EVM contracts.

const std = @import("std");

/// ABI function parameter
pub const AbiParam = struct {
    name: []const u8,
    type: []const u8,
    internal_type: ?[]const u8 = null,
    indexed: bool = false, // For events
    components: ?[]const AbiParam = null, // For tuple types
};

/// ABI function definition
pub const AbiFunction = struct {
    name: []const u8,
    inputs: []const AbiParam,
    outputs: []const AbiParam,
    state_mutability: StateMutability,
    function_type: FunctionType,
    payable: bool = false,

    pub const StateMutability = enum {
        pure, // No state read/write
        view, // Read-only
        nonpayable, // State-changing, no ETH
        payable, // State-changing, can receive ETH
    };

    pub const FunctionType = enum {
        function,
        constructor,
        fallback,
        receive,
    };
};

/// ABI event definition
pub const AbiEvent = struct {
    name: []const u8,
    inputs: []const AbiParam,
    anonymous: bool = false,
};

/// Parsed ABI
pub const Abi = struct {
    functions: []const AbiFunction,
    events: []const AbiEvent,
    constructor: ?AbiFunction = null,
    fallback: ?AbiFunction = null,
    receive: ?AbiFunction = null,
};

/// Contract metadata from contracts.json
pub const ContractMetadata = struct {
    chain: []const u8,
    chain_id: u64,
    address: []const u8,
    name: []const u8,
    display_name: []const u8,
    category: []const u8,
    enabled: bool,
    description: []const u8,
};

/// Read file contents using std.Io
fn readFileAlloc(allocator: std.mem.Allocator, io: *const std.Io, path: []const u8) ![]const u8 {
    // Open file using std.Io.Dir
    const file = std.Io.Dir.cwd().openFile(io.*, path, .{}) catch |err| {
        return err;
    };
    defer file.close(io.*);

    // Get file size
    const stat = try file.stat(io.*);
    const max_size = 10 * 1024 * 1024; // 10MB max
    if (stat.size > max_size) return error.FileTooLarge;

    // Allocate buffer and read
    const content = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(content);

    const bytes_read = try file.readPositionalAll(io.*, content, 0);
    if (bytes_read != stat.size) {
        allocator.free(content);
        return error.UnexpectedEndOfFile;
    }

    return content;
}

/// Get or create a test Io instance (lazy initialization)
var test_io_instance: ?std.Io.Threaded = null;
var test_io_value: ?std.Io = null;
var test_io_mutex: std.Thread.Mutex = .{};

fn getTestIo(allocator: std.mem.Allocator) !*const std.Io {
    test_io_mutex.lock();
    defer test_io_mutex.unlock();

    if (test_io_value) |*io| {
        return io;
    }

    // Initialize Io.Threaded for testing
    test_io_instance = std.Io.Threaded.init(allocator, .{
        .environ = std.process.Environ.empty,
        .argv0 = std.Io.Threaded.Argv0.empty,
    });

    // Get the Io interface from Threaded
    test_io_value = test_io_instance.?.io();

    return &test_io_value.?;
}

/// Read file contents for testing
fn readFileAllocForTest(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const io = try getTestIo(allocator);
    return readFileAlloc(allocator, io, path);
}

/// Load contract metadata from contracts.json
pub fn loadContractMetadata(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    registry_path: []const u8,
) ![]ContractMetadata {
    const content = try readFileAlloc(allocator, io, registry_path);
    defer allocator.free(content);

    return loadContractMetadataFromContent(allocator, content);
}

/// Load contract metadata from contracts.json (for testing)
pub fn loadContractMetadataForTest(
    allocator: std.mem.Allocator,
    registry_path: []const u8,
) ![]ContractMetadata {
    const content = try readFileAllocForTest(allocator, registry_path);
    defer allocator.free(content);

    return loadContractMetadataFromContent(allocator, content);
}

/// Parse contract metadata from JSON content
fn loadContractMetadataFromContent(
    allocator: std.mem.Allocator,
    content: []const u8,
) ![]ContractMetadata {

    const parsed = try std.json.parseFromSlice(
        struct { evm_contracts: []ContractMetadata },
        allocator,
        content,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    // Deep copy the contracts
    const contracts = try allocator.alloc(ContractMetadata, parsed.value.evm_contracts.len);
    for (parsed.value.evm_contracts, 0..) |contract, i| {
        contracts[i] = .{
            .chain = try allocator.dupe(u8, contract.chain),
            .chain_id = contract.chain_id,
            .address = try allocator.dupe(u8, contract.address),
            .name = try allocator.dupe(u8, contract.name),
            .display_name = try allocator.dupe(u8, contract.display_name),
            .category = try allocator.dupe(u8, contract.category),
            .enabled = contract.enabled,
            .description = try allocator.dupe(u8, contract.description),
        };
    }

    return contracts;
}

/// Load ABI from file
pub fn loadAbi(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    abi_path: []const u8,
) !Abi {
    const content = try readFileAlloc(allocator, io, abi_path);
    defer allocator.free(content);

    return parseAbiFromContent(allocator, content);
}

/// Load ABI from file (for testing)
pub fn loadAbiForTest(
    allocator: std.mem.Allocator,
    abi_path: []const u8,
) !Abi {
    const content = try readFileAllocForTest(allocator, abi_path);
    defer allocator.free(content);

    return parseAbiFromContent(allocator, content);
}

/// Parse ABI from JSON content
fn parseAbiFromContent(allocator: std.mem.Allocator, content: []const u8) !Abi {
    // Parse ABI JSON
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        content,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    // Extract functions and events
    var functions: std.ArrayList(AbiFunction) = .empty;
    defer functions.deinit(allocator);

    var events: std.ArrayList(AbiEvent) = .empty;
    defer events.deinit(allocator);

    var constructor: ?AbiFunction = null;
    var fallback: ?AbiFunction = null;
    var receive: ?AbiFunction = null;

    const items = parsed.value.array;
    for (items.items) |item| {
        const obj = item.object;
        const item_type = obj.get("type").?.string;

        if (std.mem.eql(u8, item_type, "function")) {
            const func = try parseFunction(allocator, obj);
            try functions.append(allocator, func);
        } else if (std.mem.eql(u8, item_type, "event")) {
            const event = try parseEvent(allocator, obj);
            try events.append(allocator, event);
        } else if (std.mem.eql(u8, item_type, "constructor")) {
            constructor = try parseFunction(allocator, obj);
        } else if (std.mem.eql(u8, item_type, "fallback")) {
            fallback = try parseFunction(allocator, obj);
        } else if (std.mem.eql(u8, item_type, "receive")) {
            receive = try parseFunction(allocator, obj);
        }
    }

    return Abi{
        .functions = try functions.toOwnedSlice(allocator),
        .events = try events.toOwnedSlice(allocator),
        .constructor = constructor,
        .fallback = fallback,
        .receive = receive,
    };
}

/// Parse ABI function from JSON
fn parseFunction(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
) !AbiFunction {
    const name = if (obj.get("name")) |n| n.string else "";

    // Parse inputs
    const inputs = if (obj.get("inputs")) |inp|
        try parseParams(allocator, inp.array)
    else
        &[_]AbiParam{};

    // Parse outputs
    const outputs = if (obj.get("outputs")) |out|
        try parseParams(allocator, out.array)
    else
        &[_]AbiParam{};

    // Determine state mutability
    const state_mutability: AbiFunction.StateMutability = blk: {
        if (obj.get("stateMutability")) |sm| {
            const sm_str = sm.string;
            if (std.mem.eql(u8, sm_str, "pure")) break :blk .pure;
            if (std.mem.eql(u8, sm_str, "view")) break :blk .view;
            if (std.mem.eql(u8, sm_str, "payable")) break :blk .payable;
            break :blk .nonpayable;
        }
        // Fallback to legacy 'constant' and 'payable' fields
        const constant = if (obj.get("constant")) |c| c.bool else false;
        const payable = if (obj.get("payable")) |p| p.bool else false;
        if (constant) break :blk .view;
        if (payable) break :blk .payable;
        break :blk .nonpayable;
    };

    // Determine function type
    const func_type: AbiFunction.FunctionType = blk: {
        if (obj.get("type")) |t| {
            const type_str = t.string;
            if (std.mem.eql(u8, type_str, "constructor")) break :blk .constructor;
            if (std.mem.eql(u8, type_str, "fallback")) break :blk .fallback;
            if (std.mem.eql(u8, type_str, "receive")) break :blk .receive;
        }
        break :blk .function;
    };

    return AbiFunction{
        .name = try allocator.dupe(u8, name),
        .inputs = inputs,
        .outputs = outputs,
        .state_mutability = state_mutability,
        .function_type = func_type,
        .payable = state_mutability == .payable,
    };
}

/// Parse ABI event from JSON
fn parseEvent(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
) !AbiEvent {
    const name = obj.get("name").?.string;

    const inputs = if (obj.get("inputs")) |inp|
        try parseParams(allocator, inp.array)
    else
        &[_]AbiParam{};

    const anonymous = if (obj.get("anonymous")) |a| a.bool else false;

    return AbiEvent{
        .name = try allocator.dupe(u8, name),
        .inputs = inputs,
        .anonymous = anonymous,
    };
}

/// Parse parameter list
fn parseParams(
    allocator: std.mem.Allocator,
    params: std.json.Array,
) ![]AbiParam {
    var result: std.ArrayList(AbiParam) = .empty;
    defer result.deinit(allocator);

    for (params.items) |param| {
        const obj = param.object;
        const name = if (obj.get("name")) |n| n.string else "";
        const param_type = obj.get("type").?.string;
        const internal_type = if (obj.get("internalType")) |it| it.string else null;
        const indexed = if (obj.get("indexed")) |idx| idx.bool else false;

        // Parse components for tuple types
        const components = if (obj.get("components")) |comp|
            try parseParams(allocator, comp.array)
        else
            null;

        try result.append(allocator, AbiParam{
            .name = try allocator.dupe(u8, name),
            .type = try allocator.dupe(u8, param_type),
            .internal_type = if (internal_type) |it| try allocator.dupe(u8, it) else null,
            .indexed = indexed,
            .components = components,
        });
    }

    return try result.toOwnedSlice(allocator);
}

/// Resolve ABI path for a contract
pub fn resolveAbiPath(
    allocator: std.mem.Allocator,
    chain: []const u8,
    contract_name: []const u8,
) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "abi_registry/{s}/{s}.json",
        .{ chain, contract_name },
    );
}

/// Check if ABI file exists
pub fn abiExists(io: *const std.Io, chain: []const u8, contract_name: []const u8) bool {
    var buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "abi_registry/{s}/{s}.json", .{ chain, contract_name }) catch return false;

    // Try to open file
    const file = std.Io.Dir.cwd().openFile(io.*, path, .{}) catch return false;
    file.close(io.*);
    return true;
}

/// Check if ABI file exists (for testing)
pub fn abiExistsForTest(chain: []const u8, contract_name: []const u8) bool {
    // Use std.heap.page_allocator for one-time test operation
    const io = getTestIo(std.heap.page_allocator) catch return false;
    return abiExists(io, chain, contract_name);
}
