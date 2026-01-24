const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const process = std.process;

/// Create a Jupiter Ultra swap order.
/// Returns an unsigned transaction for signing.
///
/// Parameters:
/// - input_mint: Base58 input token mint (required)
/// - output_mint: Base58 output token mint (required)
/// - amount: Amount in base units (required)
/// - taker: Base58 public key of the taker wallet (required)
/// - slippage_bps: Slippage tolerance in basis points (optional)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with Ultra order transaction
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

    const taker = mcp.tools.getString(args, "taker") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: taker") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const slippage_bps = mcp.tools.getInteger(args, "slippage_bps");
    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.ultra_order;
    const api_key = mcp.tools.getString(args, "api_key");
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("inputMint", .{ .string = input_mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("outputMint", .{ .string = output_mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("taker", .{ .string = taker }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    if (amount_str) |amt| {
        request_obj.put("amount", .{ .string = amt }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    } else if (amount_int) |amt| {
        const amt_str = std.fmt.allocPrint(allocator, "{d}", .{amt}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(amt_str);
        request_obj.put("amount", .{ .string = amt_str }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    if (slippage_bps) |bps| {
        request_obj.put("slippageBps", .{ .integer = bps }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = postHttp(allocator, endpoint_override, request_body, api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create Ultra order: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        input_mint: []const u8,
        output_mint: []const u8,
        taker: []const u8,
        order: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .input_mint = input_mint,
        .output_mint = output_mint,
        .taker = taker,
        .order = parsed.value,
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

fn postHttp(allocator: std.mem.Allocator, url: []const u8, body: []const u8, api_key: ?[]const u8, insecure: bool) ![]u8 {
    _ = insecure;
    return postViaCurl(allocator, url, body, api_key);
}

fn postViaCurl(allocator: std.mem.Allocator, url: []const u8, body: []const u8, api_key: ?[]const u8) ![]u8 {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "curl");
    try argv.append(allocator, "-sL");
    try argv.append(allocator, "-X");
    try argv.append(allocator, "POST");
    try argv.append(allocator, "-H");
    try argv.append(allocator, "Content-Type: application/json");

    var api_header: ?[]u8 = null;
    defer if (api_header) |h| allocator.free(h);

    if (api_key) |key| {
        try argv.append(allocator, "-H");
        api_header = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{key});
        try argv.append(allocator, api_header.?);
    }

    try argv.append(allocator, "-d");
    try argv.append(allocator, body);
    try argv.append(allocator, url);

    const result = try process.run(allocator, evm_runtime.io(), .{
        .argv = argv.items,
        .max_output_bytes = 2 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        allocator.free(result.stdout);
        return error.FetchFailed;
    }
    return result.stdout;
}
