//! Unit tests for EVM tool generator

const std = @import("std");
const testing = std.testing;
const tool_generator = @import("tool_generator.zig");
const abi_resolver = @import("abi_resolver.zig");

test "tool_generator module loads" {
    _ = tool_generator;
}

test "generate tools for WBNB" {
    // Skip: requires filesystem access, better as integration test
    return error.SkipZigTest;
}

test "generate tools for PancakeSwap Router" {
    // Skip: requires filesystem access, better as integration test
    return error.SkipZigTest;
}

test "tool description generation" {
    const allocator = testing.allocator;

    // Create a mock function
    const func = abi_resolver.AbiFunction{
        .name = "transfer",
        .inputs = &[_]abi_resolver.AbiParam{
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
        },
        .outputs = &[_]abi_resolver.AbiParam{
            .{
                .name = "",
                .type = "bool",
                .internal_type = null,
                .indexed = false,
            },
        },
        .state_mutability = .nonpayable,
        .function_type = .function,
        .payable = false,
    };

    const tool = try tool_generator.generateToolForFunction(
        allocator,
        "bsc",
        "test_token",
        "Test Token",
        "0x1234567890123456789012345678901234567890",
        func,
    );
    defer {
        allocator.free(tool.name);
        if (tool.description) |desc| allocator.free(desc);
        if (tool.inputSchema) |schema| {
            tool_generator.freeInputSchema(allocator, schema);
        }
    }

    // Verify tool name
    try testing.expectEqualStrings("bsc_test_token_transfer", tool.name);

    // Verify description contains key information
    try testing.expect(tool.description != null);
    const desc = tool.description.?;
    try testing.expect(std.mem.indexOf(u8, desc, "transfer") != null);
    try testing.expect(std.mem.indexOf(u8, desc, "Test Token") != null);
    try testing.expect(std.mem.indexOf(u8, desc, "bsc") != null);
    try testing.expect(std.mem.indexOf(u8, desc, "State-changing") != null);
}
