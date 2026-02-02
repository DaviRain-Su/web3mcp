//! EVM Tool Generator
//!
//! Converts EVM contract ABIs into MCP tool definitions.
//! Similar to Solana IDL tool generator but for Ethereum/BSC contracts.

const std = @import("std");
const mcp = @import("mcp");
const abi_resolver = @import("abi_resolver.zig");

const Abi = abi_resolver.Abi;
const AbiFunction = abi_resolver.AbiFunction;
const AbiParam = abi_resolver.AbiParam;
const ContractMetadata = abi_resolver.ContractMetadata;

/// Free InputSchema and all allocated resources
pub fn freeInputSchema(allocator: std.mem.Allocator, schema: mcp.types.InputSchema) void {
    // Free properties HashMap and its contents
    if (schema.properties) |props| {
        if (props == .object) {
            var obj = props.object;

            // First pass: collect allocated keys and clean up values
            var keys_buf: [64][]const u8 = undefined;
            var keys_count: usize = 0;

            var iter = obj.iterator();
            while (iter.next()) |entry| {
                // Collect allocated parameter names BEFORE freeing values
                if (std.mem.startsWith(u8, entry.key_ptr.*, "param_")) {
                    if (keys_count < keys_buf.len) {
                        keys_buf[keys_count] = entry.key_ptr.*;
                        keys_count += 1;
                    }
                }

                // Recursively clean up value (pass pointer to avoid copying)
                freeJsonValue(allocator, entry.value_ptr);
            }

            // Free HashMap internal storage
            obj.deinit();

            // Free allocated keys
            for (keys_buf[0..keys_count]) |key| {
                allocator.free(key);
            }
        }
    }

    // Free required array (after freeing keys since it references them)
    if (schema.required) |req| {
        allocator.free(req);
    }
}

/// Recursively free JSON Value
fn freeJsonValue(allocator: std.mem.Allocator, value: *std.json.Value) void {
    switch (value.*) {
        .object => |*obj| {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                freeJsonValue(allocator, entry.value_ptr);
            }
            obj.deinit();
        },
        .array => |*arr| {
            for (arr.items) |*item| {
                freeJsonValue(allocator, item);
            }
            arr.deinit();
        },
        else => {},
    }
}

/// Generate MCP tools from contract metadata and ABI
pub fn generateTools(
    allocator: std.mem.Allocator,
    contract: *const ContractMetadata,
    abi: *const Abi,
) ![]mcp.tools.Tool {
    var tools: std.ArrayList(mcp.tools.Tool) = .empty;
    errdefer tools.deinit(allocator);

    // Generate one tool for each function
    for (abi.functions) |func| {
        // Skip constructor, fallback, and receive functions
        if (func.function_type != .function) continue;

        const tool = try generateToolForFunction(
            allocator,
            contract.chain,
            contract.name,
            contract.display_name,
            contract.address,
            func,
        );
        try tools.append(allocator, tool);
    }

    return tools.toOwnedSlice(allocator);
}

