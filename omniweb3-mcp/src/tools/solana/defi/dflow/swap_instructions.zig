const std = @import("std");
const mcp = @import("mcp");
const secure_http = @import("../../../../core/secure_http.zig");
const solana_helpers = @import("../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../core/endpoints.zig");
const dflow_helpers = @import("helpers.zig");

/// Get dFlow swap instructions (Solana-only, imperative swap API).
///
/// Similar to swap, but returns individual instructions instead of a complete transaction.
/// Useful for composing with other instructions.
///
/// Parameters:
/// - quote: The quote object returned from get_dflow_quote (required)
/// - user_public_key: User's public key for signing (required)
///
/// Returns JSON with swap instructions to compose and sign
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const user_public_key = dflow_helpers.resolveUserPublicKey(allocator, args) catch |err| {
        return mcp.tools.errorResult(allocator, dflow_helpers.userResolveErrorMessage(err)) catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(user_public_key);

    // Get quote object from args
    const quote_value = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("quote")) |q| {
                break :blk q;
            }
        }
        break :blk null;
    } else null;

    if (quote_value == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: quote (must be quote object from get_dflow_quote)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Build request body
    const RequestBody = struct {
        quote: std.json.Value,
        userPublicKey: []const u8,
    };

    const request_body: RequestBody = .{
        .quote = quote_value.?,
        .userPublicKey = user_public_key,
    };

    const body_json = solana_helpers.jsonStringifyAlloc(allocator, request_body) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(body_json);

    const response_body = secure_http.dflowPost(allocator, endpoints.dflow.swap_instructions, body_json) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get dFlow swap instructions: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(response_body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response_body, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse dFlow swap instructions response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed.deinit();

    const Response = struct {
        protocol: []const u8,
        user_public_key: []const u8,
        instructions: std.json.Value,
    };

    const response_value: Response = .{
        .protocol = "dflow",
        .user_public_key = user_public_key,
        .instructions = parsed.value,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
