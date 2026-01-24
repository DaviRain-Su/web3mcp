const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");
const solana_sdk = @import("solana_sdk");

const PublicKey = solana_sdk.PublicKey;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.mem.eql(u8, chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}. Only 'solana' is supported.", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const address = mcp.tools.getString(args, "address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    const pubkey = solana_helpers.parsePublicKey(address) catch {
        return mcp.tools.errorResult(allocator, "Invalid Solana address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const info_opt = adapter.getAccountInfo(pubkey) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get account info: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    if (info_opt == null) {
        return mcp.tools.errorResult(allocator, "Account not found") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const info = info_opt.?;

    var owner_buf: [PublicKey.max_base58_len]u8 = undefined;
    const owner_str = info.owner.toBase58(&owner_buf);
    const owner = allocator.dupe(u8, owner_str) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(owner);

    const Response = struct {
        address: []const u8,
        lamports: u64,
        owner: []const u8,
        executable: bool,
        rent_epoch: u64,
        data_base64: []const u8,
        data_len: usize,
        network: []const u8,
        space: ?u64 = null,
    };

    const response_value: Response = .{
        .address = address,
        .lamports = info.lamports,
        .owner = owner,
        .executable = info.executable,
        .rent_epoch = info.rent_epoch,
        .data_base64 = info.data,
        .data_len = info.data.len,
        .network = network,
        .space = info.space,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
