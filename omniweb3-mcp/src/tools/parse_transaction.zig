const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");

/// Parse Solana transaction details (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - signature: Base58 signature (required)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with transaction metadata, logs, and token balances
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for parse_transaction: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const signature_str = mcp.tools.getString(args, "signature") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: signature") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

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

    const ParsedResponse = struct {
        chain: []const u8,
        signature: []const u8,
        slot: u64,
        block_time: ?i64 = null,
        fee: ?u64 = null,
        err_type: ?[]const u8 = null,
        err_instruction: ?u8 = null,
        pre_balances: ?[]const u64 = null,
        post_balances: ?[]const u64 = null,
        compute_units_consumed: ?u64 = null,
        network: []const u8,
        endpoint: []const u8,
    };

    var response_value: ParsedResponse = .{
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
        response_value.compute_units_consumed = meta.compute_units_consumed;
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
