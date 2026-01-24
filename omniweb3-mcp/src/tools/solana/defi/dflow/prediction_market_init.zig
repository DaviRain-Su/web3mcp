const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const dflow_helpers = @import("helpers.zig");

/// Initialize dFlow prediction market (Solana-only).
///
/// Creates a transaction to initialize a prediction market position.
///
/// Parameters:
/// - user_public_key: User's public key (required)
/// - market_ticker: Prediction market ticker (required)
/// - side: "yes" or "no" (required)
/// - amount: Amount in base units (required)
/// - slippage_bps: Slippage tolerance in basis points (optional, default: 50)
///
/// Returns JSON with initialization transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const user_public_key = dflow_helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return mcp.tools.errorResult(allocator, dflow_helpers.userResolveErrorMessage(err)) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(user_public_key);
    const market_ticker = mcp.tools.getString(args, "market_ticker") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: market_ticker") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const side = mcp.tools.getString(args, "side") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: side (yes or no)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount_str = mcp.tools.getString(args, "amount");
    const amount_int = mcp.tools.getInteger(args, "amount");
    if (amount_str == null and amount_int == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const amount_value: []const u8 = if (amount_str) |value| value else blk: {
        if (amount_int.? < 0) {
            return mcp.tools.errorResult(allocator, "amount must be non-negative") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        break :blk std.fmt.allocPrint(allocator, "{d}", .{amount_int.?}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer if (amount_str == null) allocator.free(amount_value);

    const slippage_bps = mcp.tools.getInteger(args, "slippage_bps") orelse 50;

    // Build request body
    const RequestBody = struct {
        userPublicKey: []const u8,
        marketTicker: []const u8,
        side: []const u8,
        amount: []const u8,
        slippageBps: i64,
    };

    const request_body: RequestBody = .{
        .userPublicKey = user_public_key,
        .marketTicker = market_ticker,
        .side = side,
        .amount = amount_value,
        .slippageBps = slippage_bps,
    };

    const body_json = solana_helpers.jsonStringifyAlloc(allocator, request_body) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(body_json);

    const response_body = secure_http.dflowPost(allocator, endpoints.dflow.prediction_market_init, body_json) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init dFlow prediction market: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(response_body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response_body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow prediction market init response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        market_ticker: []const u8,
        side: []const u8,
        amount: []const u8,
        result: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .market_ticker = market_ticker,
        .side = side,
        .amount = amount_value,
        .result = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
