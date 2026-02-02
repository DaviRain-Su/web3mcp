const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Get Jupiter token price (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - mint: Base58 mint address (required)
/// - endpoint: Override Jupiter price endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with price data
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_jupiter_price: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const mint = mcp.tools.getString(args, "mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.price;
    const use_api_key = true; // Always use API key from environment variable
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;
    const url = try std.fmt.allocPrint(allocator, "{s}?ids={s}", .{ endpoint_override, mint });
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch Jupiter price: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse Jupiter price") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    // V3 API returns: { "mint": { "usdPrice": 123.45, "decimals": 9, ... } }
    // (no "data" wrapper like V2)
    if (parsed.value != .object) {
        return mcp.tools.errorResult(allocator, "Invalid price response format") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const mint_entry = parsed.value.object.get(mint) orelse {
        const snippet_len = @min(body.len, 512);
        const msg = std.fmt.allocPrint(allocator, "Price not found for mint. Response: {s}", .{body[0..snippet_len]}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    if (mint_entry != .object) {
        return mcp.tools.errorResult(allocator, "Invalid mint entry format") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const price_value = mint_entry.object.get("usdPrice") orelse {
        return mcp.tools.errorResult(allocator, "Missing usdPrice field") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const price = switch (price_value) {
        .float => price_value.float,
        .integer => @as(f64, @floatFromInt(price_value.integer)),
        else => return mcp.tools.errorResult(allocator, "Invalid usdPrice field") catch {
            return mcp.tools.ToolError.InvalidArguments;
        },
    };

    const Response = struct {
        chain: []const u8,
        mint: []const u8,
        price: f64,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .mint = mint,
        .price = price,
        .endpoint = endpoint_override,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

