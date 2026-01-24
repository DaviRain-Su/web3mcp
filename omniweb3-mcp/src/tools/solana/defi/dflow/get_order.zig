const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const dflow_helpers = @import("helpers.zig");

/// Get dFlow order with quote and optional transaction (Solana-only).
///
/// This is a unified endpoint that returns both quote and optionally
/// the transaction to execute.
///
/// Parameters:
/// - input_mint: Base58 input token mint (required)
/// - output_mint: Base58 output token mint (required)
/// - amount: Amount in base units (required)
/// - slippage_bps: Slippage tolerance in basis points (optional, default: 50)
/// - user_public_key: User's public key (optional, if provided returns tx)
/// - include_tx: Whether to include transaction (optional, default: false)
///
/// Returns JSON with dFlow order payload
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
    const user_public_key = dflow_helpers.resolveOptionalUserPublicKey(allocator, args) catch |err| {
        return mcp.tools.errorResult(allocator, dflow_helpers.userResolveErrorMessage(err)) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer if (user_public_key) |value| allocator.free(value);
    const include_tx = mcp.tools.getBoolean(args, "include_tx") orelse false;

    // Build URL with query parameters
    const base_url = std.fmt.allocPrint(
        allocator,
        "{s}?inputMint={s}&outputMint={s}&amount={s}&slippageBps={d}",
        .{ endpoints.dflow.order, input_mint, output_mint, amount_value, slippage_bps },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(base_url);

    // Add optional parameters
    const url_with_pubkey = if (user_public_key) |pubkey| blk: {
        break :blk std.fmt.allocPrint(allocator, "{s}&userPublicKey={s}", .{ base_url, pubkey }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    } else blk: {
        break :blk allocator.dupe(u8, base_url) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(url_with_pubkey);

    const url = if (include_tx) blk: {
        break :blk std.fmt.allocPrint(allocator, "{s}&includeTx=true", .{url_with_pubkey}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    } else blk: {
        break :blk allocator.dupe(u8, url_with_pubkey) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(url);

    const body = secure_http.dflowGet(allocator, url) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch dFlow order: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow order response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        input_mint: []const u8,
        output_mint: []const u8,
        amount: []const u8,
        slippage_bps: i64,
        include_tx: bool,
        order: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .input_mint = input_mint,
        .output_mint = output_mint,
        .amount = amount_value,
        .slippage_bps = slippage_bps,
        .include_tx = include_tx,
        .order = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
