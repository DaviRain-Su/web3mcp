const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const jupiter_helpers = @import("../helpers.zig");

/// Create a Jupiter Lend deposit transaction.
/// Returns an unsigned transaction for signing.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - user: Base58 public key of the user wallet (required)
/// - mint: Base58 token mint to deposit (required)
/// - amount: Amount to deposit in base units (required)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with deposit transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const user = jupiter_helpers.resolveAddress(allocator, args, "user") catch |err| {
        return mcp.tools.errorResult(allocator, jupiter_helpers.userResolveErrorMessage(err)) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(user);

    const mint = mcp.tools.getString(args, "mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount = mcp.tools.getString(args, "amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse "https://api.jup.ag/lend/v1/earn/deposit";
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("user", .{ .string = user }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("mint", .{ .string = mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("amount", .{ .string = amount }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_base, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create lend deposit: {s}", .{@errorName(err)}) catch {
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
        mint: []const u8,
        amount: []const u8,
        transaction: std.json.Value,
        endpoint: []const u8,
        signature: ?[]const u8 = null,
    };

    const response_value: Response = .{
        .user = user,
        .mint = mint,
        .amount = amount,
        .transaction = parsed.value,
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
