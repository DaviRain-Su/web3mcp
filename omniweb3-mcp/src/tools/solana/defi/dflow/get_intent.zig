const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");

/// Get dFlow intent quote (Solana-only, declarative swap API).
///
/// Intent-based swaps use deferred routing - the exact route is determined
/// at execution time for potentially better prices.
///
/// Parameters:
/// - input_mint: Base58 input token mint (required)
/// - output_mint: Base58 output token mint (required)
/// - amount: Amount in base units (required)
/// - slippage_bps: Slippage tolerance in basis points (optional, default: 50)
/// - user_public_key: User's public key (required)
///
/// Returns JSON with dFlow intent payload
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const input_mint = mcp.tools.getString(args, "input_mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: input_mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const output_mint = mcp.tools.getString(args, "output_mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: output_mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const user_public_key = mcp.tools.getString(args, "user_public_key") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: user_public_key") catch {
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

    // Build URL with query parameters
    const url = std.fmt.allocPrint(
        allocator,
        "{s}?inputMint={s}&outputMint={s}&amount={s}&slippageBps={d}&userPublicKey={s}",
        .{ endpoints.dflow.intent, input_mint, output_mint, amount_value, slippage_bps, user_public_key },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(url);

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow intent: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow intent response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        mode: []const u8,
        input_mint: []const u8,
        output_mint: []const u8,
        amount: []const u8,
        slippage_bps: i64,
        user_public_key: []const u8,
        intent: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .mode = "declarative",
        .input_mint = input_mint,
        .output_mint = output_mint,
        .amount = amount_value,
        .slippage_bps = slippage_bps,
        .user_public_key = user_public_key,
        .intent = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
