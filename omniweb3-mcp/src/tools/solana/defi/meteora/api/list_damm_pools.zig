const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../../core/secure_http.zig");

/// Get all Meteora DAMM (Dynamic AMM) pools via REST API.
///
/// This tool fetches all DAMM V2 pools from Meteora's official API.
/// DAMM is Meteora's constant product AMM with dynamic fees.
///
/// Parameters:
/// - endpoint: Override Meteora API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON array with all DAMM pool data including:
/// - Pool address and type
/// - Token pair information
/// - Current reserves and liquidity
/// - Trading volume and fees
/// - APR/APY metrics
///
/// Example response structure:
/// ```json
/// {
///   "pools": [
///     {
///       "pool_address": "9WbGQFmSSt5cZqLFYoRWv2uZw7s8wqe2RoGmPgCFAGJz",
///       "pool_name": "SOL-USDT",
///       "pool_type": "StableSwap",
///       "token_a_mint": "So11111111111111111111111111111111111111112",
///       "token_b_mint": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
///       "token_a_amount": 1234.56,
///       "token_b_amount": 154321.12,
///       "tvl": 308642.24,
///       "volume_24h": 567890.12,
///       "fees_24h": 1419.73,
///       "apr": 23.4,
///       "apy": 26.3
///     }
///   ],
///   "count": 45,
///   "endpoint": "https://amm-v2.meteora.ag/pool/list"
/// }
/// ```
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.meteora.damm_pools;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;
    const use_api_key = false; // Meteora API doesn't require API key

    const body = secure_http.secureGet(allocator, endpoint_override, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch Meteora DAMM pools: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    // Parse response
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse Meteora API response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        pools: std.json.Value,
        count: usize,
        endpoint: []const u8,
    };

    // Count pools if it's an array
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
