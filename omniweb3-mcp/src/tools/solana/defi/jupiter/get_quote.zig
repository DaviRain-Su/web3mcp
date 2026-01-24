const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../../../core/evm_runtime.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const process = std.process;

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
    const api_key = mcp.tools.getString(args, "api_key");
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

    const body = fetchHttp(allocator, url, api_key, insecure) catch |err| {
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

fn fetchHttp(allocator: std.mem.Allocator, url: []const u8, api_key: ?[]const u8, insecure: bool) ![]u8 {
    if (insecure) {
        return fetchViaCurl(allocator, url, api_key, true);
    }

    var client = std.http.Client{ .allocator = allocator, .io = evm_runtime.io() };
    defer client.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);

    var headers: [1]std.http.Header = undefined;
    const extra_headers = if (api_key) |key| blk: {
        headers[0] = .{ .name = "x-api-key", .value = key };
        break :blk headers[0..1];
    } else &.{};

    const fetch_result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &out.writer,
        .extra_headers = extra_headers,
    }) catch {
        return fetchViaCurl(allocator, url, api_key, false);
    };

    if (fetch_result.status.class() != .success) {
        return fetchViaCurl(allocator, url, api_key, false);
    }

    return out.toOwnedSlice();
}

fn fetchViaCurl(allocator: std.mem.Allocator, url: []const u8, api_key: ?[]const u8, insecure: bool) ![]u8 {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "curl");
    if (insecure) {
        try argv.append(allocator, "-k");
    }
    try argv.append(allocator, "-sL");

    var header_value: ?[]u8 = null;
    defer if (header_value) |value| allocator.free(value);

    if (api_key) |key| {
        try argv.append(allocator, "-H");
        header_value = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{key});
        try argv.append(allocator, header_value.?);
    }

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
