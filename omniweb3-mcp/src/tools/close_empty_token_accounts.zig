const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../core/solana_helpers.zig");
const chain = @import("../core/chain.zig");
const wallet = @import("../core/wallet.zig");

const PublicKey = solana_sdk.PublicKey;
const Keypair = solana_sdk.Keypair;
const AccountMeta = solana_sdk.AccountMeta;
const TransactionBuilder = solana_client.TransactionBuilder;
const InstructionInput = solana_client.transaction.InstructionInput;
const TokenAccount = solana_client.types.TokenAccount;
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
    const network = mcp.tools.getString(args, "network") orelse "devnet";
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

    const accounts: []TokenAccount = adapter.getTokenAccountsByOwner(owner_pubkey, null) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get token accounts: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(accounts);

    var empty_accounts: std.ArrayList(PublicKey) = .empty;
    defer empty_accounts.deinit(allocator);

    for (accounts) |account| {
        const amount = decodeTokenAccountAmount(allocator, account.account.data) catch null;
        if (amount != null and amount.? == 0) {
            try empty_accounts.append(allocator, account.pubkey);
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
