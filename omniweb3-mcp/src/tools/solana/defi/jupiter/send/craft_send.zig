const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const jupiter_helpers = @import("../helpers.zig");

/// Create a Jupiter Send transaction.
/// Returns an unsigned transaction for sending tokens to another wallet.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - sender: Base58 public key of the sender wallet (required)
/// - recipient: Base58 public key or invite code of the recipient (required)
/// - mint: Base58 token mint to send (required)
/// - amount: Amount to send in base units (required)
/// - memo: Optional memo for the transaction (optional)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with unsigned send transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const sender = jupiter_helpers.resolveAddress(allocator, args, "sender") catch |err| {
        return mcp.tools.errorResult(allocator, jupiter_helpers.userResolveErrorMessage(err)) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(sender);

    const recipient = mcp.tools.getString(args, "recipient") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: recipient") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

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

    const memo = mcp.tools.getString(args, "memo");
    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.send_craft;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("sender", .{ .string = sender }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("recipient", .{ .string = recipient }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("mint", .{ .string = mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("amount", .{ .string = amount }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    if (memo) |m| {
        request_obj.put("memo", .{ .string = m }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_base, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create send transaction: {s}", .{@errorName(err)}) catch {
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
        sender: []const u8,
        recipient: []const u8,
        mint: []const u8,
        amount: []const u8,
        transaction: std.json.Value,
        endpoint: []const u8,
        signature: ?[]const u8 = null,
    };

    const response_value: Response = .{
        .sender = sender,
        .recipient = recipient,
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
