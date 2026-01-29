//! Unified (cross-chain) tools registry.
//!
//! Registers tools that work across multiple chains (Solana + EVM).

const std = @import("std");
const mcp = @import("mcp");
const balance = @import("balance.zig");
const transfer = @import("transfer.zig");
const block_number = @import("block_number.zig");
const block = @import("block.zig");
const transaction = @import("transaction.zig");
const token_balance = @import("token_balance.zig");
const sign_and_send = @import("sign_and_send.zig");
const wallet_status = @import("wallet_status.zig");
const call_contract = @import("call_contract.zig");
const call_program = @import("call_program.zig");
const swap = @import("swap.zig");
const describe_contract = @import("describe_contract.zig");

/// Tool definitions for unified/cross-chain operations.
pub const tools = [_]mcp.tools.Tool{
    .{
        .name = "get_balance",
        .description = "Get balance across Solana/EVM. Parameters: chain, address, network (optional), endpoint (optional)",
        .handler = balance.handle,
    },
    .{
        .name = "transfer",
        .description = "Transfer native tokens across Solana/EVM. Parameters: chain, to_address, amount, wallet_type (local/privy), wallet_id (required for privy), network (optional), endpoint (optional), keypair_path (for local Solana), private_key (for local EVM), tx_type (EVM), confirmations (EVM), sponsor (Privy gas sponsorship)",
        .handler = transfer.handle,
    },
    .{
        .name = "get_block_number",
        .description = "Get latest block height/number. Parameters: chain, network (optional), endpoint (optional)",
        .handler = block_number.handle,
    },
    .{
        .name = "get_block",
        .description = "Get block info. Parameters: chain, block_number (evm) or slot (solana), block_hash (evm), tag (evm), include_transactions, network (optional), endpoint (optional)",
        .handler = block.handle,
    },
    .{
        .name = "get_transaction",
        .description = "Get transaction info. Parameters: chain, signature (solana) or tx_hash (evm), network (optional), endpoint (optional)",
        .handler = transaction.handle,
    },
    .{
        .name = "token_balance",
        .description = "Token balance. Parameters: chain, token_account (solana) or owner+mint (solana) or token_address+owner (evm), network (optional), endpoint (optional)",
        .handler = token_balance.handle,
    },
    .{
        .name = "sign_and_send",
        .description = "Sign and send transaction using local or Privy wallet. Parameters: chain (solana/ethereum), transaction (base64), wallet_type (local/privy), wallet_id (for privy), keypair_path (for local), network (optional), sponsor (optional, privy only)",
        .handler = sign_and_send.handle,
    },
    .{
        .name = "wallet_status",
        .description = "Get available wallet configurations. Parameters: chain (optional, filter by solana/ethereum). Shows local and Privy wallet availability.",
        .handler = wallet_status.handle,
    },
    .{
        .name = "call_contract",
        .description = "Call a smart contract function with ABI encoding. Parameters: chain (bsc/ethereum/polygon/avalanche), contract (address or name), function, args (array), from (optional), value (optional wei), send_transaction (optional), network (optional), tx_type (optional), confirmations (optional), include_receipt (optional), private_key (optional), keypair_path (optional). Tip: use describe_contract first to confirm function signature.",
        .handler = call_contract.handle,
    },
    .{
        .name = "call_program",
        .description = "Call a Solana program instruction. Parameters: program, instruction, accounts (array of account objects), data (optional), network (optional)",
        .handler = call_program.handle,
    },
    .{
        .name = "swap",
        .description = "Swap native tokens to ERC20 via DEX router. Parameters: chain (optional), network (optional), amount_in (wei string), amount_out_min (optional), path (array), to, deadline (optional), router (optional), tx_type (optional), confirmations (optional), from (optional), private_key (optional), keypair_path (optional)",
        .handler = swap.handle,
    },
    .{
        .name = "describe_contract",
        .description = "Summarize an EVM contract ABI for tool usage. Parameters: chain, contract (name from contracts.json). Use this before call_contract to avoid argument errors.",
        .handler = describe_contract.handle,
    },
};

