const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const process = std.process;

/// Create a Jupiter trigger (limit) order.
/// Returns an unsigned transaction for signing.
///
/// Parameters:
/// - input_mint: Base58 input token mint (required)
/// - output_mint: Base58 output token mint (required)
/// - maker: Base58 public key of the maker wallet (required)
/// - making_amount: Amount of input tokens (required)
/// - taking_amount: Amount of output tokens (required)
/// - expired_at: Expiration timestamp in seconds (optional)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - api_key: Jupiter API key (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with trigger order transaction
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

    const maker = mcp.tools.getString(args, "maker") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: maker") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const making_amount = mcp.tools.getString(args, "making_amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: making_amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const taking_amount = mcp.tools.getString(args, "taking_amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: taking_amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const expired_at = mcp.tools.getInteger(args, "expired_at");
    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse "https://api.jup.ag/trigger/v1/createOrder";
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
    request_obj.put("maker", .{ .string = maker }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("makingAmount", .{ .string = making_amount }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("takingAmount", .{ .string = taking_amount }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    if (expired_at) |exp| {
        request_obj.put("expiredAt", .{ .integer = exp }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = postHttp(allocator, endpoint_base, request_body, api_key, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create trigger order: {s}", .{@errorName(err)}) catch {
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
        maker: []const u8,
        order: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .input_mint = input_mint,
        .output_mint = output_mint,
        .maker = maker,
        .order = parsed.value,
        .endpoint = endpoint_base,
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
