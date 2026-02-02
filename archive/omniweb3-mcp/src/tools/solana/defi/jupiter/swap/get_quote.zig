const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Get Jupiter swap quote (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - input_mint: Base58 input mint (required)
/// - output_mint: Base58 output mint (required)
/// - amount: Amount in base units (required)
/// - swap_mode: ExactIn | ExactOut (optional, default: ExactIn)
/// - slippage_bps: Slippage in basis points (optional)
/// - endpoint: Override Jupiter quote endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with Jupiter quote payload
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for get_jupiter_quote: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

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
        break :blk try std.fmt.allocPrint(allocator, "{d}", .{amount_int.?});
    };
    defer if (amount_str == null) allocator.free(amount_value);

    const swap_mode = mcp.tools.getString(args, "swap_mode") orelse "ExactIn";
    const slippage_bps = mcp.tools.getInteger(args, "slippage_bps");
    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.quote;
    const use_api_key = true; // Always use API key from environment variable
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    const url = if (slippage_bps) |bps| blk: {
        break :blk try std.fmt.allocPrint(
            allocator,
            "{s}?inputMint={s}&outputMint={s}&amount={s}&swapMode={s}&slippageBps={d}",
            .{ endpoint_override, input_mint, output_mint, amount_value, swap_mode, bps },
        );
    } else blk: {
        break :blk try std.fmt.allocPrint(
            allocator,
            "{s}?inputMint={s}&outputMint={s}&amount={s}&swapMode={s}",
            .{ endpoint_override, input_mint, output_mint, amount_value, swap_mode },
        );
    };
    defer allocator.free(url);

    const body = secure_http.secureGet(allocator, url, use_api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to fetch Jupiter quote: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse Jupiter quote") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        chain: []const u8,
        input_mint: []const u8,
        output_mint: []const u8,
        amount: []const u8,
        swap_mode: []const u8,
        quote: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .input_mint = input_mint,
        .output_mint = output_mint,
        .amount = amount_value,
        .swap_mode = swap_mode,
        .quote = parsed.value,
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

