//! EVM chain tools registry.
//!
//! Registers tools specific to EVM-compatible chains
//! (Ethereum, BSC, Avalanche, Polygon, Arbitrum, Optimism, Base, etc.)

const mcp = @import("mcp");
const receipt = @import("receipt.zig");
const nonce = @import("nonce.zig");
const gas_price = @import("gas_price.zig");
const estimate_gas = @import("estimate_gas.zig");
const call = @import("call.zig");
const get_chain_id = @import("get_chain_id.zig");
const get_fee_history = @import("get_fee_history.zig");
const get_logs = @import("get_logs.zig");

/// Tool definitions for EVM-specific operations.
pub const tools = [_]mcp.tools.Tool{
    .{
        .name = "get_receipt",
        .description = "Get EVM transaction receipt. Parameters: chain, tx_hash, network (optional), endpoint (optional)",
        .handler = receipt.handle,
    },
    .{
        .name = "get_nonce",
        .description = "Get EVM address nonce. Parameters: chain, address, tag (optional), network (optional), endpoint (optional)",
        .handler = nonce.handle,
    },
    .{
        .name = "get_gas_price",
        .description = "Get EVM gas price. Parameters: chain, network (optional), endpoint (optional)",
        .handler = gas_price.handle,
    },
    .{
        .name = "estimate_gas",
        .description = "Estimate EVM gas. Parameters: chain, to_address, from_address (optional), value (optional), data (optional), network (optional), endpoint (optional)",
        .handler = estimate_gas.handle,
    },
    .{
        .name = "call",
        .description = "EVM eth_call. Parameters: chain, to_address, data, from_address (optional), value (optional), tag (optional), network (optional), endpoint (optional)",
        .handler = call.handle,
    },
    .{
        .name = "get_chain_id",
        .description = "Get EVM chain id. Parameters: chain, network (optional), endpoint (optional)",
        .handler = get_chain_id.handle,
    },
    .{
        .name = "get_fee_history",
        .description = "Get EVM fee history. Parameters: chain, block_count, newest_block (optional), reward_percentiles (optional), network (optional), endpoint (optional)",
        .handler = get_fee_history.handle,
    },
    .{
        .name = "get_logs",
        .description = "Get EVM logs. Parameters: chain, address (optional), from_block (optional), to_block (optional), block_hash (optional), topics (optional), tag (optional), network (optional), endpoint (optional)",
        .handler = get_logs.handle,
    },
};

/// Register all EVM tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    for (tools) |tool| {
        try server.addTool(tool);
    }
}
