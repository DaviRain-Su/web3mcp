const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for signature_status: {s}", .{chain_name}) catch {
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

    const status_opt = adapter.getSignatureStatus(signature) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get signature status: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const StatusResponse = struct {
        chain: []const u8,
        signature: []const u8,
        found: bool,
        slot: ?u64 = null,
        confirmations: ?u64 = null,
        confirmation_status: ?[]const u8 = null,
        err_type: ?[]const u8 = null,
        err_instruction: ?u8 = null,
        network: []const u8,
        endpoint: []const u8,
    };

    var response_value: StatusResponse = .{
        .chain = "solana",
        .signature = signature_str,
        .found = false,
        .network = network,
        .endpoint = adapter.endpoint,
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
