const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");

/// Get fee for a Solana transaction message (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - message: base64-encoded transaction message (required)
/// - network: devnet/testnet/mainnet/localhost (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with fee in lamports (nullable)
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_fee_for_message: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const message_b64 = mcp.tools.getString(args, "message") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: message") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(message_b64) catch {
        return mcp.tools.errorResult(allocator, "Invalid base64 message") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const message = allocator.alloc(u8, decoded_len) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(message);

    std.base64.standard.Decoder.decode(message, message_b64) catch {
        return mcp.tools.errorResult(allocator, "Invalid base64 message") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const fee = adapter.getFeeForMessage(message) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get fee for message: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const Response = struct {
        chain: []const u8,
        fee_lamports: ?u64 = null,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .fee_lamports = fee,
        .network = network,
        .endpoint = adapter.endpoint,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