/// Generate a single MCP tool for an ABI function
pub fn generateToolForFunction(
    allocator: std.mem.Allocator,
    chain: []const u8,
    contract_name: []const u8,
    display_name: []const u8,
    contract_address: []const u8,
    func: AbiFunction,
) !mcp.tools.Tool {
    // Tool name: {chain}_{contract}_{function} (e.g., "bsc_wbnb_deposit")
    // MCP requires tool names to be at most 64 characters
    const full_name = try std.fmt.allocPrint(
        allocator,
        "{s}_{s}_{s}",
        .{ chain, contract_name, func.name },
    );
    defer allocator.free(full_name);

    const tool_name = if (full_name.len <= 64)
        try allocator.dupe(u8, full_name)
    else blk: {
        // If too long, truncate and add hash for uniqueness
        // Format: {chain}_{contract_short}_{func_short}_{hash}
        // Reserve 9 chars for hash (_12345678), leaving 55 for content
        const hash = std.hash.Wyhash.hash(0, full_name);
        const hash_str = try std.fmt.allocPrint(allocator, "{x:0>8}", .{@as(u32, @truncate(hash))});
        defer allocator.free(hash_str);

        // Calculate available space for each component
        const max_base_len = 64 - 9; // 55 chars for base, 9 for _hash
        const chain_len = chain.len;
        const contract_len = contract_name.len;
        const func_len = func.name.len;

        // Try to keep full function name, truncate contract if needed
        const func_max = @min(func_len, 30); // Keep function name under 30 chars
        const contract_max = if (max_base_len - chain_len - func_max - 2 > 0)
            @min(contract_len, max_base_len - chain_len - func_max - 2)
        else
            8; // Minimum contract name length

        break :blk try std.fmt.allocPrint(
            allocator,
            "{s}_{s}_{s}_{s}",
            .{
                chain,
                contract_name[0..contract_max],
                func.name[0..func_max],
                hash_str,
            },
        );
    };

    // Generate description
    const state_mutability_desc = switch (func.state_mutability) {
        .view => "Read-only function",
        .pure => "Pure function (no state access)",
        .nonpayable => "State-changing function",
        .payable => "Payable function (can receive native tokens)",
    };

    const description = try std.fmt.allocPrint(
        allocator,
        \\Call {s} on {s} ({s})
        \\
        \\Contract: {s}
        \\Chain: {s}
        \\Type: {s}
        \\Inputs: {d}
        \\Outputs: {d}
    ,
        .{
            func.name,
            display_name,
            contract_address,
            contract_name,
            chain,
            state_mutability_desc,
            func.inputs.len,
            func.outputs.len,
        },
    );

    // Generate input schema from function parameters
    const input_schema = try generateInputSchema(allocator, func.inputs, func.payable);

    // Create tool with generic handler
    return mcp.tools.Tool{
        .name = tool_name,
        .description = description,
        .inputSchema = input_schema,
        .handler = genericEvmHandler,
    };
}

/// Generate JSON Schema for function inputs
fn generateInputSchema(
    allocator: std.mem.Allocator,
    parameters: []const AbiParam,
    is_payable: bool,
) !mcp.types.InputSchema {
    var properties = std.json.ObjectMap.init(allocator);
    var required_list: std.ArrayList([]const u8) = .empty;

    // Add function parameters to schema
    for (parameters, 0..) |param, i| {
        const param_name = if (param.name.len > 0) param.name else try std.fmt.allocPrint(allocator, "param_{d}", .{i});
        const param_schema = try abiTypeToJsonSchema(allocator, param.type);
        try properties.put(param_name, param_schema);
        try required_list.append(allocator, param_name);
    }

    // Add 'value' parameter for payable functions
    if (is_payable) {
        var value_schema = std.json.ObjectMap.init(allocator);
        try value_schema.put("type", std.json.Value{ .string = "string" });
        try value_schema.put("description", std.json.Value{
            .string = "Amount of native token to send (in wei, as string)",
        });
        try properties.put("value", std.json.Value{ .object = value_schema });
        // value is optional - don't add to required list
    }

    std.log.info("Generated schema for {} parameters{s}", .{
        parameters.len,
        if (is_payable) " (+ value for payable)" else "",
    });

    // Build InputSchema struct
    const schema = mcp.types.InputSchema{
        .type = "object",
        .properties = if (properties.count() > 0) std.json.Value{ .object = properties } else null,
        .required = if (required_list.items.len > 0)
            try required_list.toOwnedSlice(allocator)
        else
            null,
        .description = null,
    };

    return schema;
}

