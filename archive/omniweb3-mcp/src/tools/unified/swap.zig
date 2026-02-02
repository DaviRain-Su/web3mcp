const std = @import("std");
const mcp = @import("mcp");
const call_contract = @import("call_contract.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");

/// Swap native tokens to ERC20 using a DEX router.
///
/// Supported routers by default:
/// - bsc testnet: pancake_testnet
/// - bsc mainnet: pancakeswap_router_v2
/// - ethereum mainnet: uniswap_router_v2
/// - polygon mainnet: quickswap_router
///
/// Parameters:
/// - chain: "bsc" | "ethereum" | "polygon" (optional, default: bsc)
/// - network: "mainnet" | "testnet" (optional, default: mainnet)
/// - amount_in: Amount of native token in wei (string, required)
/// - amount_out_min: Minimum output amount (string, optional, default: "0")
/// - path: Array of token addresses (required)
/// - to: Recipient address (required)
/// - deadline: Unix timestamp (string, optional, default: now + 1200s)
/// - router: Router contract name or address (optional, default based on chain/network)
/// - tx_type: "legacy" | "eip1559" (optional)
/// - confirmations: Number of confirmations to wait for (optional, default: 1)
/// - from: Optional sender address
/// - private_key: Optional EVM private key override
/// - keypair_path: Optional keypair file path
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "bsc";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const amount_in = mcp.tools.getString(args, "amount_in") orelse mcp.tools.getString(args, "value") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount_in (wei string)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount_out_min = mcp.tools.getString(args, "amount_out_min") orelse "0";

    const path_array = mcp.tools.getArray(args, "path") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: path (array of token addresses)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    if (path_array.items.len < 2) {
        return mcp.tools.errorResult(allocator, "path must contain at least two addresses") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const to_address = mcp.tools.getString(args, "to") orelse mcp.tools.getString(args, "recipient") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: to") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const deadline = mcp.tools.getString(args, "deadline") orelse blk: {
        const io = evm_runtime.io();
        const now = std.Io.Clock.now(.real, io) catch {
            return mcp.tools.errorResult(allocator, "Failed to read system time") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        const deadline_value: i64 = now.toSeconds() + 1200;
        break :blk std.fmt.allocPrint(allocator, "{d}", .{deadline_value}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer if (mcp.tools.getString(args, "deadline") == null) allocator.free(deadline);

    const router = mcp.tools.getString(args, "router") orelse resolveDefaultRouter(chain_name, network) orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: router (no default for this chain/network)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const tx_type = mcp.tools.getString(args, "tx_type") orelse defaultTxType(chain_name, network);
    const confirmations = mcp.tools.getInteger(args, "confirmations") orelse 1;
    const from = mcp.tools.getString(args, "from");
    const private_key = mcp.tools.getString(args, "private_key");
    const keypair_path = mcp.tools.getString(args, "keypair_path");

    var args_obj = std.json.ObjectMap.init(allocator);
    try args_obj.put("chain", .{ .string = chain_name });
    try args_obj.put("contract", .{ .string = router });
    try args_obj.put("function", .{ .string = "swapExactETHForTokens" });
    try args_obj.put("value", .{ .string = amount_in });
    try args_obj.put("send_transaction", .{ .bool = true });
    try args_obj.put("network", .{ .string = network });
    try args_obj.put("tx_type", .{ .string = tx_type });
    try args_obj.put("confirmations", .{ .integer = confirmations });

    if (from) |value| {
        try args_obj.put("from", .{ .string = value });
    }
    if (private_key) |value| {
        try args_obj.put("private_key", .{ .string = value });
    }
    if (keypair_path) |value| {
        try args_obj.put("keypair_path", .{ .string = value });
    }

    var path_list = std.json.Array.init(allocator);
    defer path_list.deinit();
    for (path_array.items) |item| {
        if (item != .string) {
            return mcp.tools.errorResult(allocator, "Invalid path entry: expected string address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        try path_list.append(.{ .string = item.string });
    }

    var swap_args = std.json.Array.init(allocator);
    defer swap_args.deinit();
    try swap_args.append(.{ .string = amount_out_min });
    try swap_args.append(.{ .array = path_list });
    try swap_args.append(.{ .string = to_address });
    try swap_args.append(.{ .string = deadline });

    try args_obj.put("args", .{ .array = swap_args });

    const args_value = std.json.Value{ .object = args_obj };
    return call_contract.handle(allocator, args_value);
}

fn resolveDefaultRouter(chain_name: []const u8, network: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(chain_name, "bsc") or std.ascii.eqlIgnoreCase(chain_name, "bnb")) {
        if (std.ascii.eqlIgnoreCase(network, "testnet")) return "pancake_testnet";
        return "pancakeswap_router_v2";
    }
    if (std.ascii.eqlIgnoreCase(chain_name, "ethereum")) return "uniswap_router_v2";
    if (std.ascii.eqlIgnoreCase(chain_name, "polygon")) return "quickswap_router";
    return null;
}

fn defaultTxType(chain_name: []const u8, network: []const u8) []const u8 {
    if ((std.ascii.eqlIgnoreCase(chain_name, "bsc") or std.ascii.eqlIgnoreCase(chain_name, "bnb")) and
        std.ascii.eqlIgnoreCase(network, "testnet"))
    {
        return "legacy";
    }
    return "eip1559";
}
