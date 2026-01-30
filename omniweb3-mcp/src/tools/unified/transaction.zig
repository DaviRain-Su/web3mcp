const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../core/solana_helpers.zig");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");

/// Get transaction details (Solana/EVM).
///
/// Parameters:
/// - chain: "solana" | "ethereum" | "avalanche" | "bnb" (optional, default: solana)
/// - signature: Solana transaction signature (required for solana)
/// - tx_hash: EVM transaction hash (required for evm)
/// - network: Solana: devnet/testnet/mainnet/localhost; EVM: mainnet/sepolia/goerli/fuji/testnet
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with transaction info
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    _ = mcp.tools.getBoolean(args, "_ui");

    if (std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const signature_str = mcp.tools.getString(args, "signature") orelse {
            return mcp.tools.errorResult(allocator, "Missing required parameter: signature") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        const network = mcp.tools.getString(args, "network") orelse "mainnet";

        const signature = solana_helpers.parseSignature(signature_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid transaction signature") catch {
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

        const tx_opt = adapter.getTransaction(signature) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get transaction: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        if (tx_opt == null) {
            return mcp.tools.errorResult(allocator, "Transaction not found") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const tx = tx_opt.?;

        const TxResponse = struct {
            chain: []const u8,
            signature: []const u8,
            slot: u64,
            block_time: ?i64 = null,
            fee: ?u64 = null,
            err_type: ?[]const u8 = null,
            err_instruction: ?u8 = null,
            pre_balances: ?[]const u64 = null,
            post_balances: ?[]const u64 = null,
            network: []const u8,
            endpoint: []const u8,
        };

        var response_value: TxResponse = .{
            .chain = "solana",
            .signature = signature_str,
            .slot = tx.slot,
            .block_time = tx.block_time,
            .network = network,
            .endpoint = adapter.endpoint,
        };

        if (tx.meta) |meta| {
            response_value.fee = meta.fee;
            response_value.pre_balances = meta.pre_balances;
            response_value.post_balances = meta.post_balances;
            if (meta.err) |err_info| {
                response_value.err_type = err_info.err_type;
                response_value.err_instruction = err_info.instruction_index;
            }
        }

        const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(json);

        return mcp.tools.textResult(allocator, json) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    if (std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "bsc") or std.ascii.eqlIgnoreCase(chain_name, "polygon") or std.ascii.eqlIgnoreCase(chain_name, "evm")) {
        const network = mcp.tools.getString(args, "network") orelse "mainnet";
        const tx_hash_str = mcp.tools.getString(args, "tx_hash") orelse {
            return mcp.tools.errorResult(allocator, "Missing required parameter: tx_hash") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const tx_hash = evm_helpers.parseHash(tx_hash_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid transaction hash") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const tx_response = adapter.getTransactionByHash(tx_hash) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get transaction: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer tx_response.deinit();

        const tx_json = evm_helpers.jsonStringifyAlloc(allocator, tx_response.response) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(tx_json);

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\",\"transaction\":{s}}}",
            .{ chain_name, network, adapter.endpoint, tx_json },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(response);
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
