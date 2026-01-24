//! Privy Sign Transaction Tool
//!
//! Sign a transaction using a Privy wallet (without sending).

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// Sign a transaction with a Privy wallet
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const wallet_id = mcp.tools.getString(args, "wallet_id") orelse {
        return client.errorResult(allocator, "Missing required parameter: wallet_id");
    };

    const transaction = mcp.tools.getString(args, "transaction") orelse {
        return client.errorResult(allocator, "Missing required parameter: transaction");
    };

    const chain_type = mcp.tools.getString(args, "chain_type") orelse {
        return client.errorResult(allocator, "Missing required parameter: chain_type");
    };

    const network = mcp.tools.getString(args, "network") orelse "devnet";

    // Build request body based on chain type
    const body = if (std.mem.eql(u8, chain_type, "solana")) blk: {
        const caip2 = client.SolanaNetwork.fromNetwork(network);
        break :blk std.fmt.allocPrint(
            allocator,
            "{{\"method\":\"signTransaction\",\"caip2\":\"{s}\",\"params\":{{\"transaction\":\"{s}\",\"encoding\":\"base64\"}}}}",
            .{ caip2, transaction },
        );
    } else if (std.mem.eql(u8, chain_type, "ethereum")) blk: {
        const caip2 = if (std.mem.eql(u8, network, "mainnet"))
            client.EvmNetwork.ETHEREUM_MAINNET
        else
            client.EvmNetwork.ETHEREUM_SEPOLIA;
        break :blk std.fmt.allocPrint(
            allocator,
            "{{\"method\":\"eth_signTransaction\",\"caip2\":\"{s}\",\"params\":{{\"transaction\":\"{s}\"}}}}",
            .{ caip2, transaction },
        );
    } else {
        return client.errorResult(allocator, "Unsupported chain_type. Use 'solana' or 'ethereum'.");
    };

    const request_body = body catch return mcp.tools.ToolError.OutOfMemory;
    defer allocator.free(request_body);

    // Build path
    const path = std.fmt.allocPrint(allocator, "/wallets/{s}/rpc", .{wallet_id}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(path);

    // Make API request
    const response = client.privyPost(allocator, path, request_body) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Privy API error: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return client.errorResult(allocator, msg);
    };
    defer allocator.free(response);

    return client.jsonResult(allocator, response);
}
