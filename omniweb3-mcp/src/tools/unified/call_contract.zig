const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");
const abi_resolver = @import("../../providers/evm/abi_resolver.zig");

const block = zabi.types.block;
const EthCall = zabi.types.transactions.EthCall;
const Wei = zabi.types.ethereum.Wei;
const encoder = zabi.encoding.abi_encoding;

/// Call a smart contract function with automatic ABI encoding.
///
/// This tool reads the ABI from abi_registry and automatically encodes
/// the function call, making it easy to interact with any contract.
///
/// Parameters:
/// - chain: "bsc" | "ethereum" | "polygon" | "avalanche" (required)
/// - contract: Contract address or name from contracts.json (required)
/// - function: Function name to call (required)
/// - args: Array of function arguments (optional, default: [])
/// - from: Optional sender address
/// - value: Optional value to send (in wei or as string)
///
/// Example:
///   call_contract(
///     chain="bsc",
///     contract="0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
///     function="swapExactTokensForTokens",
///     args=[100000000, 0, ["0xToken1", "0xToken2"], "0xRecipient", 1234567890]
///   )
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Parse basic parameters
    const chain_name = mcp.tools.getString(args, "chain") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: chain") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const contract_str = mcp.tools.getString(args, "contract") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: contract") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const function_name = mcp.tools.getString(args, "function") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: function") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Optional parameters
    const from_str = mcp.tools.getString(args, "from");
    const value_str = mcp.tools.getString(args, "value");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    // Parse contract address
    const contract_address = evm_helpers.parseAddress(contract_str) catch blk: {
        // Maybe it's a contract name, try to resolve from contracts.json
        const resolved = resolveContractAddress(allocator, contract_str, chain_name) catch {
            return mcp.tools.errorResult(allocator, "Invalid contract address or name") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk resolved;
    };

    // Load ABI from abi_registry
    const abi = loadContractAbi(allocator, contract_str, chain_name) catch |err| {
        const msg = std.fmt.allocPrint(
            allocator,
            "Failed to load ABI for contract {s}: {s}",
            .{ contract_str, @errorName(err) }
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer {
        // TODO: Free ABI properly
    }

    // Find function in ABI
    const func = findFunction(abi, function_name) orelse {
        const msg = std.fmt.allocPrint(
            allocator,
            "Function '{s}' not found in contract ABI",
            .{function_name}
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // Encode function call
    // TODO: Parse args from JSON and encode using zabi
    const calldata = encodeFunctionCall(allocator, func, args) catch |err| {
        const msg = std.fmt.allocPrint(
            allocator,
            "Failed to encode function call: {s}",
            .{@errorName(err)}
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(calldata);

    // Parse optional parameters
    const from_address = if (from_str) |value| blk: {
        const addr = evm_helpers.parseAddress(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid from address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk addr;
    } else null;

    const value_wei: ?Wei = if (value_str) |value| blk: {
        const parsed = evm_helpers.parseWeiAmount(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid value") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk parsed;
    } else null;

    // Initialize chain adapter
    var adapter = chain.initEvmAdapter(
        allocator,
        evm_runtime.io(),
        chain_name,
        network,
        null
    ) catch |err| {
        const msg = std.fmt.allocPrint(
            allocator,
            "Failed to init chain adapter: {s}",
            .{@errorName(err)}
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    // Call contract
    const call = EthCall{
        .london = .{
            .from = from_address,
            .to = contract_address,
            .value = value_wei,
            .data = @constCast(calldata),
        }
    };
    const request: block.BlockNumberRequest = .{ .tag = .latest };

    const response = adapter.call(call, request) catch |err| {
        const msg = std.fmt.allocPrint(
            allocator,
            "Contract call failed: {s}",
            .{@errorName(err)}
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer response.deinit();

    // Decode response using ABI
    // TODO: Decode using zabi
    const hex_len = response.response.len * 2;
    const hex_buf = try allocator.alloc(u8, hex_len);
    defer allocator.free(hex_buf);

    const hex_chars = "0123456789abcdef";
    for (response.response, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const result_hex = std.fmt.allocPrint(allocator, "0x{s}", .{hex_buf}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(result_hex);

    // Format response
    const response_json = std.fmt.allocPrint(
        allocator,
        \\{{
        \\  "success": true,
        \\  "chain": "{s}",
        \\  "contract": "{s}",
        \\  "function": "{s}",
        \\  "result_hex": "{s}",
        \\  "note": "Result decoding not yet implemented - showing raw hex"
        \\}}
        ,
        .{ chain_name, contract_str, function_name, result_hex }
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response_json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

/// Resolve contract name to address from contracts.json
fn resolveContractAddress(
    allocator: std.mem.Allocator,
    name: []const u8,
    chain_name: []const u8,
) !zabi.types.ethereum.Address {
    // Read contracts.json using std.Io
    const io = evm_runtime.io();
    const file = try std.Io.Dir.cwd().openFile(io, "abi_registry/contracts.json", .{});
    defer file.close(io);

    const stat = try file.stat(io);
    const content = try allocator.alloc(u8, stat.size);
    defer allocator.free(content);

    _ = try file.readPositionalAll(io, content, 0);

    // Parse JSON
    const parsed = try std.json.parseFromSlice(
        struct {
            evm_contracts: []struct {
                chain: []const u8,
                address: []const u8,
                name: []const u8,
                enabled: bool,
            },
        },
        allocator,
        content,
        .{}
    );
    defer parsed.deinit();

    // Find matching contract
    for (parsed.value.evm_contracts) |contract| {
        if (!contract.enabled) continue;
        if (std.mem.eql(u8, contract.chain, chain_name) and
            std.mem.eql(u8, contract.name, name))
        {
            return try evm_helpers.parseAddress(contract.address);
        }
    }

    return error.ContractNotFound;
}

/// Load ABI for a contract
fn loadContractAbi(
    allocator: std.mem.Allocator,
    contract: []const u8,
    chain_name: []const u8,
) !abi_resolver.Abi {
    // First, try to find the contract in contracts.json to get the actual name
    const io = evm_runtime.io();
    var contract_name: []const u8 = contract;

    // Try to read contracts.json to find the real contract name
    const file_result = std.Io.Dir.cwd().openFile(io, "abi_registry/contracts.json", .{});
    if (file_result) |file| {
        defer file.close(io);

        const stat = file.stat(io) catch |err| {
            std.log.warn("Failed to stat contracts.json: {}", .{err});
            // Fall through to use input contract name
            return error.FileNotFound;
        };

        const content = allocator.alloc(u8, stat.size) catch {
            return error.OutOfMemory;
        };
        defer allocator.free(content);

        _ = file.readPositionalAll(io, content, 0) catch {
            // Fall through to use input contract name
            return error.FileNotFound;
        };

        // Parse JSON to find the contract
        const parsed = std.json.parseFromSlice(
            struct {
                evm_contracts: []struct {
                    chain: []const u8,
                    address: []const u8,
                    name: []const u8,
                    enabled: bool,
                },
            },
            allocator,
            content,
            .{},
        ) catch {
            return error.FileNotFound;
        };
        defer parsed.deinit();

        // Find matching contract by address or name
        for (parsed.value.evm_contracts) |c| {
            if (!c.enabled) continue;
            if (!std.mem.eql(u8, c.chain, chain_name)) continue;

            // Match by address or name
            const is_address = evm_helpers.parseAddress(contract) catch null;
            const contract_addr = evm_helpers.parseAddress(c.address) catch continue;

            if (is_address) |addr| {
                if (std.mem.eql(u8, &addr, &contract_addr)) {
                    contract_name = c.name;
                    break;
                }
            } else if (std.mem.eql(u8, c.name, contract)) {
                contract_name = c.name;
                break;
            }
        }
    } else |_| {
        // contracts.json not found, continue with provided name
    }

    // Build ABI path: abi_registry/{chain}/{name}.json
    const abi_path = try std.fmt.allocPrint(
        allocator,
        "abi_registry/{s}/{s}.json",
        .{ chain_name, contract_name },
    );
    defer allocator.free(abi_path);

    // Load ABI using abi_resolver
    const io_val = evm_runtime.io();
    return try abi_resolver.loadAbi(allocator, &io_val, abi_path);
}

/// Find function in ABI
fn findFunction(abi: abi_resolver.Abi, name: []const u8) ?abi_resolver.AbiFunction {
    for (abi.functions) |func| {
        if (std.mem.eql(u8, func.name, name)) {
            return func;
        }
    }
    return null;
}

/// Encode function call using ABI
fn encodeFunctionCall(
    allocator: std.mem.Allocator,
    func: abi_resolver.AbiFunction,
    args: ?std.json.Value,
) ![]const u8 {
    // Import zabi encoding
    const Keccak256 = std.crypto.hash.sha3.Keccak256;

    // Step 1: Compute function selector (first 4 bytes of keccak256(signature))
    var sig_buffer: [256]u8 = undefined;
    const sig = try buildFunctionSignature(allocator, func, &sig_buffer);

    var hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(sig, &hash, .{});

    const selector = hash[0..4];

    // Step 2: Parse and encode parameters
    const encoded_params = if (args) |arg_value| blk: {
        // Parse JSON args into AbiEncodedValues
        const abi_values = try parseArgsToAbiValues(allocator, func.inputs, arg_value);
        defer allocator.free(abi_values);

        // Encode using zabi
        break :blk try encoder.encodeAbiParametersValues(allocator, abi_values);
    } else if (func.inputs.len > 0) {
        return error.MissingArguments;
    } else blk: {
        // No parameters
        break :blk try allocator.alloc(u8, 0);
    };
    defer allocator.free(encoded_params);

    // Step 3: Concatenate selector + encoded params
    const calldata = try allocator.alloc(u8, 4 + encoded_params.len);
    @memcpy(calldata[0..4], selector);
    @memcpy(calldata[4..], encoded_params);

    return calldata;
}

/// Build function signature string (e.g., "transfer(address,uint256)")
fn buildFunctionSignature(
    allocator: std.mem.Allocator,
    func: abi_resolver.AbiFunction,
    buffer: []u8,
) ![]const u8 {
    // Build parameter list
    var params_list: std.ArrayList(u8) = .empty;
    defer params_list.deinit(allocator);

    for (func.inputs, 0..) |input, i| {
        try params_list.appendSlice(allocator, input.type);
        if (i < func.inputs.len - 1) {
            try params_list.appendSlice(allocator, ",");
        }
    }

    const params = try params_list.toOwnedSlice(allocator);
    defer allocator.free(params);

    // Build full signature
    return std.fmt.bufPrint(buffer, "{s}({s})", .{ func.name, params });
}

/// Parse JSON args to AbiEncodedValues for encoding
fn parseArgsToAbiValues(
    allocator: std.mem.Allocator,
    params: []const abi_resolver.AbiParam,
    args_value: std.json.Value,
) ![]const encoder.AbiEncodedValues {
    // Args should be an array
    const args_array = switch (args_value) {
        .array => |arr| arr.items,
        else => return error.InvalidArguments,
    };

    if (args_array.len != params.len) {
        return error.ArgumentCountMismatch;
    }

    const values = try allocator.alloc(encoder.AbiEncodedValues, params.len);
    errdefer allocator.free(values);

    for (params, args_array, 0..) |param, arg, i| {
        values[i] = try parseJsonToAbiValue(allocator, param.type, arg);
    }

    return values;
}

/// Parse a single JSON value to AbiEncodedValue based on parameter type
fn parseJsonToAbiValue(
    allocator: std.mem.Allocator,
    param_type: []const u8,
    value: std.json.Value,
) !encoder.AbiEncodedValues {
    // Handle basic types
    if (std.mem.eql(u8, param_type, "address")) {
        const addr_str = switch (value) {
            .string => |s| s,
            else => return error.InvalidArgumentType,
        };
        const addr = try evm_helpers.parseAddress(addr_str);
        return encoder.AbiEncodedValues{ .address = addr };
    } else if (std.mem.startsWith(u8, param_type, "uint")) {
        const num = switch (value) {
            .integer => |n| @as(u256, @intCast(n)),
            .number_string => |s| blk: {
                const parsed = try std.fmt.parseInt(u256, s, 10);
                break :blk parsed;
            },
            else => return error.InvalidArgumentType,
        };
        return encoder.AbiEncodedValues{ .uint = num };
    } else if (std.mem.startsWith(u8, param_type, "int")) {
        const num = switch (value) {
            .integer => |n| @as(i256, @intCast(n)),
            .number_string => |s| blk: {
                const parsed = try std.fmt.parseInt(i256, s, 10);
                break :blk parsed;
            },
            else => return error.InvalidArgumentType,
        };
        return encoder.AbiEncodedValues{ .int = num };
    } else if (std.mem.eql(u8, param_type, "bool")) {
        const b = switch (value) {
            .bool => |boolean| boolean,
            else => return error.InvalidArgumentType,
        };
        return encoder.AbiEncodedValues{ .bool = b };
    } else if (std.mem.eql(u8, param_type, "string")) {
        const str = switch (value) {
            .string => |s| s,
            else => return error.InvalidArgumentType,
        };
        const owned = try allocator.dupe(u8, str);
        return encoder.AbiEncodedValues{ .string = owned };
    } else if (std.mem.eql(u8, param_type, "bytes")) {
        const bytes_str = switch (value) {
            .string => |s| s,
            else => return error.InvalidArgumentType,
        };
        // Parse hex string
        const bytes = try parseHexBytes(allocator, bytes_str);
        return encoder.AbiEncodedValues{ .bytes = bytes };
    } else if (std.mem.endsWith(u8, param_type, "[]")) {
        // Dynamic array
        const arr = switch (value) {
            .array => |a| a.items,
            else => return error.InvalidArgumentType,
        };
        // Get element type
        const elem_type = param_type[0 .. param_type.len - 2];
        const elements = try allocator.alloc(encoder.AbiEncodedValues, arr.len);
        for (arr, 0..) |item, i| {
            elements[i] = try parseJsonToAbiValue(allocator, elem_type, item);
        }
        return encoder.AbiEncodedValues{ .dynamic_array = elements };
    }

    // Unsupported type - for now just return error
    // TODO: Support more types (fixed arrays, bytes32, tuples, etc.)
    return error.UnsupportedParameterType;
}

/// Parse hex string to bytes
fn parseHexBytes(allocator: std.mem.Allocator, hex_str: []const u8) ![]u8 {
    const str = if (std.mem.startsWith(u8, hex_str, "0x"))
        hex_str[2..]
    else
        hex_str;

    if (str.len % 2 != 0) return error.InvalidHexString;

    const bytes = try allocator.alloc(u8, str.len / 2);
    errdefer allocator.free(bytes);

    for (0..bytes.len) |i| {
        bytes[i] = try std.fmt.parseInt(u8, str[i * 2 .. i * 2 + 2], 16);
    }

    return bytes;
}
