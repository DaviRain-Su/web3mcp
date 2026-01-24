const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const solana_sdk = @import("solana_sdk");
const solana_helpers = @import("../../core/solana_helpers.zig");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");

const EthCall = zabi.types.transactions.EthCall;
const Wei = zabi.types.ethereum.Wei;
const utils = zabi.utils.utils;

/// Get token balance for Solana/EVM.
///
/// Parameters:
/// - chain: "solana" | "ethereum" | "avalanche" | "bnb" (optional, default: solana)
/// - network: Solana: devnet/testnet/mainnet/localhost; EVM: mainnet/sepolia/goerli/fuji/testnet
/// - endpoint: Override RPC endpoint (optional)
/// - token_account: Solana token account (optional)
/// - owner: Solana owner address (optional, requires mint)
/// - mint: Solana mint address (optional, requires owner)
/// - token_address: EVM ERC20 contract address (required for evm)
/// - owner: EVM owner address (required for evm)
///
/// Returns JSON with token balance
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const token_account_str = mcp.tools.getString(args, "token_account");
        const owner_str = mcp.tools.getString(args, "owner");
        const mint_str = mcp.tools.getString(args, "mint");
        const network = mcp.tools.getString(args, "network") orelse "devnet";

        if (token_account_str == null and (owner_str == null or mint_str == null)) {
            return mcp.tools.errorResult(allocator, "Missing required parameter: token_account or owner+mint") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        var token_account_pubkey: solana_sdk.PublicKey = undefined;
        var token_account_owned: ?[]u8 = null;
        defer if (token_account_owned) |value| allocator.free(value);

        if (token_account_str) |value| {
            token_account_pubkey = solana_helpers.parsePublicKey(value) catch {
                return mcp.tools.errorResult(allocator, "Invalid token account address") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };
            token_account_owned = try allocator.dupe(u8, value);
        } else {
            const owner = solana_helpers.parsePublicKey(owner_str.?) catch {
                return mcp.tools.errorResult(allocator, "Invalid owner address") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };
            const mint = solana_helpers.parsePublicKey(mint_str.?) catch {
                return mcp.tools.errorResult(allocator, "Invalid mint address") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };

            const accounts = adapter.getTokenAccountsByOwner(owner, mint) catch |err| {
                const msg = std.fmt.allocPrint(allocator, "Failed to get token accounts: {s}", .{@errorName(err)}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                return mcp.tools.errorResult(allocator, msg) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            };
            defer allocator.free(accounts);

            if (accounts.len == 0) {
                return mcp.tools.errorResult(allocator, "No token accounts found for owner+mint") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            if (accounts.len > 1) {
                return mcp.tools.errorResult(allocator, "Multiple token accounts found; specify token_account") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }

            token_account_pubkey = accounts[0].pubkey;
            var pubkey_buf: [solana_sdk.PublicKey.max_base58_len]u8 = undefined;
            const pubkey_str = token_account_pubkey.toBase58(&pubkey_buf);
            token_account_owned = try allocator.dupe(u8, pubkey_str);
        }

        const balance = adapter.getTokenAccountBalance(token_account_pubkey) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get token balance: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const BalanceResponse = struct {
            chain: []const u8,
            token_account: []const u8,
            amount: []const u8,
            decimals: u8,
            ui_amount: ?f64 = null,
            ui_amount_string: ?[]const u8 = null,
            network: []const u8,
            endpoint: []const u8,
        };

        const response_value: BalanceResponse = .{
            .chain = "solana",
            .token_account = token_account_owned.?,
            .amount = balance.amount,
            .decimals = balance.decimals,
            .ui_amount = balance.ui_amount,
            .ui_amount_string = balance.ui_amount_string,
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

    if (std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "evm")) {
        const network = mcp.tools.getString(args, "network") orelse "mainnet";
        const token_address_str = mcp.tools.getString(args, "token_address") orelse {
            return mcp.tools.errorResult(allocator, "Missing required parameter: token_address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        const owner_str = mcp.tools.getString(args, "owner") orelse {
            return mcp.tools.errorResult(allocator, "Missing required parameter: owner") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const token_address = evm_helpers.parseAddress(token_address_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid token address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        _ = evm_helpers.parseAddress(owner_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid owner address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const owner_hex = if (std.mem.startsWith(u8, owner_str, "0x")) owner_str[2..] else owner_str;
        if (owner_hex.len != 40) {
            return mcp.tools.errorResult(allocator, "Invalid owner address length") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const data_hex = std.fmt.allocPrint(
            allocator,
            "0x70a08231{s}{s}",
            .{ "000000000000000000000000", owner_hex },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(data_hex);

        const data_bytes = evm_helpers.parseHexDataAlloc(allocator, data_hex) catch {
            return mcp.tools.errorResult(allocator, "Invalid calldata hex") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        defer allocator.free(data_bytes);

        var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const call = EthCall{ .london = .{ .to = token_address, .data = data_bytes } };
        const response = adapter.call(call, .{}) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to call token balance: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer response.deinit();

        const balance_raw = utils.bytesToInt(Wei, response.response) catch {
            return mcp.tools.errorResult(allocator, "Failed to decode token balance") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const balance_str = evm_helpers.formatU256(allocator, balance_raw) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(balance_str);

        const response_json = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"{s}\",\"token_address\":\"{s}\",\"owner\":\"{s}\",\"balance_wei\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\"}}",
            .{ chain_name, token_address_str, owner_str, balance_str, network, adapter.endpoint },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        return mcp.tools.textResult(allocator, response_json) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const msg = std.fmt.allocPrint(allocator, "Unsupported chain: {s}", .{chain_name}) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    return mcp.tools.errorResult(allocator, msg) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