/// Convert Solidity ABI type to JSON Schema
fn abiTypeToJsonSchema(allocator: std.mem.Allocator, abi_type: []const u8) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    // Handle array types (e.g., "uint256[]", "address[]")
    if (std.mem.endsWith(u8, abi_type, "[]")) {
        const base_type = abi_type[0 .. abi_type.len - 2];
        try schema.put("type", std.json.Value{ .string = "array" });
        try schema.put("items", try abiTypeToJsonSchema(allocator, base_type));
        return std.json.Value{ .object = schema };
    }

    // Handle fixed-size arrays (e.g., "uint256[10]")
    if (std.mem.indexOfScalar(u8, abi_type, '[')) |bracket_idx| {
        const base_type = abi_type[0..bracket_idx];
        // Extract array size
        const size_str = abi_type[bracket_idx + 1 .. abi_type.len - 1];
        const array_size = try std.fmt.parseInt(usize, size_str, 10);

        try schema.put("type", std.json.Value{ .string = "array" });
        try schema.put("items", try abiTypeToJsonSchema(allocator, base_type));
        try schema.put("minItems", std.json.Value{ .integer = @intCast(array_size) });
        try schema.put("maxItems", std.json.Value{ .integer = @intCast(array_size) });
        return std.json.Value{ .object = schema };
    }

    // Handle tuple types (represented as structs in ABI)
    if (std.mem.startsWith(u8, abi_type, "tuple")) {
        try schema.put("type", std.json.Value{ .string = "object" });
        try schema.put("description", std.json.Value{
            .string = "Tuple/struct parameter - provide as JSON object",
        });
        return std.json.Value{ .object = schema };
    }

    // Primitive types
    const json_type = mapSolidityTypeToJson(abi_type);
    try schema.put("type", std.json.Value{ .string = json_type });

    // Add descriptions and formats for specific types
    if (std.mem.eql(u8, abi_type, "address")) {
        try schema.put("description", std.json.Value{
            .string = "Ethereum address (0x-prefixed hex, 42 characters)",
        });
        try schema.put("pattern", std.json.Value{
            .string = "^0x[a-fA-F0-9]{40}$",
        });
    } else if (std.mem.startsWith(u8, abi_type, "uint") or std.mem.startsWith(u8, abi_type, "int")) {
        try schema.put("description", std.json.Value{
            .string = "Integer value (as string for large numbers like uint256)",
        });
    } else if (std.mem.startsWith(u8, abi_type, "bytes")) {
        if (!std.mem.eql(u8, abi_type, "bytes")) {
            // Fixed-size bytes (bytes1, bytes32, etc.)
            try schema.put("description", std.json.Value{
                .string = "Fixed-size byte array (0x-prefixed hex)",
            });
        } else {
            // Dynamic bytes
            try schema.put("description", std.json.Value{
                .string = "Dynamic byte array (0x-prefixed hex)",
            });
        }
        try schema.put("pattern", std.json.Value{
            .string = "^0x[a-fA-F0-9]*$",
        });
    } else if (std.mem.eql(u8, abi_type, "bool")) {
        try schema.put("description", std.json.Value{
            .string = "Boolean value (true/false)",
        });
    } else if (std.mem.eql(u8, abi_type, "string")) {
        try schema.put("description", std.json.Value{
            .string = "String value",
        });
    }

    return std.json.Value{ .object = schema };
}

/// Map Solidity type to JSON Schema type
fn mapSolidityTypeToJson(solidity_type: []const u8) []const u8 {
    // Integer types (uint8, uint256, int256, etc.) -> string
    // We use string for large integers to avoid precision loss
    if (std.mem.startsWith(u8, solidity_type, "uint") or
        std.mem.startsWith(u8, solidity_type, "int"))
    {
        return "string";
    }

    // Address -> string
    if (std.mem.eql(u8, solidity_type, "address")) {
        return "string";
    }

    // Bytes types -> string (hex encoded)
    if (std.mem.startsWith(u8, solidity_type, "bytes")) {
        return "string";
    }

    // Bool -> boolean
    if (std.mem.eql(u8, solidity_type, "bool")) {
        return "boolean";
    }

    // String -> string
    if (std.mem.eql(u8, solidity_type, "string")) {
        return "string";
    }

    // Default to string
    return "string";
}

/// Generic EVM handler (placeholder)
/// This will be replaced with a real handler in the dynamic registry
fn genericEvmHandler(
    allocator: std.mem.Allocator,
    args: ?std.json.Value,
) !mcp.tools.ToolResult {
    _ = allocator;
    _ = args;

    // TODO: Implement actual handler that:
    // 1. Extracts contract address and function name from context
    // 2. Encodes function call using ABI
    // 3. Builds transaction
    // 4. Returns unsigned transaction or call result

    return mcp.tools.ToolResult{
        .content = &[_]mcp.types.ContentItem{
            .{ .text = .{
                .text = "EVM tool generation successful (handler not yet implemented)",
            } },
        },
    };
}

// Tests
const testing = std.testing;

test "tool_generator module loads" {
    _ = generateTools;
}

test "mapSolidityTypeToJson" {
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("uint256"));
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("uint8"));
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("int256"));
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("address"));
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("bytes32"));
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("bytes"));
    try testing.expectEqualStrings("boolean", mapSolidityTypeToJson("bool"));
    try testing.expectEqualStrings("string", mapSolidityTypeToJson("string"));
}