/// Register all unified tools with the MCP server.
pub fn registerAll(server: *mcp.Server) !void {
    const allocator = server.allocator;

    for (tools) |tool| {
        var modified_tool = tool;

        // Add MCP Apps UI metadata for tools with UI support
        if (std.mem.eql(u8, tool.name, "call_contract")) {
            modified_tool.inputSchema = try buildCallContractSchema(allocator);
        } else if (std.mem.eql(u8, tool.name, "get_balance")) {
            var ui_obj = std.json.ObjectMap.init(allocator);
            try ui_obj.put("resourceUri", .{ .string = "ui://balance" });

            var meta_obj = std.json.ObjectMap.init(allocator);
            try meta_obj.put("ui", .{ .object = ui_obj });

            modified_tool.metadata = .{ .object = meta_obj };
        } else if (std.mem.eql(u8, tool.name, "swap")) {
            var ui_obj = std.json.ObjectMap.init(allocator);
            try ui_obj.put("resourceUri", .{ .string = "ui://swap" });

            var meta_obj = std.json.ObjectMap.init(allocator);
            try meta_obj.put("ui", .{ .object = ui_obj });

            modified_tool.metadata = .{ .object = meta_obj };
        } else if (std.mem.eql(u8, tool.name, "get_transaction")) {
            var ui_obj = std.json.ObjectMap.init(allocator);
            try ui_obj.put("resourceUri", .{ .string = "ui://transaction" });

            var meta_obj = std.json.ObjectMap.init(allocator);
            try meta_obj.put("ui", .{ .object = ui_obj });

            modified_tool.metadata = .{ .object = meta_obj };
        }

        try server.addTool(modified_tool);
    }
}

fn buildCallContractSchema(allocator: std.mem.Allocator) !mcp.types.InputSchema {
    var props = std.json.ObjectMap.init(allocator);

    try props.put("chain", .{ .object = try schemaString(allocator, "Chain name: bsc/ethereum/polygon/avalanche") });
    try props.put("contract", .{ .object = try schemaString(allocator, "Contract address or name from contracts.json") });
    try props.put("function", .{ .object = try schemaString(allocator, "Function name") });
    try props.put("args", .{ .object = try schemaArray(allocator, "Function arguments in ABI order (array or JSON string)") });
    try props.put("from", .{ .object = try schemaString(allocator, "Optional sender address") });
    try props.put("value", .{ .object = try schemaString(allocator, "Wei amount as string") });
    try props.put("send_transaction", .{ .object = try schemaBoolean(allocator, "If true, sign and send transaction") });
    try props.put("network", .{ .object = try schemaString(allocator, "Network: mainnet or testnet") });
    try props.put("tx_type", .{ .object = try schemaString(allocator, "Transaction type: legacy or eip1559") });
    try props.put("confirmations", .{ .object = try schemaInteger(allocator, "Confirmations to wait for") });
    try props.put("include_receipt", .{ .object = try schemaBoolean(allocator, "Include receipt_status and receipt_block in response") });
    try props.put("private_key", .{ .object = try schemaString(allocator, "Optional private key override") });
    try props.put("keypair_path", .{ .object = try schemaString(allocator, "Optional keypair file path") });

    const required_fields = try allocator.alloc([]const u8, 3);
    required_fields[0] = "chain";
    required_fields[1] = "contract";
    required_fields[2] = "function";

    return .{
        .type = "object",
        .properties = .{ .object = props },
        .required = required_fields,
        .description = "call_contract input parameters",
    };
}

fn schemaString(allocator: std.mem.Allocator, desc: []const u8) !std.json.ObjectMap {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("type", .{ .string = "string" });
    try obj.put("description", .{ .string = desc });
    return obj;
}

fn schemaArray(allocator: std.mem.Allocator, desc: []const u8) !std.json.ObjectMap {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("type", .{ .string = "array" });
    try obj.put("description", .{ .string = desc });
    return obj;
}

fn schemaBoolean(allocator: std.mem.Allocator, desc: []const u8) !std.json.ObjectMap {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("type", .{ .string = "boolean" });
    try obj.put("description", .{ .string = desc });
    return obj;
}

fn schemaInteger(allocator: std.mem.Allocator, desc: []const u8) !std.json.ObjectMap {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("type", .{ .string = "integer" });
    try obj.put("description", .{ .string = desc });
    return obj;
}
