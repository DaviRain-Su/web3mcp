//! Meteora Dynamic Bonding Curve Create Pool Tool

const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const helpers = @import("../helpers.zig");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const user_str = helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return helpers.errorResult(allocator, helpers.userResolveErrorMessage(err));
    };
    defer allocator.free(user_str);

    const name = mcp.tools.getString(args, "name") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: name");
    };

    const symbol = mcp.tools.getString(args, "symbol") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: symbol");
    };

    const uri = mcp.tools.getString(args, "uri") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: uri");
    };

    _ = helpers.parsePublicKey(user_str) orelse {
        return helpers.errorResult(allocator, "Invalid user");
    };

    const base_amount: u64 = blk: {
        if (mcp.tools.getString(args, "base_amount")) |s| {
            break :blk std.fmt.parseInt(u64, s, 10) catch {
                return helpers.errorResult(allocator, "Invalid base_amount");
            };
        } else if (mcp.tools.getInteger(args, "base_amount")) |i| {
            if (i < 0) return helpers.errorResult(allocator, "base_amount must be non-negative");
            break :blk @intCast(i);
        } else {
            return helpers.errorResult(allocator, "Missing required parameter: base_amount");
        }
    };

    const config_str = mcp.tools.getString(args, "config") orelse "default";

    const Response = struct {
        status: []const u8,
        creator: []const u8,
        name: []const u8,
        symbol: []const u8,
        uri: []const u8,
        base_amount: u64,
        config: []const u8,
        instruction: []const u8,
        note: []const u8,
    };

    const response = Response{
        .status = "instruction_prepared",
        .creator = user_str,
        .name = name,
        .symbol = symbol,
        .uri = uri,
        .base_amount = base_amount,
        .config = config_str,
        .instruction = "create_pool",
        .note = "Creates new token and bonding curve pool. Token will be mintable until graduation.",
    };

    return helpers.jsonResult(allocator, response);
}
