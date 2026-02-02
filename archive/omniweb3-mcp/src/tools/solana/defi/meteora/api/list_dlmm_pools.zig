const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../../core/secure_http.zig");

/// Get all Meteora DLMM pools via REST API.
///
/// This tool fetches pool data from Meteora's official API, providing accurate
/// information including pool addresses, token pairs, prices, TVL, volume, fees, and APRs.
///
/// Parameters:
/// - endpoint: Override Meteora API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON array with all DLMM pool data including:
/// - Pool address and type
/// - Token mints and symbols
/// - Current price and active bin
/// - Reserves (TVL)
/// - 24h volume and fees
/// - APRs (base fee, rewards)
/// - Trading fee (in basis points)
///
/// Example response structure:
/// ```json
/// {
///   "pools": [
///     {
///       "address": "BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y",
///       "name": "SOL-USDC",
///       "mint_x": "So11111111111111111111111111111111111111112",
///       "mint_y": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
///       "reserve_x": "123456789",
///       "reserve_y": "987654321",
///       "current_price": 125.5,
///       "bin_step": 25,
///       "base_fee_percentage": "0.25",
///       "trade_volume_24h": 1234567.89,
///       "fees_24h": 3086.42,
///       "today_fees": 1543.21,
///       "apr": 45.6,
///       "apy": 57.8
///     }
///   ],
///   "count": 250,
///   "endpoint": "https://dlmm-api.meteora.ag/pair/all"
/// }
/// ```
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.meteora.dlmm_pairs_all;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;
    const use_api_key = false; // Meteora API doesn't require API key for read endpoints

    const body = secure_http.secureGet(allocator, endpoint_override, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch Meteora DLMM pools: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    // Parse response to validate it's valid JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse Meteora API response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    // Meteora API returns: { "groups": { ... } } or array of pools
    // We'll wrap it in a response structure
    const Response = struct {
        pools: std.json.Value,
        count: usize,
        endpoint: []const u8,
    };

    // Count pools (if it's an array, otherwise estimate from groups)
    const pool_count = if (parsed.value == .array) parsed.value.array.items.len else 0;

    const response_value: Response = .{
        .pools = parsed.value,
        .count = pool_count,
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
