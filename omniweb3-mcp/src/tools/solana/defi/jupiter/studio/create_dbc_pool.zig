const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");

/// Create a Jupiter Dynamic Bonding Curve pool with token metadata.
///
/// SECURITY: API key is read from JUPITER_API_KEY environment variable.
/// POST body is written to temp file to avoid exposure in process list.
///
/// Parameters:
/// - creator: Base58 public key of the pool creator (required)
/// - name: Token name (required)
/// - symbol: Token symbol (required)
/// - uri: Token metadata URI (required)
/// - decimals: Token decimals (optional, default: 9)
/// - total_supply: Total token supply (optional)
/// - endpoint: Override Jupiter API endpoint (optional)
/// - insecure: Skip TLS verification (optional, default: false)
///
/// Returns JSON with pool creation transaction
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const creator = mcp.tools.getString(args, "creator") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: creator") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const name = mcp.tools.getString(args, "name") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: name") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const symbol = mcp.tools.getString(args, "symbol") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: symbol") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const uri = mcp.tools.getString(args, "uri") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: uri") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const decimals = mcp.tools.getInteger(args, "decimals") orelse 9;
    const total_supply = mcp.tools.getString(args, "total_supply");

    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse endpoints.jupiter.studio_dbc_create;
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    request_obj.put("creator", .{ .string = creator }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("name", .{ .string = name }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("symbol", .{ .string = symbol }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("uri", .{ .string = uri }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    request_obj.put("decimals", .{ .integer = decimals }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    if (total_supply) |supply| {
        request_obj.put("totalSupply", .{ .string = supply }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(request_body);

    const body = secure_http.securePost(allocator, endpoint_base, request_body, true, insecure) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create DBC pool transaction: {s}", .{@errorName(err)}) catch {
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
        creator: []const u8,
        name: []const u8,
        symbol: []const u8,
        transaction: std.json.Value,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .creator = creator,
        .name = name,
        .symbol = symbol,
        .transaction = parsed.value,
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
