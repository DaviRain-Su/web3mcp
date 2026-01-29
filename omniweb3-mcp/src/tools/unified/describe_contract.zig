const std = @import("std");
const mcp = @import("mcp");
const evm_runtime = @import("../../core/evm_runtime.zig");
const abi_resolver = @import("../../providers/evm/abi_resolver.zig");

/// Generate a concise summary for an EVM contract ABI.
///
/// Parameters:
/// - chain: "bsc" | "ethereum" | "polygon" (required)
/// - contract: Contract name from contracts.json (required)
///
/// Returns JSON with function summaries and common hints.
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: chain") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const contract_name = mcp.tools.getString(args, "contract") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: contract") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const io = evm_runtime.io();
    const abi_path = abi_resolver.resolveAbiPath(allocator, chain_name, contract_name) catch {
        return mcp.tools.errorResult(allocator, "Failed to resolve ABI path") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer allocator.free(abi_path);

    const abi = abi_resolver.loadAbi(allocator, &io, abi_path) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to load ABI: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer {
        // ABI allocator ownership cleanup not implemented in resolver yet
    }

    var view_count: usize = 0;
    var payable_count: usize = 0;
    var nonpayable_count: usize = 0;

    for (abi.functions) |func| {
        switch (func.state_mutability) {
            .view, .pure => view_count += 1,
            .payable => payable_count += 1,
            .nonpayable => nonpayable_count += 1,
        }
    }

    const max_items: usize = 8;
    var functions_list = std.json.Array.init(allocator);
    defer functions_list.deinit();

    for (abi.functions, 0..) |func, idx| {
        if (idx >= max_items) break;
        var sig_buf: [256]u8 = undefined;
        const signature = buildFunctionSignature(allocator, func, &sig_buf) catch "";
        var func_obj = std.json.ObjectMap.init(allocator);
        try func_obj.put("name", .{ .string = func.name });
        try func_obj.put("signature", .{ .string = signature });
        try func_obj.put("state", .{ .string = @tagName(func.state_mutability) });
        try func_obj.put("payable", .{ .bool = func.payable });
        try functions_list.append(.{ .object = func_obj });
    }

    var hints_list = std.json.Array.init(allocator);
    defer hints_list.deinit();
    try hints_list.append(.{ .string = "Use call_contract with function + args array" });
    try hints_list.append(.{ .string = "args must match ABI types in order" });
    try hints_list.append(.{ .string = "For state changes, set send_transaction=true" });

    var result_obj = std.json.ObjectMap.init(allocator);
    defer result_obj.deinit();

    const function_count: i64 = @intCast(abi.functions.len);
    const view_count_i64: i64 = @intCast(view_count);
    const payable_count_i64: i64 = @intCast(payable_count);
    const nonpayable_count_i64: i64 = @intCast(nonpayable_count);

    try result_obj.put("chain", .{ .string = chain_name });
    try result_obj.put("contract", .{ .string = contract_name });
    try result_obj.put("function_count", .{ .integer = function_count });
    try result_obj.put("view_functions", .{ .integer = view_count_i64 });
    try result_obj.put("payable_functions", .{ .integer = payable_count_i64 });
    try result_obj.put("nonpayable_functions", .{ .integer = nonpayable_count_i64 });
    try result_obj.put("top_functions", .{ .array = functions_list });
    try result_obj.put("hints", .{ .array = hints_list });

    const response = std.fmt.allocPrint(
        allocator,
        "{f}",
        .{std.json.fmt(std.json.Value{ .object = result_obj }, .{})},
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(response);

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn buildFunctionSignature(
    allocator: std.mem.Allocator,
    func: abi_resolver.AbiFunction,
    buffer: []u8,
) ![]const u8 {
    var params_list: std.ArrayList(u8) = .empty;
    defer params_list.deinit(allocator);

    for (func.inputs, 0..) |input, i| {
        try params_list.appendSlice(allocator, input.type);
        if (i < func.inputs.len - 1) {
            try params_list.appendSlice(allocator, ",");
        }
    }

    const params = try params_list.toOwnedSlice(allocator);
    defer allocator.free(params);

    return std.fmt.bufPrint(buffer, "{s}({s})", .{ func.name, params });
}
