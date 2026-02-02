const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const jupiter_helpers = @import("../helpers.zig");

/// Create a Jupiter recurring (DCA) order.
/// Returns an unsigned transaction for signing.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - user: Base58 public key of the user wallet (required)
/// - input_mint: Base58 input token mint (required)
/// - output_mint: Base58 output token mint (required)
/// - in_amount: Total amount to DCA (required)
/// - in_amount_per_cycle: Amount per cycle (required)
/// - cycle_frequency: Seconds between cycles (required)
/// - min_out_amount_per_cycle: Minimum output per cycle (optional)
/// - max_out_amount_per_cycle: Maximum output per cycle (optional)
/// - start_at: Start timestamp in seconds (optional)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with recurring order transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const user = jupiter_helpers.resolveAddress(allocator, args, "user") catch |err| {
        return mcp.tools.errorResult(allocator, jupiter_helpers.userResolveErrorMessage(err)) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(user);

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

    const in_amount = mcp.tools.getString(args, "in_amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: in_amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const in_amount_per_cycle = mcp.tools.getString(args, "in_amount_per_cycle") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: in_amount_per_cycle") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const cycle_frequency = mcp.tools.getInteger(args, "cycle_frequency") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: cycle_frequency") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const min_out = mcp.tools.getString(args, "min_out_amount_per_cycle");
    const max_out = mcp.tools.getString(args, "max_out_amount_per_cycle");
    const start_at = mcp.tools.getInteger(args, "start_at");

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse "https://api.jup.ag/recurring/v1/createOrder";
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("user", .{ .string = user }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("inputMint", .{ .string = input_mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("outputMint", .{ .string = output_mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("inAmount", .{ .string = in_amount }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("inAmountPerCycle", .{ .string = in_amount_per_cycle }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("cycleFrequency", .{ .integer = cycle_frequency }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    if (min_out) |m| {
        request_obj.put("minOutAmountPerCycle", .{ .string = m }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (max_out) |m| {
        request_obj.put("maxOutAmountPerCycle", .{ .string = m }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (start_at) |s| {
        request_obj.put("startAt", .{ .integer = s }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_base, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create recurring order: {s}", .{@errorName(err)}) catch {
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

    const signature = if (jupiter_helpers.extractTransactionBase64(parsed.value)) |tx| blk: {
        break :blk jupiter_helpers.signAndSendIfRequested(allocator, args, tx) catch |err| {
            return mcp.tools.errorResult(allocator, jupiter_helpers.signErrorMessage(err)) catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
    } else null;
    defer if (signature) |sig| allocator.free(sig);

    const Response = struct {
        user: []const u8,
        input_mint: []const u8,
        output_mint: []const u8,
        order: std.json.Value,
        endpoint: []const u8,
        signature: ?[]const u8 = null,
    };

    const response_value: Response = .{
        .user = user,
        .input_mint = input_mint,
        .output_mint = output_mint,
        .order = parsed.value,
        .endpoint = endpoint_base,
        .signature = signature,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
