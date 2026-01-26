//! Dynamic Tool Handler
//!
//! Generic handler for dynamically generated tools. Routes MCP tool calls to the
//! appropriate ChainProvider for transaction building.

const std = @import("std");
const mcp = @import("mcp");
const chain_provider = @import("../../core/chain_provider.zig");
const registry_mod = @import("./registry.zig");

const ChainProvider = chain_provider.ChainProvider;
const FunctionCall = chain_provider.FunctionCall;
const CallOptions = chain_provider.CallOptions;
const DynamicToolRegistry = registry_mod.DynamicToolRegistry;

/// Handle a dynamic tool call
///
/// This function:
/// 1. Looks up the tool metadata
/// 2. Extracts parameters from the MCP request
/// 3. Builds the transaction using ChainProvider
/// 4. Returns the unsigned transaction
pub fn handleDynamicTool(
    allocator: std.mem.Allocator,
    registry: *const DynamicToolRegistry,
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

    std.log.info("Handling dynamic tool: {s} (function: {s})", .{
        tool_name,
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

    // Build function call
    const call = FunctionCall{
        .contract = dyn_tool.meta.address,
        .function = dyn_tool.function_name,
        .signer = signer,
        .args = args orelse std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        .options = .{
            .value = mcp.tools.getInteger(args, "value") orelse 0,
            .gas_limit = if (mcp.tools.getInteger(args, "gas_limit")) |g| @intCast(g) else null,
        },
    };

    // Get provider and build transaction
    const provider = switch (dyn_tool.chain_type) {
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
    const tx = provider.buildTransaction(allocator, call) catch |err| {
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
    errdefer response_obj.deinit(allocator);

    try response_obj.put("chain", std.json.Value{ .string = @tagName(tx.chain) });
    try response_obj.put("from", std.json.Value{ .string = tx.from });
    try response_obj.put("to", std.json.Value{ .string = tx.to });
    try response_obj.put("value", std.json.Value{ .integer = @intCast(tx.value) });

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
    const response_str = try std.json.stringifyAlloc(
        allocator,
        response,
        .{ .whitespace = .indent_2 },
    );

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
