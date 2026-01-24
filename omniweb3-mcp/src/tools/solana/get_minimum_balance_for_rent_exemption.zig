const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");

/// Get minimum balance for rent exemption (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - data_len: Account data length (required)
/// - network: devnet/testnet/mainnet/localhost (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with minimum balance in lamports
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_minimum_balance_for_rent_exemption: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const data_len = mcp.tools.getInteger(args, "data_len") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: data_len") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    if (data_len < 0) {
        return mcp.tools.errorResult(allocator, "data_len must be non-negative") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const min_balance = adapter.getMinimumBalanceForRentExemption(@intCast(data_len)) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get minimum balance: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const sol_amount = @as(f64, @floatFromInt(min_balance)) / 1_000_000_000.0;

    const Response = struct {
        chain: []const u8,
        data_len: u64,
        minimum_balance_lamports: u64,
        minimum_balance_sol: f64,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .data_len = @intCast(data_len),
        .minimum_balance_lamports = min_balance,
        .minimum_balance_sol = sol_amount,
        .network = network,
        .endpoint = adapter.endpoint,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
