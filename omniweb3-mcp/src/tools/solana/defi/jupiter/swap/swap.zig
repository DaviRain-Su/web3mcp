const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Build a Jupiter swap transaction from a quote.
/// Returns an unsigned transaction that needs to be signed and submitted.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - quote_response: The full quote response JSON from get_jupiter_quote (required)
/// - user_public_key: Base58 public key of the user wallet (required)
/// - wrap_unwrap_sol: Wrap/unwrap SOL automatically (optional, default: true)
/// - use_shared_accounts: Use shared accounts for better success rate (optional, default: true)
/// - fee_account: Fee account for referral fees (optional)
/// - compute_unit_price_micro_lamports: Priority fee in micro lamports (optional)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with unsigned swap transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const quote_response = mcp.tools.getString(args, "quote_response") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: quote_response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const user_public_key = mcp.tools.getString(args, "user_public_key") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: user_public_key") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const wrap_unwrap_sol = mcp.tools.getBoolean(args, "wrap_unwrap_sol") orelse true;
    const use_shared_accounts = mcp.tools.getBoolean(args, "use_shared_accounts") orelse true;
    const fee_account = mcp.tools.getString(args, "fee_account");
    const compute_unit_price = mcp.tools.getInteger(args, "compute_unit_price_micro_lamports");

    const endpoint_override = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.swap;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    const parsed_quote = std.json.parseFromSlice(std.json.Value, allocator, quote_response, .{}) catch {
        return mcp.tools.errorResult(allocator, "Invalid quote_response JSON") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed_quote.deinit();

    request_obj.put("quoteResponse", parsed_quote.value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("userPublicKey", .{ .string = user_public_key }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("wrapAndUnwrapSol", .{ .bool = wrap_unwrap_sol }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("useSharedAccounts", .{ .bool = use_shared_accounts }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    if (fee_account) |fa| {
        request_obj.put("feeAccount", .{ .string = fa }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    if (compute_unit_price) |cup| {
        request_obj.put("computeUnitPriceMicroLamports", .{ .integer = cup }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_override, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to build swap transaction: {s}", .{@errorName(err)}) catch {
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
        user_public_key: []const u8,
        swap_transaction: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .user_public_key = user_public_key,
        .swap_transaction = parsed.value,
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
