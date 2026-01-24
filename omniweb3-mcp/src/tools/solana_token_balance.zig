const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.mem.eql(u8, chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}. Only 'solana' is supported.", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const token_account_str = mcp.tools.getString(args, "token_account") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: token_account") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    const token_account = solana_helpers.parsePublicKey(token_account_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid token account address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const balance = adapter.getTokenAccountBalance(token_account) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token balance: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const BalanceResponse = struct {
        token_account: []const u8,
        amount: []const u8,
        decimals: u8,
        ui_amount: ?f64 = null,
        ui_amount_string: ?[]const u8 = null,
        network: []const u8,
    };

    const response_value: BalanceResponse = .{
        .token_account = token_account_str,
        .amount = balance.amount,
        .decimals = balance.decimals,
        .ui_amount = balance.ui_amount,
        .ui_amount_string = balance.ui_amount_string,
        .network = network,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
