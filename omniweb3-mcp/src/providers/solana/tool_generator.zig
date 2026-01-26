const std = @import("std");
const mcp = @import("../../mcp.zig");
const chain_provider = @import("../../core/chain_provider.zig");

const ContractMeta = chain_provider.ContractMeta;
const Function = chain_provider.Function;
const Parameter = chain_provider.Parameter;
const Type = chain_provider.Type;
const PrimitiveType = chain_provider.PrimitiveType;

/// Generate MCP tools from contract metadata
pub fn generateTools(
    allocator: std.mem.Allocator,
    meta: *const ContractMeta,
) ![]mcp.tools.Tool {
    var tools: std.ArrayList(mcp.tools.Tool) = .empty;
    errdefer tools.deinit(allocator);

    const program_name = meta.name orelse "program";

    // Generate one tool for each function
    for (meta.functions) |func| {
        const tool = try generateToolForFunction(allocator, program_name, meta.address, func);
        try tools.append(allocator, tool);
    }

    return tools.toOwnedSlice(allocator);
}

/// Generate a single MCP tool for a function
fn generateToolForFunction(
    allocator: std.mem.Allocator,
    program_name: []const u8,
    program_address: []const u8,
    func: Function,
) !mcp.tools.Tool {
    // Tool name: programName_functionName (e.g., "jupiter_swap")
    const tool_name = try std.fmt.allocPrint(
        allocator,
        "{s}_{s}",
        .{ program_name, func.name },
    );

    // Description from function docs or auto-generate
    const description = if (func.description) |desc|
        try std.fmt.allocPrint(
            allocator,
            "{s}\n\nProgram: {s}\nFunction: {s}",
            .{ desc, program_address, func.name },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "Call {s} instruction on program {s}",
            .{ func.name, program_address },
        );

    // Generate input schema from function parameters
    const input_schema = try generateInputSchema(allocator, func.inputs);

    // Create tool with generic handler
    // Note: The handler is a placeholder that would need to be properly implemented
    // to call the transaction builder with the right context
    return mcp.tools.Tool{
        .name = tool_name,
        .description = description,
        .inputSchema = input_schema,
        .handler = genericInstructionHandler,
    };
}

/// Generate JSON Schema for function inputs
fn generateInputSchema(
    allocator: std.mem.Allocator,
    parameters: []const Parameter,
) !std.json.Value {
    var properties = std.json.ObjectMap.init(allocator);
    var required: std.ArrayList(std.json.Value) = .empty;

    // Add parameters to schema
    for (parameters) |param| {
        const param_schema = try typeToJsonSchema(allocator, param.type);
        try properties.put(param.name, param_schema);

        // Add to required list if not optional
        if (!param.optional) {
            try required.append(allocator, std.json.Value{ .string = param.name });
        }
    }

    // Build schema object
    var schema = std.json.ObjectMap.init(allocator);
    try schema.put("type", std.json.Value{ .string = "object" });
    try schema.put("properties", std.json.Value{ .object = properties });

    if (required.items.len > 0) {
        try schema.put("required", std.json.Value{ .array = std.json.Array.fromOwnedSlice(allocator, try required.toOwnedSlice(allocator)) });
    }

    return std.json.Value{ .object = schema };
}

/// Convert Type to JSON Schema
fn typeToJsonSchema(allocator: std.mem.Allocator, param_type: Type) !std.json.Value {
    switch (param_type) {
        .primitive => |prim| {
            return try primitiveToJsonSchema(allocator, prim);
        },
        .array => |inner_type| {
            var schema = std.json.ObjectMap.init(allocator);
            try schema.put("type", std.json.Value{ .string = "array" });
            try schema.put("items", try typeToJsonSchema(allocator, inner_type.*));
            return std.json.Value{ .object = schema };
        },
        .option => |inner_type| {
            // Optional types allow null
            const inner_schema = try typeToJsonSchema(allocator, inner_type.*);

            // Wrap in anyOf: [inner_schema, null]
            var any_of: std.ArrayList(std.json.Value) = .empty;
            try any_of.append(allocator, inner_schema);

            var null_schema = std.json.ObjectMap.init(allocator);
            try null_schema.put("type", std.json.Value{ .string = "null" });
            try any_of.append(allocator, std.json.Value{ .object = null_schema });

            var schema = std.json.ObjectMap.init(allocator);
            try schema.put("anyOf", std.json.Value{ .array = std.json.Array.fromOwnedSlice(allocator, try any_of.toOwnedSlice(allocator)) });

            return std.json.Value{ .object = schema };
        },
        .struct_type => |fields| {
            var properties = std.json.ObjectMap.init(allocator);
            var required: std.ArrayList(std.json.Value) = .empty;

            for (fields) |field| {
                try properties.put(field.name, try typeToJsonSchema(allocator, field.type));
                try required.append(allocator, std.json.Value{ .string = field.name });
            }

            var schema = std.json.ObjectMap.init(allocator);
            try schema.put("type", std.json.Value{ .string = "object" });
            try schema.put("properties", std.json.Value{ .object = properties });
            if (required.items.len > 0) {
                try schema.put("required", std.json.Value{ .array = std.json.Array.fromOwnedSlice(allocator, try required.toOwnedSlice(allocator)) });
            }

            return std.json.Value{ .object = schema };
        },
        .custom => |type_name| {
            // For custom types, reference by name
            var schema = std.json.ObjectMap.init(allocator);
            try schema.put("type", std.json.Value{ .string = "object" });
            try schema.put("description", std.json.Value{ .string = try std.fmt.allocPrint(allocator, "Custom type: {s}", .{type_name}) });
            return std.json.Value{ .object = schema };
        },
    }
}

