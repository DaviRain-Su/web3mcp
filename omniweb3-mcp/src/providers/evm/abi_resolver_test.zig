//! Unit tests for ABI resolver

const std = @import("std");
const testing = std.testing;
const abi_resolver = @import("abi_resolver.zig");

test "abi_resolver module loads" {
    _ = abi_resolver;
}

test "load contract metadata" {
    const allocator = testing.allocator;

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

    // Should have at least one contract
    try testing.expect(contracts.len > 0);

    // Check first contract has required fields
    const first = contracts[0];
    try testing.expect(first.chain.len > 0);
    try testing.expect(first.address.len > 0);
    try testing.expect(first.name.len > 0);
}

test "load WBNB ABI" {
    const allocator = testing.allocator;

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

    // WBNB should have deposit and withdraw functions
    try testing.expect(abi.functions.len > 0);

    var has_deposit = false;
    var has_withdraw = false;
    for (abi.functions) |func| {
        if (std.mem.eql(u8, func.name, "deposit")) has_deposit = true;
        if (std.mem.eql(u8, func.name, "withdraw")) has_withdraw = true;
    }

    try testing.expect(has_deposit);
    try testing.expect(has_withdraw);
}

test "load PancakeSwap Router ABI" {
    const allocator = testing.allocator;

    const abi = abi_resolver.loadAbiForTest(
        allocator,
        "abi_registry/bsc/pancakeswap_router_v2.json",
    ) catch |err| {
        std.debug.print("Failed to load PancakeSwap Router ABI: {}\n", .{err});
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

    // Should have swap functions
    try testing.expect(abi.functions.len > 0);

    var has_swap_exact_tokens = false;
    for (abi.functions) |func| {
        if (std.mem.eql(u8, func.name, "swapExactTokensForTokens")) {
            has_swap_exact_tokens = true;
            // Should have 5 inputs (amountIn, amountOutMin, path, to, deadline)
            try testing.expect(func.inputs.len == 5);
        }
    }

    try testing.expect(has_swap_exact_tokens);
}

test "resolve ABI path" {
    const allocator = testing.allocator;

    const path = try abi_resolver.resolveAbiPath(allocator, "bsc", "wbnb");
    defer allocator.free(path);

    try testing.expectEqualStrings("abi_registry/bsc/wbnb.json", path);
}

test "check ABI exists" {
    try testing.expect(abi_resolver.abiExistsForTest("bsc", "wbnb"));
    try testing.expect(!abi_resolver.abiExistsForTest("bsc", "nonexistent"));
}
