//! Batch Get Token Balances Tool
//!
//! Query balances for multiple SPL tokens in a single RPC call.
//!
//! Use case: Portfolio tracking - query all token balances at once
//! instead of making individual calls for each token.

const std = @import("std");
const mcp = @import("mcp");
const batch_rpc = @import("../../core/batch_rpc.zig");

/// Batch get token balances for an owner.
///
/// Parameters:
/// - chain: Must be "solana" (required)
/// - owner: Owner wallet address (required)
/// - mints: Array of token mint addresses (required, max 100)
/// - network: Network - mainnet/devnet/testnet (optional, default: mainnet)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns: JSON array with token balances for each mint
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain = mcp.tools.getString(args, "chain") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: chain") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    if (!std.mem.eql(u8, chain, "solana")) {
        return mcp.tools.errorResult(allocator, "chain must be 'solana'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const owner = mcp.tools.getString(args, "owner") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: owner") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const mints_array_opt = mcp.tools.getArray(args, "mints");
    if (mints_array_opt == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: mints (array)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const mints_json = mints_array_opt.?.items;
    if (mints_json.len == 0) {
        return mcp.tools.errorResult(allocator, "mints array cannot be empty") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (mints_json.len > 100) {
        return mcp.tools.errorResult(allocator, "Maximum 100 mints per batch") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Convert JSON array to string array
    var mints: std.ArrayList([]const u8) = .empty;
    defer mints.deinit(allocator);

    for (mints_json) |mint_val| {
        if (mint_val != .string) {
            return mcp.tools.errorResult(allocator, "All mints must be strings") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        try mints.append(allocator, mint_val.string);
    }

    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint = mcp.tools.getString(args, "endpoint");

    // Call batch RPC
    const response = batch_rpc.batchGetTokenBalances(
        allocator,
        owner,
        mints.items,
        network,
        endpoint,
    ) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Batch RPC failed: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(response);

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
