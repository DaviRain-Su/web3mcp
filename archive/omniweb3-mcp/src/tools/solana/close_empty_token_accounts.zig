const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../core/solana_helpers.zig");
const chain = @import("../../core/chain.zig");
const wallet = @import("../../core/wallet.zig");

const json_rpc = solana_client.json_rpc;
const PublicKey = solana_sdk.PublicKey;
const Keypair = solana_sdk.Keypair;
const AccountMeta = solana_sdk.AccountMeta;
const TransactionBuilder = solana_client.TransactionBuilder;
const InstructionInput = solana_client.transaction.InstructionInput;
const TokenAccountState = solana_sdk.spl.token.Account;
const TOKEN_PROGRAM_ID = solana_sdk.spl.token.instruction.TOKEN_PROGRAM_ID;

const MAX_INSTRUCTIONS: usize = 40;

fn buildCloseInstruction(
    allocator: std.mem.Allocator,
    account: PublicKey,
    owner: PublicKey,
) !InstructionInput {
    const close_ix = solana_sdk.spl.token.instruction.closeAccount(account, owner, owner);

    const accounts = try allocator.alloc(AccountMeta, close_ix.accounts.len);
    errdefer allocator.free(accounts);
    @memcpy(accounts, close_ix.accounts[0..]);

    const data = try allocator.alloc(u8, close_ix.data.len);
    errdefer allocator.free(data);
    @memcpy(data, close_ix.data[0..]);

    return .{
        .program_id = TOKEN_PROGRAM_ID,
        .accounts = accounts,
        .data = data,
    };
}

fn decodeTokenAccountAmount(allocator: std.mem.Allocator, data_b64: []const u8) !?u64 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data_b64) catch return null;
    if (decoded_len < TokenAccountState.SIZE) return null;

    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);

    std.base64.standard.Decoder.decode(decoded, data_b64) catch return null;

    const account_state = TokenAccountState.unpackUnchecked(decoded) catch return null;
    return account_state.amount;
}

/// Close empty SPL token accounts for the configured wallet (Solana-only).
///
/// Parameters:
/// - chain: "solana" (optional, default: solana)
/// - keypair_path: Solana keypair path (optional)
/// - network: devnet/testnet/mainnet/localhost (optional, default: devnet)
/// - endpoint: Override RPC endpoint (optional)
///
/// Returns JSON with closed account count and signature
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    if (!std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const msg = std.fmt.allocPrint(allocator, "Unsupported chain for close_empty_token_accounts: {s}", .{chain_name}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const keypair_path_override = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    const keypair: Keypair = wallet.loadSolanaKeypair(allocator, keypair_path_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to load Solana keypair: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
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

    const owner_pubkey = keypair.pubkey();

    var params_arr = std.json.Array.init(allocator);
    defer params_arr.deinit();

    var owner_buf: [PublicKey.max_base58_len]u8 = undefined;
    const owner_str = owner_pubkey.toBase58(&owner_buf);

    var program_buf: [PublicKey.max_base58_len]u8 = undefined;
    const program_str = TOKEN_PROGRAM_ID.toBase58(&program_buf);

    try params_arr.append(json_rpc.jsonString(owner_str));

    var filter_obj = json_rpc.jsonObject(allocator);
    defer filter_obj.deinit();
    try filter_obj.put("programId", json_rpc.jsonString(program_str));
    try params_arr.append(.{ .object = filter_obj });

    var config_obj = json_rpc.jsonObject(allocator);
    defer config_obj.deinit();
    try config_obj.put("encoding", json_rpc.jsonString("base64"));
    try params_arr.append(.{ .object = config_obj });

    var result = adapter.client.json_rpc.callWithResult(allocator, "getTokenAccountsByOwner", .{ .array = params_arr }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token accounts: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer result.deinit();

    if (result.rpc_error) |rpc_err| {
        const msg = std.fmt.allocPrint(allocator, "RPC error: {s}", .{rpc_err.message}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const value = result.value orelse {
        return mcp.tools.errorResult(allocator, "Missing token accounts result") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    var empty_accounts: std.ArrayList(PublicKey) = .empty;
    defer empty_accounts.deinit(allocator);

    const value_arr = value.object.get("value").?.array;
    for (value_arr.items) |item| {
        const item_obj = item.object;
        const account_obj = item_obj.get("account").?.object;
        const data_arr = account_obj.get("data").?.array;
        const data_b64 = data_arr.items[0].string;

        const amount = decodeTokenAccountAmount(allocator, data_b64) catch null;
        if (amount != null and amount.? == 0) {
            const pubkey_str = item_obj.get("pubkey").?.string;
            const account_pubkey = solana_helpers.parsePublicKey(pubkey_str) catch {
                return mcp.tools.errorResult(allocator, "Invalid token account pubkey") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };
            try empty_accounts.append(allocator, account_pubkey);
        }
    }

    if (empty_accounts.items.len == 0) {
        const Response = struct {
            chain: []const u8,
            closed: usize,
            signature: ?[]const u8 = null,
            network: []const u8,
            endpoint: []const u8,
        };

        const response_value: Response = .{
            .chain = "solana",
            .closed = 0,
            .network = network,
            .endpoint = adapter.endpoint,
        };

        const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(json);

        return mcp.tools.textResult(allocator, json) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const blockhash_result = adapter.getLatestBlockhash() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get latest blockhash: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    var builder = TransactionBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.setFeePayer(owner_pubkey);
    _ = builder.setRecentBlockhash(blockhash_result.blockhash);

    var close_count: usize = 0;
    for (empty_accounts.items) |account_pubkey| {
        if (close_count >= MAX_INSTRUCTIONS) break;

        const instruction = buildCloseInstruction(allocator, account_pubkey, owner_pubkey) catch {
            return mcp.tools.errorResult(allocator, "Failed to build close instruction") catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer allocator.free(instruction.data);
        defer allocator.free(instruction.accounts);

        _ = builder.addInstruction(instruction) catch {
            return mcp.tools.errorResult(allocator, "Failed to add close instruction") catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        close_count += 1;
    }

    var tx = builder.buildSigned(&[_]*const Keypair{&keypair}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to build/sign transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer tx.deinit();

    const serialized = tx.serialize() catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to serialize transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(serialized);

    const signature = adapter.sendTransaction(serialized) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to send transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    var sig_buf: [88]u8 = undefined;
    const sig_str = signature.toBase58(&sig_buf);

    const Response = struct {
        chain: []const u8,
        closed: usize,
        signature: []const u8,
        network: []const u8,
        endpoint: []const u8,
    };

    const response_value: Response = .{
        .chain = "solana",
        .closed = close_count,
        .signature = sig_str,
        .network = network,
        .endpoint = adapter.endpoint,
    };

    const json = solana_helpers.jsonStringifyAlloc(allocator, response_value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json);

    return mcp.tools.textResult(allocator, json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
