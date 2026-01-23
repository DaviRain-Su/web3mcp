const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");

const RpcClient = solana_client.RpcClient;
const PublicKey = solana_sdk.PublicKey;

/// Lamports per SOL
const LAMPORTS_PER_SOL: u64 = 1_000_000_000;

/// Get balance tool handler
/// Supports Solana (devnet by default) balance queries
///
/// Parameters:
/// - chain: "solana" (required)
/// - address: Base58 encoded address (required)
/// - network: "devnet" | "mainnet" | "testnet" (optional, default: devnet)
///
/// Returns JSON with balance info
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Extract parameters
    const chain = mcp.tools.getString(args, "chain") orelse "solana";
    const address = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network_str = mcp.tools.getString(args, "network") orelse "devnet";

    // Only support Solana for now
    if (!std.mem.eql(u8, chain, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}. Only 'solana' is supported.", .{chain}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    // Get endpoint based on network
    const endpoint: []const u8 = if (std.mem.eql(u8, network_str, "mainnet"))
        "https://api.mainnet-beta.solana.com"
    else if (std.mem.eql(u8, network_str, "testnet"))
        "https://api.testnet.solana.com"
    else if (std.mem.eql(u8, network_str, "localhost"))
        "http://localhost:8899"
    else
        "https://api.devnet.solana.com";

    // Parse public key
    const pubkey = PublicKey.fromBase58(address) catch {
        return mcp.tools.errorResult(allocator, "Invalid Solana address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Create RPC client and query balance
    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    const lamports = client.getBalance(pubkey) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get balance: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // Convert to SOL
    const sol = @as(f64, @floatFromInt(lamports)) / @as(f64, @floatFromInt(LAMPORTS_PER_SOL));

    // Format response
    const response = std.fmt.allocPrint(allocator, "{{\"address\":\"{s}\",\"balance_lamports\":{d},\"balance_sol\":{d:.9},\"network\":\"{s}\"}}", .{ address, lamports, sol, network_str }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
