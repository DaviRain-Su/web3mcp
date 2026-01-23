const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");

const RpcClient = solana_client.RpcClient;
const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.mem.eql(u8, chain, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}. Only 'solana' is supported.", .{chain}) catch {
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

    const token_account = solana_helpers.parsePublicKey(token_account_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid token account address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint = solana_helpers.resolveEndpoint(network);
    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    const balance = client.getTokenAccountBalance(token_account) catch |err| {
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
