const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");

const PublicKey = solana_sdk.PublicKey;
const SignatureInfo = solana_client.types.SignatureInfo;

/// Get signatures for a Solana address (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - address: Base58 address (required)
/// - limit: Max signatures (optional)
/// - before: Signature to start before (optional)
/// - until: Signature to stop at (optional)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with signature list
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_signatures_for_address: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const address_str = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const limit_raw = mcp.tools.getInteger(args, "limit");
    const before_str = mcp.tools.getString(args, "before");
    const until_str = mcp.tools.getString(args, "until");
    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    const address = solana_helpers.parsePublicKey(address_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid address") catch {
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

    const limit: ?u32 = if (limit_raw) |value| if (value > 0) @as(u32, @intCast(value)) else null else null;
    const before_sig = if (before_str) |value| solana_helpers.parseSignature(value) catch {
        return mcp.tools.errorResult(allocator, "Invalid before signature") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    } else null;
    const until_sig = if (until_str) |value| solana_helpers.parseSignature(value) catch {
        return mcp.tools.errorResult(allocator, "Invalid until signature") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    } else null;

    const signatures: []SignatureInfo = adapter.getSignaturesForAddress(address, limit, before_sig, until_sig) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get signatures: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(signatures);

    const Response = struct {
        chain: []const u8,
        address: []const u8,
        signatures: []const SignatureInfo,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .address = address_str,
        .signatures = signatures,
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
