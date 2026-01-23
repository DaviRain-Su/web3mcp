const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");

const RpcClient = solana_client.RpcClient;
const Signature = solana_sdk.Signature;

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

    const signature_str = mcp.tools.getString(args, "signature") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: signature") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "devnet";

    const signature = solana_helpers.parseSignature(signature_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid transaction signature") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint = solana_helpers.resolveEndpoint(network);
    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    const tx_opt = client.getTransaction(signature) catch |err| {
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
        signature: []const u8,
        slot: u64,
        block_time: ?i64 = null,
        fee: ?u64 = null,
        err_type: ?[]const u8 = null,
        err_instruction: ?u8 = null,
        pre_balances: ?[]const u64 = null,
        post_balances: ?[]const u64 = null,
        transaction_data: []const u8,
        network: []const u8,
    };

    var response_value: TxResponse = .{
        .signature = signature_str,
        .slot = tx.slot,
        .block_time = tx.block_time,
        .transaction_data = tx.transaction.data,
        .network = network,
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
