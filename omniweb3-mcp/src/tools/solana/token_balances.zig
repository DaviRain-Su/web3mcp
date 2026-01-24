const std = @import("std");
const mcp = @import("mcp");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");
const wallet = @import("../../core/wallet.zig");

const PublicKey = solana_sdk.PublicKey;

/// Get all SPL token balances for a Solana owner (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - owner: Base58 owner address (optional, default: keypair pubkey)
/// - mint: Base58 mint address (optional, filters results)
/// - network: "devnet" | "testnet" | "mainnet" | "localhost" (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
/// - keypair_path: Optional keypair path (used if owner not provided)
///
/// Returns JSON with SOL balance and token list
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for token_balances: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const owner_str = mcp.tools.getString(args, "owner");
    const mint_str = mcp.tools.getString(args, "mint");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "devnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    var owner_buf: [PublicKey.max_base58_len]u8 = undefined;
    const owner_pubkey: PublicKey = if (owner_str) |value| blk: {
        break :blk solana_helpers.parsePublicKey(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid owner address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
    } else blk: {
        const keypair = wallet.loadSolanaKeypair(allocator, keypair_path) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to load keypair: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        break :blk keypair.pubkey();
    };

    const owner_out = owner_str orelse owner_pubkey.toBase58(&owner_buf);

    const mint = if (mint_str) |value| blk: {
        const mint_pubkey = solana_helpers.parsePublicKey(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid mint address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        break :blk mint_pubkey;
    } else null;

    var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const lamports = adapter.getBalance(owner_pubkey) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get SOL balance: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    const sol = @as(f64, @floatFromInt(lamports)) / 1_000_000_000.0;

    const accounts = adapter.getTokenAccountsByOwner(owner_pubkey, mint) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token accounts: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(accounts);

    const TokenSummary = struct {
        token_account: []const u8,
        mint: ?[]const u8 = null,
        owner: ?[]const u8 = null,
        amount: ?[]const u8 = null,
        decimals: ?u8 = null,
        ui_amount: ?f64 = null,
        ui_amount_string: ?[]const u8 = null,
    };

    const summaries = try allocator.alloc(TokenSummary, accounts.len);
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

        summaries[i] = .{ .token_account = pubkey_owned };

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
            summaries[i].ui_amount = parsed.token_amount.ui_amount;
            if (parsed.token_amount.ui_amount_string) |ui_str| {
                const ui_owned = try allocator.dupe(u8, ui_str);
                try allocated_strings.append(ui_owned);
                summaries[i].ui_amount_string = ui_owned;
            }
        }
    }

    const Response = struct {
        chain: []const u8,
        owner: []const u8,
        sol_lamports: u64,
        sol: f64,
        tokens: []const TokenSummary,
        network: []const u8,
        endpoint: []const u8,
        mint: ?[]const u8 = null,
    };

    const response_value: Response = .{
        .chain = "solana",
        .owner = owner_out,
        .sol_lamports = lamports,
        .sol = sol,
        .tokens = summaries,
        .network = network,
        .endpoint = adapter.endpoint,
        .mint = mint_str,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
