const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../core/solana_helpers.zig");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");

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
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    const address = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network_str = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const pubkey = solana_helpers.parsePublicKey(address) catch {
            return mcp.tools.errorResult(allocator, "Invalid Solana address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        var adapter = chain.initSolanaAdapter(allocator, network_str, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const lamports = adapter.getBalance(pubkey) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get balance: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const sol = @as(f64, @floatFromInt(lamports)) / @as(f64, @floatFromInt(LAMPORTS_PER_SOL));

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"solana\",\"address\":\"{s}\",\"balance_lamports\":{d},\"balance_sol\":{d:.9},\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
            .{ address, lamports, sol, network_str, adapter.endpoint },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        return mcp.tools.textResult(allocator, response) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    if (std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm")) {
        const evm_address = evm_helpers.parseAddress(address) catch {
            return mcp.tools.errorResult(allocator, "Invalid EVM address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network_str, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const balance = adapter.getBalance(evm_address) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get balance: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const wei_str = evm_helpers.formatU256(allocator, balance) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(wei_str);

        const eth_str = evm_helpers.formatWeiToEthString(allocator, balance) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(eth_str);

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"{s}\",\"address\":\"{s}\",\"balance_wei\":\"{s}\",\"balance_eth\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
            .{ chain_name, address, wei_str, eth_str, network_str, adapter.endpoint },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        return mcp.tools.textResult(allocator, response) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}", .{chain_name}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    return mcp.tools.errorResult(allocator, msg) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
