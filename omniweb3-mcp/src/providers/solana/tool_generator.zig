const std = @import("std");
const mcp = @import("../../mcp.zig");
const chain_provider = @import("../../core/chain_provider.zig");
const ContractMeta = chain_provider.ContractMeta;

/// Generate MCP tools from contract metadata
pub fn generateTools(
    allocator: std.mem.Allocator,
    meta: *const ContractMeta,
) ![]mcp.tools.Tool {
    _ = allocator;
    _ = meta;

    // TODO: Implement tool generation from IDL
    return error.NotImplemented;
}
