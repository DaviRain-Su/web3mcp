//! Privy List Wallets Tool
//!
//! Get all wallets in your Privy app.

const std = @import("std");
const mcp = @import("mcp");
const client = @import("../client.zig");

/// List all Privy wallets
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    if (!client.isConfigured()) {
        return client.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.");
    }

    const chain_type = getChainType(allocator, args);
    const cursor = mcp.tools.getString(args, "cursor");
    const limit = mcp.tools.getInteger(args, "limit");

    // Build path with query string
    const path = blk: {
        if (chain_type != null and cursor != null and limit != null) {
            break :blk std.fmt.allocPrint(allocator, "/wallets?chain_type={s}&cursor={s}&limit={d}", .{ chain_type.?, cursor.?, limit.? });
        } else if (chain_type != null and cursor != null) {
            break :blk std.fmt.allocPrint(allocator, "/wallets?chain_type={s}&cursor={s}", .{ chain_type.?, cursor.? });
        } else if (chain_type != null and limit != null) {
            break :blk std.fmt.allocPrint(allocator, "/wallets?chain_type={s}&limit={d}", .{ chain_type.?, limit.? });
        } else if (cursor != null and limit != null) {
            break :blk std.fmt.allocPrint(allocator, "/wallets?cursor={s}&limit={d}", .{ cursor.?, limit.? });
        } else if (chain_type) |ct| {
            break :blk std.fmt.allocPrint(allocator, "/wallets?chain_type={s}", .{ct});
        } else if (cursor) |c| {
            break :blk std.fmt.allocPrint(allocator, "/wallets?cursor={s}", .{c});
        } else if (limit) |l| {
            break :blk std.fmt.allocPrint(allocator, "/wallets?limit={d}", .{l});
        } else {
            break :blk std.fmt.allocPrint(allocator, "/wallets", .{});
        }
    };

    const path_str = path catch return mcp.tools.ToolError.OutOfMemory;
    defer allocator.free(path_str);

    // Make API request
    const response = client.privyGet(allocator, path_str) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Privy API error: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return client.errorResult(allocator, msg);
    };
    defer allocator.free(response);

    return client.jsonResult(allocator, response);
}

fn getChainType(allocator: std.mem.Allocator, args: ?std.json.Value) ?[]const u8 {
    if (mcp.tools.getString(args, "chain_type")) |val| return val;
    if (mcp.tools.getString(args, "chainType")) |val| return val;

    if (args) |a| {
        if (a == .string) {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, a.string, .{}) catch return null;
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("chain_type")) |v| if (v == .string) return v.string;
                if (parsed.value.object.get("chainType")) |v| if (v == .string) return v.string;
            }
        }
    }

    return null;
}
