//! Batch Get Account Info Tool
//!
//! Query multiple Solana accounts in a single RPC call.
//!
//! Performance improvement:
//! - 100 accounts: 100 RPC calls (~50s) → 1 RPC call (~500ms)
//! - 10x-100x faster for bulk queries
//! - Reduced network overhead and RPC node load

const std = @import("std");
const mcp = @import("mcp");
const batch_rpc = @import("../../core/batch_rpc.zig");

/// Batch get account info for multiple addresses.
///
/// Parameters:
/// - chain: Must be "solana" (required)
/// - addresses: Array of base58 public keys (required, max 100)
/// - network: Network - mainnet/devnet/testnet (optional, default: mainnet)
/// - endpoint: Custom RPC endpoint (optional)
///
/// Returns: JSON array with account info for each address
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

    const addresses_array_opt = mcp.tools.getArray(args, "addresses");
    if (addresses_array_opt == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: addresses (array)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const addresses_json = addresses_array_opt.?.items;
    if (addresses_json.len == 0) {
        return mcp.tools.errorResult(allocator, "addresses array cannot be empty") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (addresses_json.len > 100) {
        return mcp.tools.errorResult(allocator, "Maximum 100 addresses per batch") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Convert JSON array to string array
    var addresses: std.ArrayList([]const u8) = .empty;
    defer addresses.deinit(allocator);

    for (addresses_json) |addr_val| {
        if (addr_val != .string) {
            return mcp.tools.errorResult(allocator, "All addresses must be strings") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        try addresses.append(allocator, addr_val.string);
    }

    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint = mcp.tools.getString(args, "endpoint");

    // Call batch RPC
    const response = batch_rpc.batchGetAccountInfo(
        allocator,
        addresses.items,
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
