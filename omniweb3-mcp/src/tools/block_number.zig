const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../core/evm_runtime.zig");
const solana_sdk = @import("solana_sdk");
const chain = @import("../core/chain.zig");

/// Get latest block number/height.
///
/// Parameters:
/// - chain: "solana" | "ethereum" | "avalanche" | "bnb" (optional, default: solana)
/// - network: Solana: devnet/testnet/mainnet/localhost; EVM: mainnet/sepolia/goerli/fuji/testnet
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with block height/number
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    const network_raw = mcp.tools.getString(args, "network");
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const network = network_raw orelse "devnet";
        var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const latest = adapter.getLatestBlockhash() catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get latest blockhash: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        var hash_buf: [solana_sdk.hash.MAX_BASE58_LEN]u8 = undefined;
        const hash_str = latest.blockhash.toBase58(&hash_buf);

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"solana\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"block_height\":{d},\"blockhash\":\"{s}\"}}",
            .{ network, adapter.endpoint, latest.last_valid_block_height, hash_str },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        return mcp.tools.textResult(allocator, response) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    if (std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm")) {
        const network = network_raw orelse "mainnet";
        var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const block_number = adapter.getBlockNumber() catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get block number: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"block_number\":{d}}}",
            .{ chain_name, network, adapter.endpoint, block_number },
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
