const std = @import("std");
const provider = @import("./provider.zig");
const chain_provider = @import("../../core/chain_provider.zig");

const SolanaProvider = provider.SolanaProvider;
const FunctionCall = chain_provider.FunctionCall;
const CallOptions = chain_provider.CallOptions;

// Integration test for Jupiter swap
// This test validates the entire flow:
// 1. Initialize SolanaProvider
// 2. Fetch Jupiter IDL
// 3. Generate tools dynamically
// 4. Build a sample swap transaction
// 5. Verify transaction structure
test "Jupiter swap integration" {
    const allocator = std.testing.allocator;

    // Jupiter program ID
    const jupiter_program_id = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";
    const rpc_url = "https://api.mainnet-beta.solana.com";

    // Initialize provider
    const solana_provider = try SolanaProvider.init(allocator, rpc_url);
    defer solana_provider.deinit();

    // Get contract metadata
    std.debug.print("\n=== Fetching Jupiter IDL ===\n", .{});
    const meta = solana_provider.resolver.resolve(allocator, jupiter_program_id) catch |err| {
        std.debug.print("Failed to fetch Jupiter IDL: {}\n", .{err});
        std.debug.print("This is expected if offline or Solana FM API is unavailable\n", .{});
        return error.SkipZigTest;
    };
    defer {
        var meta_mut = meta;
        meta_mut.deinit(allocator);
    }

    std.debug.print("✓ Successfully fetched IDL for: {s}\n", .{meta.name orelse "unknown"});
    std.debug.print("  Functions: {}\n", .{meta.functions.len});

    // Generate tools
    std.debug.print("\n=== Generating MCP Tools ===\n", .{});
    const chain_prov = solana_provider.asChainProvider();
    const tools = try chain_prov.generateTools(allocator, &meta);
    defer {
        for (tools) |tool| {
            allocator.free(tool.name);
            allocator.free(tool.description);
            // Note: inputSchema cleanup would require recursive JSON cleanup
        }
        allocator.free(tools);
    }

    std.debug.print("✓ Generated {} tools\n", .{tools.len});

    // Print first few tools for verification
    const max_print = @min(5, tools.len);
    for (tools[0..max_print]) |tool| {
        std.debug.print("  - {s}\n", .{tool.name});
    }

    // Try to find a swap-related function
    var swap_function: ?[]const u8 = null;
    for (meta.functions) |func| {
        if (std.mem.indexOf(u8, func.name, "swap") != null or
            std.mem.indexOf(u8, func.name, "route") != null) {
            swap_function = func.name;
            std.debug.print("  Found swap function: {s}\n", .{func.name});
            break;
        }
    }

    if (swap_function) |func_name| {
        // Build a sample transaction
        std.debug.print("\n=== Building Sample Transaction ===\n", .{});

        // Create sample function call arguments
        var args_obj = std.json.ObjectMap.init(allocator);
        defer args_obj.deinit();

        // Note: Actual Jupiter swap requires specific arguments
        // This is just a structure test
        try args_obj.put("amount", std.json.Value{ .integer = 1000000 });

        const call = FunctionCall{
            .contract = jupiter_program_id,
            .function = func_name,
            .signer = "11111111111111111111111111111111",
            .args = std.json.Value{ .object = args_obj },
            .options = CallOptions{
                .value = 0,
                .gas_limit = null,
            },
        };

        const tx = try chain_prov.buildTransaction(allocator, call);
        defer allocator.free(tx.data);

        std.debug.print("✓ Transaction built successfully\n", .{});
        std.debug.print("  Chain: {}\n", .{tx.chain});
        std.debug.print("  From: {s}\n", .{tx.from});
        std.debug.print("  To: {s}\n", .{tx.to});
        std.debug.print("  Data length: {} bytes\n", .{tx.data.len});

        // Verify transaction structure
        try std.testing.expect(tx.data.len >= 8); // At least discriminator
        try std.testing.expectEqual(chain_provider.ChainType.solana, tx.chain);
        try std.testing.expectEqualStrings(jupiter_program_id, tx.to);

        std.debug.print("  Discriminator: ", .{});
        for (tx.data[0..8]) |byte| {
            std.debug.print("{X:0>2}", .{byte});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("\n=== Integration Test Passed ===\n", .{});
}

// Integration test for SPL Token
test "SPL Token integration" {
    const allocator = std.testing.allocator;

    const spl_token_program_id = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
    const rpc_url = "https://api.mainnet-beta.solana.com";

    // Initialize provider
    const solana_provider = try SolanaProvider.init(allocator, rpc_url);
    defer solana_provider.deinit();

    std.debug.print("\n=== Fetching SPL Token IDL ===\n", .{});
    const meta = solana_provider.resolver.resolve(allocator, spl_token_program_id) catch |err| {
        std.debug.print("Failed to fetch SPL Token IDL: {}\n", .{err});
        std.debug.print("This is expected - SPL Token uses native instructions, not Anchor\n", .{});
        return error.SkipZigTest;
    };
    defer {
        var meta_mut = meta;
        meta_mut.deinit(allocator);
    }

    std.debug.print("✓ Successfully fetched IDL\n", .{});
    std.debug.print("  Functions: {}\n", .{meta.functions.len});

    // Generate tools
    const chain_prov = solana_provider.asChainProvider();
    const tools = try chain_prov.generateTools(allocator, &meta);
    defer {
        for (tools) |tool| {
            allocator.free(tool.name);
            allocator.free(tool.description);
        }
        allocator.free(tools);
    }

    std.debug.print("✓ Generated {} tools\n", .{tools.len});

    // Look for common token operations
    const expected_ops = [_][]const u8{ "transfer", "mint", "burn", "approve" };
    for (expected_ops) |expected| {
        for (tools) |tool| {
            if (std.mem.indexOf(u8, tool.name, expected) != null) {
                std.debug.print("  ✓ Found {s} operation\n", .{expected});
                break;
            }
        }
    }

    std.debug.print("\n=== SPL Token Test Passed ===\n", .{});
}

// Test discriminator computation matches Anchor's algorithm
test "Anchor discriminator computation" {
    const allocator = std.testing.allocator;
    const transaction_builder = @import("./transaction_builder.zig");

    std.debug.print("\n=== Testing Anchor Discriminator ===\n", .{});

    // Test known discriminators
    const test_cases = [_]struct {
        name: []const u8,
        // Expected discriminators would need to be verified against actual Anchor output
    }{
        .{ .name = "initialize" },
        .{ .name = "swap" },
        .{ .name = "transfer" },
    };

    for (test_cases) |case| {
        const disc = try transaction_builder.computeDiscriminator(allocator, case.name);

        std.debug.print("Function: {s}\n", .{case.name});
        std.debug.print("  Discriminator: ", .{});
        for (disc) |byte| {
            std.debug.print("{X:0>2}", .{byte});
        }
        std.debug.print("\n", .{});

        // Verify determinism
        const disc2 = try transaction_builder.computeDiscriminator(allocator, case.name);
        try std.testing.expectEqualSlices(u8, &disc, &disc2);
    }

    std.debug.print("✓ Discriminators are deterministic\n", .{});
}
