const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../../core/secure_http.zig");

/// Get specific Meteora DLMM pool info via REST API.
///
/// This tool fetches detailed information for a specific DLMM pool from Meteora's
/// official API, providing accurate real-time data.
///
/// Parameters:
/// - pool_address: Base58 DLMM pool address (required)
/// - endpoint: Override Meteora API base endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with detailed pool information including:
/// - Pool metadata (address, name, type)
/// - Token information (mints, symbols, decimals)
/// - Current state (price, active bin, reserves)
/// - Trading metrics (24h volume, fees, APR/APY)
/// - Fee structure (bin step, base fee percentage)
/// - Liquidity distribution
///
/// Example response:
/// ```json
/// {
///   "address": "BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y",
///   "name": "SOL-USDC",
///   "mint_x": "So11111111111111111111111111111111111111112",
///   "mint_y": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
///   "decimals_x": 9,
///   "decimals_y": 6,
///   "current_price": 125.5,
///   "reserve_x": "123456789000000",
///   "reserve_y": "987654321000",
///   "reserve_x_amount": 123.456789,
///   "reserve_y_amount": 987654.321,
///   "bin_step": 25,
///   "base_fee_percentage": "0.25",
///   "trade_volume_24h": 1234567.89,
///   "fees_24h": 3086.42,
///   "apr": 45.6,
///   "apy": 57.8,
///   "tvl": 246913.58,
///   "endpoint": "https://dlmm-api.meteora.ag/pair/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y"
/// }
/// ```
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const pool_address = mcp.tools.getString(args, "pool_address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: pool_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.meteora.dlmm_pair;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;
    const use_api_key = false; // Meteora API doesn't require API key

    // Build URL: /pair/{address}
    const url = std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ endpoint_base, pool_address },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch DLMM pool info: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    // Parse and validate response
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse Meteora API response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    // Wrap response with metadata
    const Response = struct {
        pool_address: []const u8,
        pool_data: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .pool_address = pool_address,
        .pool_data = parsed.value,
        .endpoint = url,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
