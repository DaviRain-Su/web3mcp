//! Meteora DAMM v1 Get Pool Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_client = @import("solana_client");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;
const RpcClient = solana_client.RpcClient;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address_str = mcp.tools.getString(args, "pool_address") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: pool_address");
    };

    const pool_address = helpers.parsePublicKey(pool_address_str) orelse {
        return helpers.errorResult(allocator, "Invalid pool_address");
    };

    const endpoint = helpers.getEndpoint(args);

    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    const account_info = client.getAccountInfo(pool_address) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch pool: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return helpers.errorResult(allocator, msg);
    };

    if (account_info == null) {
        return helpers.errorResult(allocator, "Pool not found");
    }

    if (!constants.isProgramId(account_info.?.owner, constants.PROGRAM_IDS.DAMM_V1)) {
        return helpers.errorResult(allocator, "Not a DAMM v1 pool");
    }

    const data = account_info.?.data;

    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const Response = struct {
        address: []const u8,
        program_id: []const u8,
        data_len: usize,
        network: []const u8,
        note: []const u8,
    };

    const response = Response{
        .address = pool_address_str,
        .program_id = "Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB",
        .data_len = data.len,
        .network = network,
        .note = "DAMM v1 supports constant product, stable, and weighted pools. Uses LP tokens (not NFTs).",
    };

    return helpers.jsonResult(allocator, response);
}