/// Convert primitive type to JSON Schema
fn primitiveToJsonSchema(allocator: std.mem.Allocator, prim: PrimitiveType) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    const json_type: []const u8 = switch (prim) {
        .u8, .u16, .u32, .u64, .u128, .u256, .i8, .i16, .i32, .i64, .i128 => "integer",
        .bool => "boolean",
        .string => "string",
        .bytes => "string", // base64 or hex encoded
        .pubkey => "string", // base58 encoded
        .address => "string", // hex encoded
    };

    try schema.put("type", std.json.Value{ .string = json_type });

    // Add format hints for special types
    switch (prim) {
        .pubkey => {
            try schema.put("description", std.json.Value{ .string = "Solana public key (base58)" });
        },
        .address => {
            try schema.put("description", std.json.Value{ .string = "Ethereum address (hex)" });
        },
        .bytes => {
            try schema.put("description", std.json.Value{ .string = "Byte array (base64 or hex)" });
        },
        .u64, .u128, .u256, .i64, .i128 => {
            try schema.put("format", std.json.Value{ .string = "int64" });
        },
        else => {},
    }

    return std.json.Value{ .object = schema };
}

/// Generic instruction handler
/// This is a placeholder that would be called with the proper context
/// In a real implementation, this would extract the program_id and function_name
/// from the tool metadata and call the transaction builder
fn genericInstructionHandler(
    allocator: std.mem.Allocator,
    args: ?std.json.Value,
) !mcp.tools.ToolResult {
    _ = allocator;
    _ = args;

    // TODO: Implement actual handler that:
    // 1. Extracts program_id and function_name from context
    // 2. Gets ContractMeta from provider
    // 3. Calls transaction builder
    // 4. Returns unsigned transaction

    return mcp.tools.ToolResult{
        .content = &[_]mcp.tools.Content{
            .{
                .type = "text",
                .text = "Tool generation successful (handler not yet implemented)",
            },
        },
    };
}

// Tests
test "generateInputSchema for simple function" {
    const allocator = std.testing.allocator;

    const params = [_]Parameter{
        .{
            .name = "amount",
            .type = Type{ .primitive = .u64 },
            .optional = false,
        },
        .{
            .name = "recipient",
            .type = Type{ .primitive = .pubkey },
            .optional = false,
        },
    };

    const schema = try generateInputSchema(allocator, &params);
    defer schema.object.deinit(allocator);

    // Verify schema structure
    try std.testing.expect(schema.object.get("type") != null);
    try std.testing.expect(schema.object.get("properties") != null);
    try std.testing.expect(schema.object.get("required") != null);

    const properties = schema.object.get("properties").?.object;
    try std.testing.expect(properties.get("amount") != null);
    try std.testing.expect(properties.get("recipient") != null);
}

test "primitiveToJsonSchema" {
    const allocator = std.testing.allocator;

    const u64_schema = try primitiveToJsonSchema(allocator, .u64);
    defer u64_schema.object.deinit(allocator);

    try std.testing.expectEqualStrings("integer", u64_schema.object.get("type").?.string);

    const pubkey_schema = try primitiveToJsonSchema(allocator, .pubkey);
    defer pubkey_schema.object.deinit(allocator);

    try std.testing.expectEqualStrings("string", pubkey_schema.object.get("type").?.string);
    try std.testing.expect(pubkey_schema.object.get("description") != null);
}
