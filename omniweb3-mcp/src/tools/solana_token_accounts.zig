const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");

const RpcClient = solana_client.RpcClient;
const PublicKey = solana_sdk.PublicKey;
const TokenAccount = solana_client.TokenAccount;
const TokenAccountFilter = solana_client.RpcClient.TokenAccountFilter;
const TOKEN_PROGRAM_ID = solana_sdk.spl.token.instruction.TOKEN_PROGRAM_ID;

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.mem.eql(u8, chain, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}. Only 'solana' is supported.", .{chain}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const owner_str = mcp.tools.getString(args, "owner") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: owner") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    const mint_str = mcp.tools.getString(args, "mint");
    const network = mcp.tools.getString(args, "network") orelse "devnet";

    const owner = solana_helpers.parsePublicKey(owner_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid owner address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const filter: TokenAccountFilter = if (mint_str) |mint_value| blk: {
        const mint = solana_helpers.parsePublicKey(mint_value) catch {
            return mcp.tools.errorResult(allocator, "Invalid mint address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk .{ .mint = mint };
    } else blk: {
        break :blk .{ .program_id = TOKEN_PROGRAM_ID };
    };

    const endpoint = solana_helpers.resolveEndpoint(network);
    var client = RpcClient.init(allocator, endpoint);
    defer client.deinit();

    const accounts = client.getTokenAccountsByOwner(owner, filter) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token accounts: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(accounts);

    const TokenAccountSummary = struct {
        pubkey: []const u8,
        mint: ?[]const u8 = null,
        owner: ?[]const u8 = null,
        amount: ?[]const u8 = null,
        decimals: ?u8 = null,
        ui_amount_string: ?[]const u8 = null,
    };

    const summaries = try allocator.alloc(TokenAccountSummary, accounts.len);
    defer allocator.free(summaries);

    var allocated_strings = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (allocated_strings.items) |item| allocator.free(item);
        allocated_strings.deinit();
    }

    for (accounts, 0..) |account, i| {
        var pubkey_buf: [PublicKey.max_base58_len]u8 = undefined;
        const pubkey_str = account.pubkey.toBase58(&pubkey_buf);
        const pubkey_owned = try allocator.dupe(u8, pubkey_str);
        try allocated_strings.append(pubkey_owned);

        summaries[i] = .{ .pubkey = pubkey_owned };

        if (account.parsed) |parsed| {
            const mint_owned = try allocator.dupe(u8, parsed.mint);
            const owner_owned = try allocator.dupe(u8, parsed.owner);
            const amount_owned = try allocator.dupe(u8, parsed.token_amount.amount);
            try allocated_strings.append(mint_owned);
            try allocated_strings.append(owner_owned);
            try allocated_strings.append(amount_owned);

            summaries[i].mint = mint_owned;
            summaries[i].owner = owner_owned;
            summaries[i].amount = amount_owned;
            summaries[i].decimals = parsed.token_amount.decimals;
            if (parsed.token_amount.ui_amount_string) |ui_str| {
                const ui_owned = try allocator.dupe(u8, ui_str);
                try allocated_strings.append(ui_owned);
                summaries[i].ui_amount_string = ui_owned;
            }
        }
    }

    const Response = struct {
        owner: []const u8,
        network: []const u8,
        mint: ?[]const u8 = null,
        accounts: []const TokenAccountSummary,
    };

    const response_value: Response = .{
        .owner = owner_str,
        .network = network,
        .mint = mint_str,
        .accounts = summaries,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
