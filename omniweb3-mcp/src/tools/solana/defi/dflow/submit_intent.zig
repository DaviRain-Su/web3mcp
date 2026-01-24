const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");

/// Submit signed dFlow intent transaction (Solana-only, declarative swap API).
///
/// After getting an intent from get_dflow_intent, sign the transaction and
/// submit it here for execution with deferred routing.
///
/// Parameters:
/// - signed_transaction: Base64 encoded signed transaction (required)
///
/// Returns JSON with submission result
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const signed_transaction = mcp.tools.getString(args, "signed_transaction") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: signed_transaction") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Build request body
    const RequestBody = struct {
        signedTransaction: []const u8,
    };

    const request_body: RequestBody = .{
        .signedTransaction = signed_transaction,
    };

    const body_json = solana_helpers.jsonStringifyAlloc(allocator, request_body) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(body_json);

    const response_body = secure_http.dflowPost(allocator, endpoints.dflow.submit_intent, body_json) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to submit dFlow intent: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(response_body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response_body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow submit response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        mode: []const u8,
        result: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .mode = "declarative",
        .result = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
