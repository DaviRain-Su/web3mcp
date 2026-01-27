//! Unit tests for EVM tool generator

const std = @import("std");
const testing = std.testing;
const tool_generator = @import("tool_generator.zig");
const abi_resolver = @import("abi_resolver.zig");

test "tool_generator module loads" {
    _ = tool_generator;
}

test "generate tools for WBNB" {
    const allocator = testing.allocator;

    // Load WBNB contract metadata
    const contracts = abi_resolver.loadContractMetadataForTest(
        allocator,
        "abi_registry/contracts.json",
    ) catch |err| {
        std.debug.print("Failed to load contracts: {}\n", .{err});
        return err;
    };
    defer {
        for (contracts) |contract| {
            allocator.free(contract.chain);
            allocator.free(contract.address);
            allocator.free(contract.name);
            allocator.free(contract.display_name);
            allocator.free(contract.category);
            allocator.free(contract.description);
        }
        allocator.free(contracts);
    }

    // Find WBNB contract
    var wbnb_contract: ?*const abi_resolver.ContractMetadata = null;
    for (contracts) |*contract| {
        if (std.mem.eql(u8, contract.name, "wbnb")) {
            wbnb_contract = contract;
            break;
        }
    }

    if (wbnb_contract == null) {
        std.debug.print("WBNB contract not found in registry\n", .{});
        return error.ContractNotFound;
    }

    // Load WBNB ABI
    const abi = abi_resolver.loadAbiForTest(
        allocator,
        "abi_registry/bsc/wbnb.json",
    ) catch |err| {
        std.debug.print("Failed to load WBNB ABI: {}\n", .{err});
        return err;
    };
    defer {
        for (abi.functions) |func| {
            allocator.free(func.name);
            for (func.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(func.inputs);
            for (func.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(func.outputs);
        }
        allocator.free(abi.functions);
        // Clean up events
        for (abi.events) |event| {
            allocator.free(event.name);
            for (event.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(event.inputs);
        }
        allocator.free(abi.events);
        // Clean up constructor, fallback, receive
        if (abi.constructor) |cons| {
            allocator.free(cons.name);
            for (cons.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(cons.inputs);
            for (cons.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(cons.outputs);
        }
        if (abi.fallback) |fb| {
            allocator.free(fb.name);
            for (fb.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(fb.inputs);
            for (fb.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(fb.outputs);
        }
        if (abi.receive) |recv| {
            allocator.free(recv.name);
            for (recv.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(recv.inputs);
            for (recv.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(recv.outputs);
        }
    }

    // Generate tools
    const tools = try tool_generator.generateTools(allocator, wbnb_contract.?, &abi);
    defer {
        for (tools) |tool| {
            allocator.free(tool.name);
            if (tool.description) |desc| allocator.free(desc);
            // Clean up input schema
            if (tool.inputSchema) |schema| {
                tool_generator.freeInputSchema(allocator, schema);
            }
        }
        allocator.free(tools);
    }

    // Should have multiple tools (deposit, withdraw, transfer, etc.)
    try testing.expect(tools.len > 0);

    // Check tool naming convention
    for (tools) |tool| {
        // Tool name should start with "bsc_wbnb_"
        try testing.expect(std.mem.startsWith(u8, tool.name, "bsc_wbnb_"));
    }

    // Verify specific tools exist
    var has_deposit = false;
    var has_withdraw = false;
    for (tools) |tool| {
        if (std.mem.eql(u8, tool.name, "bsc_wbnb_deposit")) has_deposit = true;
        if (std.mem.eql(u8, tool.name, "bsc_wbnb_withdraw")) has_withdraw = true;
    }

    try testing.expect(has_deposit);
    try testing.expect(has_withdraw);
}

test "generate tools for PancakeSwap Router" {
    const allocator = testing.allocator;

    // Load contract metadata
    const contracts = abi_resolver.loadContractMetadataForTest(
        allocator,
        "abi_registry/contracts.json",
    ) catch |err| {
        std.debug.print("Failed to load contracts: {}\n", .{err});
        return err;
    };
    defer {
        for (contracts) |contract| {
            allocator.free(contract.chain);
            allocator.free(contract.address);
            allocator.free(contract.name);
            allocator.free(contract.display_name);
            allocator.free(contract.category);
            allocator.free(contract.description);
        }
        allocator.free(contracts);
    }

    // Find PancakeSwap Router
    var router_contract: ?*const abi_resolver.ContractMetadata = null;
    for (contracts) |*contract| {
        if (std.mem.eql(u8, contract.name, "pancakeswap_router_v2")) {
            router_contract = contract;
            break;
        }
    }

    if (router_contract == null) {
        std.debug.print("PancakeSwap Router not found in registry\n", .{});
        return error.ContractNotFound;
    }

    // Load ABI
    const abi = abi_resolver.loadAbiForTest(
        allocator,
        "abi_registry/bsc/pancakeswap_router_v2.json",
    ) catch |err| {
        std.debug.print("Failed to load Router ABI: {}\n", .{err});
        return err;
    };
    defer {
        for (abi.functions) |func| {
            allocator.free(func.name);
            for (func.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(func.inputs);
            for (func.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(func.outputs);
        }
        allocator.free(abi.functions);
        // Clean up events
        for (abi.events) |event| {
            allocator.free(event.name);
            for (event.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(event.inputs);
        }
        allocator.free(abi.events);
        // Clean up constructor, fallback, receive
        if (abi.constructor) |cons| {
            allocator.free(cons.name);
            for (cons.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(cons.inputs);
            for (cons.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(cons.outputs);
        }
        if (abi.fallback) |fb| {
            allocator.free(fb.name);
            for (fb.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(fb.inputs);
            for (fb.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(fb.outputs);
        }
        if (abi.receive) |recv| {
            allocator.free(recv.name);
            for (recv.inputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(recv.inputs);
            for (recv.outputs) |param| {
                allocator.free(param.name);
                allocator.free(param.type);
                if (param.internal_type) |it| allocator.free(it);
            }
            allocator.free(recv.outputs);
        }
    }

    // Generate tools
    const tools = try tool_generator.generateTools(allocator, router_contract.?, &abi);
    defer {
        for (tools) |tool| {
            allocator.free(tool.name);
            if (tool.description) |desc| allocator.free(desc);
            // Clean up input schema
            if (tool.inputSchema) |schema| {
                tool_generator.freeInputSchema(allocator, schema);
            }
        }
        allocator.free(tools);
    }

    // Should have many tools (swap, liquidity, etc.)
    try testing.expect(tools.len > 10);

    // Check for key swap function
    var has_swap_exact_tokens = false;
    for (tools) |tool| {
        if (std.mem.eql(u8, tool.name, "bsc_pancakeswap_router_v2_swapExactTokensForTokens")) {
            has_swap_exact_tokens = true;

            // Verify it has input schema with parameters
            try testing.expect(tool.inputSchema != null);
            const schema = tool.inputSchema.?;
            try testing.expect(schema.properties != null);
            const properties = schema.properties.?.object;

            // Should have 5 parameters
            try testing.expectEqual(@as(usize, 5), properties.count());
        }
    }

    try testing.expect(has_swap_exact_tokens);
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
