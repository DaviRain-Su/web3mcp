const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");

const RpcClient = solana_client.RpcClient;
const Signature = solana_sdk.Signature;
const TransactionStatus = solana_client.TransactionStatus;

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

    const statuses = client.getSignatureStatusesWithHistory(&.{signature}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get signature status: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(statuses);

    const status_opt = if (statuses.len > 0) statuses[0] else null;

    const StatusResponse = struct {
        signature: []const u8,
        found: bool,
        slot: ?u64 = null,
        confirmations: ?u64 = null,
        confirmation_status: ?[]const u8 = null,
        err_type: ?[]const u8 = null,
        err_instruction: ?u8 = null,
        network: []const u8,
    };

    var response_value: StatusResponse = .{
        .signature = signature_str,
        .found = false,
        .network = network,
    };

    if (status_opt) |status| {
        response_value.found = true;
        response_value.slot = status.slot;
        response_value.confirmations = status.confirmations;
        response_value.confirmation_status = if (status.confirmation_status) |c| @tagName(c) else null;
        if (status.err) |err_info| {
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
