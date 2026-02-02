//! Dynamic Tool Handler
//!
//! Generic handler for dynamically generated tools. Routes MCP tool calls to the
//! appropriate ChainProvider for transaction building.

const std = @import("std");
const mcp = @import("mcp");
const chain_provider = @import("../../core/chain_provider.zig");
const registry_mod = @import("./registry.zig");
const solana_helpers = @import("../../core/solana_helpers.zig");

const ChainProvider = chain_provider.ChainProvider;
const FunctionCall = chain_provider.FunctionCall;
const CallOptions = chain_provider.CallOptions;
const DynamicToolRegistry = registry_mod.DynamicToolRegistry;

/// Handle a dynamic tool call (when tool name is known)
///
/// This function:
/// 1. Looks up the tool metadata
/// 2. Extracts parameters from the MCP request
/// 3. Builds the transaction using ChainProvider
/// 4. Returns the unsigned transaction
pub fn handleDynamicToolWithName(
    allocator: std.mem.Allocator,
    registry: *DynamicToolRegistry,
    tool_name: []const u8,
    args: ?std.json.Value,
) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Find the dynamic tool
    const dyn_tool = registry.findTool(tool_name) orelse {
        const msg = try std.fmt.allocPrint(
            allocator,
            "Dynamic tool not found: {s}",
            .{tool_name},
        );
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    return handleDynamicToolImpl(allocator, registry, dyn_tool, args);
}

/// Handle a dynamic tool call (legacy name)
pub const handleDynamicTool = handleDynamicToolWithName;

/// Implementation of dynamic tool handling
fn handleDynamicToolImpl(
    allocator: std.mem.Allocator,
    registry: *DynamicToolRegistry,
    dyn_tool: *const DynamicToolRegistry.DynamicTool,
    args: ?std.json.Value,
) mcp.tools.ToolError!mcp.tools.ToolResult {

    std.log.info("Handling dynamic tool: {s} (function: {s})", .{
        dyn_tool.tool.name,
        dyn_tool.function_name,
    });

    // Extract signer address (required for all blockchain transactions)
    const signer = mcp.tools.getString(args, "signer") orelse
        mcp.tools.getString(args, "user") orelse
        mcp.tools.getString(args, "wallet") orelse {
        return mcp.tools.errorResult(
            allocator,
            "Missing required parameter: signer (or user/wallet)",
        ) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Extract contract address
    // For Solana: use meta.address
    // For EVM: use contract_address from DynamicTool
    const contract_address = if (dyn_tool.meta) |meta|
        meta.address
    else if (dyn_tool.contract_address) |addr|
        addr
    else
        mcp.tools.getString(args, "contract") orelse {
            return mcp.tools.errorResult(
                allocator,
                "Missing contract address",
            ) catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

    // Build function call
    const call = FunctionCall{
        .contract = contract_address,
        .function = dyn_tool.function_name,
        .signer = signer,
        .args = args orelse std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        .options = .{
            .value = if (mcp.tools.getInteger(args, "value")) |v| @intCast(v) else null,
            .gas = if (mcp.tools.getInteger(args, "gas")) |g| @intCast(g) else null,
        },
    };

    // Get provider and build transaction
    var provider = switch (dyn_tool.chain_type) {
        .solana => blk: {
            if (registry.solana_provider) |sol_provider| {
                break :blk sol_provider.asChainProvider();
            }
            return mcp.tools.errorResult(
                allocator,
                "Solana provider not initialized",
            ) catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        },
        .evm => blk: {
            // Get the specific EVM provider for this chain
            const chain_name = dyn_tool.chain_name orelse {
                std.log.err("EVM tool missing chain_name: {s}", .{dyn_tool.tool.name});
                return mcp.tools.errorResult(
                    allocator,
                    "EVM tool missing chain information",
                ) catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };

            // Lookup provider by chain name
            const provider = registry.evm_providers.get(chain_name) orelse {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "EVM provider not found for chain: {s}",
                    .{chain_name},
                );
                return mcp.tools.errorResult(allocator, msg) catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };

            std.log.debug("Using EVM provider for chain: {s}", .{chain_name});
            break :blk provider.asChainProvider();
        },
        else => {
            const msg = try std.fmt.allocPrint(
                allocator,
                "Unsupported chain type: {}",
                .{dyn_tool.chain_type},
            );
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        },
    };

    // Build transaction
    const tx = (&provider).buildTransaction(allocator, call) catch |err| {
        const msg = try std.fmt.allocPrint(
            allocator,
            "Failed to build transaction: {}",
            .{err},
        );
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(tx.data);

    // Format response
    var response_obj = std.json.ObjectMap.init(allocator);
    errdefer response_obj.deinit();

    try response_obj.put("chain", std.json.Value{ .string = @tagName(tx.chain) });
    if (tx.from) |from| {
        try response_obj.put("from", std.json.Value{ .string = from });
    }
    try response_obj.put("to", std.json.Value{ .string = tx.to });
    if (tx.value) |val| {
        try response_obj.put("value", std.json.Value{ .integer = @intCast(val) });
    }

    // Encode transaction data as base64
    const b64_encoder = std.base64.standard.Encoder;
    const encoded_len = b64_encoder.calcSize(tx.data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);
    _ = b64_encoder.encode(encoded, tx.data);

    try response_obj.put("data", std.json.Value{ .string = encoded });

    // Add metadata
    try response_obj.put("metadata", tx.metadata);

    const response = std.json.Value{ .object = response_obj };
    const response_str = solana_helpers.jsonStringifyAlloc(allocator, response) catch {
        return mcp.tools.errorResult(
            allocator,
            "Failed to serialize transaction response",
        ) catch {
            return mcp.tools.ToolError.ExecutionFailed;
        };
    };

    return mcp.tools.textResult(allocator, response_str);
}

/// Create a tool handler closure for a specific dynamic tool
/// This is used when registering tools with the MCP server
pub fn createToolHandler(
    registry: *const DynamicToolRegistry,
    tool_name: []const u8,
) mcp.tools.ToolHandler {
    // Note: In a real implementation, we'd need to store the registry pointer
    // and tool_name in a way that the handler can access them.
    // For now, this is a placeholder showing the intended pattern.
    _ = registry;
    _ = tool_name;

    return struct {
        pub fn handle(
            allocator: std.mem.Allocator,
            args: ?std.json.Value,
        ) mcp.tools.ToolError!mcp.tools.ToolResult {
            // This would call handleDynamicTool with the captured registry and tool_name
            _ = allocator;
            _ = args;
            return mcp.tools.ToolError.InvalidArguments;
        }
    }.handle;
}