test "abiTypeToJsonSchema for simple types" {
    const allocator = testing.allocator;

    // Test uint256
    {
        const schema = try abiTypeToJsonSchema(allocator, "uint256");
        defer {
            var obj = schema.object;
            obj.deinit();
        }

        try testing.expect(schema == .object);
        const type_val = schema.object.get("type").?;
        try testing.expectEqualStrings("string", type_val.string);
        try testing.expect(schema.object.get("description") != null);
    }

    // Test address
    {
        const schema = try abiTypeToJsonSchema(allocator, "address");
        defer {
            var obj = schema.object;
            obj.deinit();
        }

        try testing.expect(schema == .object);
        const type_val = schema.object.get("type").?;
        try testing.expectEqualStrings("string", type_val.string);
        try testing.expect(schema.object.get("pattern") != null);
    }

    // Test bool
    {
        const schema = try abiTypeToJsonSchema(allocator, "bool");
        defer {
            var obj = schema.object;
            obj.deinit();
        }

        try testing.expect(schema == .object);
        const type_val = schema.object.get("type").?;
        try testing.expectEqualStrings("boolean", type_val.string);
    }
}

test "abiTypeToJsonSchema for array types" {
    const allocator = testing.allocator;

    // Test dynamic array (address[])
    {
        const schema = try abiTypeToJsonSchema(allocator, "address[]");
        defer {
            var obj = schema.object;
            // Clean up items
            if (obj.get("items")) |items| {
                if (items == .object) {
                    var items_obj = items.object;
                    items_obj.deinit();
                }
            }
            obj.deinit();
        }

        try testing.expect(schema == .object);
        const type_val = schema.object.get("type").?;
        try testing.expectEqualStrings("array", type_val.string);
        try testing.expect(schema.object.get("items") != null);
    }

    // Test fixed-size array (uint256[10])
    {
        const schema = try abiTypeToJsonSchema(allocator, "uint256[10]");
        defer {
            var obj = schema.object;
            // Clean up items
            if (obj.get("items")) |items| {
                if (items == .object) {
                    var items_obj = items.object;
                    items_obj.deinit();
                }
            }
            obj.deinit();
        }

        try testing.expect(schema == .object);
        const type_val = schema.object.get("type").?;
        try testing.expectEqualStrings("array", type_val.string);

        const min_items = schema.object.get("minItems").?;
        try testing.expectEqual(@as(i64, 10), min_items.integer);

        const max_items = schema.object.get("maxItems").?;
        try testing.expectEqual(@as(i64, 10), max_items.integer);
    }
}

test "generateInputSchema for WBNB deposit" {
    const allocator = testing.allocator;

    // WBNB deposit() has no parameters but is payable
    const params = [_]AbiParam{};
    const schema = try generateInputSchema(allocator, &params, true);

    defer {
        if (schema.properties) |props| {
            if (props == .object) {
                var obj = props.object;
                // Clean up nested objects
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .object) {
                        var nested = entry.value_ptr.*.object;
                        nested.deinit();
                    }
                }
                obj.deinit();
            }
        }
        if (schema.required) |req| {
            allocator.free(req);
        }
    }

    // Should have 'value' parameter for payable
    try testing.expect(schema.properties != null);
    const properties = schema.properties.?.object;
    try testing.expect(properties.contains("value"));
}

test "generateInputSchema for token transfer" {
    const allocator = testing.allocator;

    // transfer(address to, uint256 amount)
    const params = [_]AbiParam{
        .{
            .name = "to",
            .type = "address",
            .internal_type = null,
            .indexed = false,
        },
        .{
            .name = "amount",
            .type = "uint256",
            .internal_type = null,
            .indexed = false,
        },
    };

    const schema = try generateInputSchema(allocator, &params, false);

    defer {
        if (schema.properties) |props| {
            if (props == .object) {
                var obj = props.object;
                // Clean up nested objects
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .object) {
                        var nested = entry.value_ptr.*.object;
                        nested.deinit();
                    }
                }
                obj.deinit();
            }
        }
        if (schema.required) |req| {
            allocator.free(req);
        }
    }

    try testing.expectEqualStrings("object", schema.type);
    try testing.expect(schema.properties != null);
    try testing.expect(schema.required != null);

    const properties = schema.properties.?.object;
    try testing.expect(properties.contains("to"));
    try testing.expect(properties.contains("amount"));

    const required = schema.required.?;
    try testing.expectEqual(@as(usize, 2), required.len);
}
