const std = @import("std");
const mcp = @import("mcp");
const solana_client = @import("solana_client");
const solana_sdk = @import("solana_sdk");
const zabi = @import("zabi");
const solana_helpers = @import("../../core/solana_helpers.zig");
const evm_helpers = @import("../../core/evm_helpers.zig");
const evm_runtime = @import("../../core/evm_runtime.zig");
const chain = @import("../../core/chain.zig");
const wallet = @import("../../core/wallet.zig");
const wallet_provider = @import("../../core/wallet_provider.zig");

const PublicKey = solana_sdk.PublicKey;
const Keypair = solana_sdk.Keypair;
const AccountMeta = solana_sdk.AccountMeta;

const TransactionBuilder = solana_client.TransactionBuilder;
const InstructionInput = solana_client.transaction.InstructionInput;
const TransactionTypes = zabi.types.transactions.TransactionTypes;
const Wei = zabi.types.ethereum.Wei;
const TransactionReceipt = zabi.types.transactions.TransactionReceipt;

/// Lamports per SOL
const LAMPORTS_PER_SOL: u64 = 1_000_000_000;

/// System Program ID (all zeros)
const SYSTEM_PROGRAM_ID: [32]u8 = [_]u8{0} ** 32;

/// System Program instruction discriminators
const SystemInstruction = enum(u32) {
    CreateAccount = 0,
    Assign = 1,
    Transfer = 2,
    CreateAccountWithSeed = 3,
    AdvanceNonceAccount = 4,
    WithdrawNonceAccount = 5,
    InitializeNonceAccount = 6,
    AuthorizeNonceAccount = 7,
    Allocate = 8,
    AllocateWithSeed = 9,
    AssignWithSeed = 10,
    TransferWithSeed = 11,
    UpgradeNonceAccount = 12,
};

/// Create a System Program transfer instruction
/// Caller must free the returned data and accounts slices
fn createTransferInstruction(
    allocator: std.mem.Allocator,
    from_pubkey: PublicKey,
    to_pubkey: PublicKey,
    lamports: u64,
) !InstructionInput {
    // Allocate instruction data: 4 bytes discriminator + 8 bytes lamports (little endian)
    const instruction_data = try allocator.alloc(u8, 12);
    errdefer allocator.free(instruction_data);

    // Write discriminator (Transfer = 2)
    std.mem.writeInt(u32, instruction_data[0..4], @intFromEnum(SystemInstruction.Transfer), .little);
    // Write lamports
    std.mem.writeInt(u64, instruction_data[4..12], lamports, .little);

    // Allocate accounts
    const accounts = try allocator.alloc(AccountMeta, 2);
    errdefer allocator.free(accounts);

    accounts[0] = AccountMeta.newWritableSigner(from_pubkey);
    accounts[1] = AccountMeta.newWritable(to_pubkey);

    return .{
        .program_id = PublicKey.from(SYSTEM_PROGRAM_ID),
        .accounts = accounts,
        .data = instruction_data,
    };
}

/// Transfer native tokens on Solana or EVM chains.
///
/// Parameters:
/// - chain: "solana" | "ethereum" | "avalanche" | "bnb" (optional, default: solana)
/// - to_address: Recipient address (base58 for Solana, hex for EVM)
/// - amount: Amount (lamports for Solana, wei for EVM)
/// - network: Solana: devnet/testnet/mainnet/localhost, EVM: mainnet/sepolia/goerli/fuji/testnet
/// - endpoint: Override RPC endpoint (optional)
/// - wallet_type: "local" | "privy" (optional, default: local)
/// - wallet_id: Privy wallet ID (required if wallet_type=privy)
/// - keypair_path: Solana keypair path (optional, for local wallet)
/// - private_key: EVM private key (optional, for local wallet)
/// - tx_type: EVM tx type (eip1559/legacy)
/// - confirmations: EVM confirmations (optional)
/// - sponsor: Enable Privy gas sponsorship (optional, default: false)
///
/// Returns JSON with transaction signature/hash
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_name = mcp.tools.getString(args, "chain") orelse "solana";
    const to_address_str = mcp.tools.getString(args, "to_address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: to_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount_str = mcp.tools.getString(args, "amount");
    const amount_int = mcp.tools.getInteger(args, "amount");
    if (amount_str == null and amount_int == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");

    if (std.ascii.eqlIgnoreCase(chain_name, "solana")) {
        const keypair_path_override = mcp.tools.getString(args, "keypair_path");
        const wallet_id = mcp.tools.getString(args, "wallet_id");
        const wallet_type_str = mcp.tools.getString(args, "wallet_type") orelse if (wallet_id != null) "privy" else "local";
        const sponsor = mcp.tools.getBoolean(args, "sponsor") orelse false;

        const amount = amount_int orelse {
            return mcp.tools.errorResult(allocator, "Missing required parameter: amount (lamports)") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
        if (amount <= 0) {
            return mcp.tools.errorResult(allocator, "Amount must be positive") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const wallet_type = wallet_provider.WalletType.fromString(wallet_type_str) orelse {
            return mcp.tools.errorResult(allocator, "Invalid wallet_type. Use 'local' or 'privy'") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        // Validate Privy configuration
        if (wallet_type == .privy) {
            if (wallet_id == null) {
                return mcp.tools.errorResult(allocator, "wallet_id is required when wallet_type='privy'") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            if (!wallet_provider.isPrivyConfigured()) {
                return mcp.tools.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars.") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
        }

        const to_pubkey = solana_helpers.parsePublicKey(to_address_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid recipient address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const lamports: u64 = @intCast(amount);

        // Initialize Solana adapter for RPC calls
        var adapter = chain.initSolanaAdapter(allocator, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init Solana adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const blockhash_result = adapter.getLatestBlockhash() catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get latest blockhash: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        // Get sender public key based on wallet type
        const wallet_config = wallet_provider.WalletConfig{
            .wallet_type = wallet_type,
            .chain = .solana,
            .keypair_path = keypair_path_override,
            .wallet_id = wallet_id,
            .network = network,
            .sponsor = sponsor,
        };

        const from_str = wallet_provider.getWalletAddress(allocator, wallet_config) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to get wallet address: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer allocator.free(from_str);

        const from_pubkey = solana_helpers.parsePublicKey(from_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid sender address from wallet") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        // Build transaction
        var builder = TransactionBuilder.init(allocator);
        defer builder.deinit();

        _ = builder.setFeePayer(from_pubkey);
        _ = builder.setRecentBlockhash(blockhash_result.blockhash);

        const transfer_ix = createTransferInstruction(allocator, from_pubkey, to_pubkey, lamports) catch {
            return mcp.tools.errorResult(allocator, "Failed to create transfer instruction") catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer allocator.free(transfer_ix.data);
        defer allocator.free(transfer_ix.accounts);

        _ = builder.addInstruction(transfer_ix) catch {
            return mcp.tools.errorResult(allocator, "Failed to add transfer instruction") catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        // Handle signing based on wallet type
        const sig_str: []const u8 = switch (wallet_type) {
            .local => blk: {
                // Local signing
                const sender_keypair = wallet.loadSolanaKeypair(allocator, keypair_path_override) catch |err| {
                    const msg = std.fmt.allocPrint(allocator, "Failed to load keypair: {s}", .{@errorName(err)}) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                    return mcp.tools.errorResult(allocator, msg) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                };

                var tx = builder.buildSigned(&[_]*const Keypair{&sender_keypair}) catch |err| {
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
                break :blk allocator.dupe(u8, signature.toBase58(&sig_buf)) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            },
            .privy => blk: {
                // Privy signing: build unsigned tx, encode as base64, send to Privy
                var tx = builder.build() catch |err| {
                    const msg = std.fmt.allocPrint(allocator, "Failed to build unsigned transaction: {s}", .{@errorName(err)}) catch {
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

                // Encode to base64 for Privy API
                const base64_len = std.base64.standard.Encoder.calcSize(serialized.len);
                const tx_b64 = allocator.alloc(u8, base64_len) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                defer allocator.free(tx_b64);
                _ = std.base64.standard.Encoder.encode(tx_b64, serialized);

                // Sign and send via Privy
                const sign_result = wallet_provider.signAndSendSolanaTransaction(allocator, wallet_config, tx_b64) catch |err| {
                    const msg = std.fmt.allocPrint(allocator, "Privy sign and send failed: {s}", .{@errorName(err)}) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                    return mcp.tools.errorResult(allocator, msg) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                };

                if (sign_result.signature) |sig| {
                    break :blk sig;
                } else {
                    return mcp.tools.errorResult(allocator, "Privy did not return transaction signature") catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                }
            },
        };
        defer allocator.free(sig_str);

        const sol_amount = @as(f64, @floatFromInt(lamports)) / @as(f64, @floatFromInt(LAMPORTS_PER_SOL));

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"solana\",\"signature\":\"{s}\",\"from\":\"{s}\",\"to\":\"{s}\",\"lamports\":{d},\"sol\":{d:.9},\"network\":\"{s}\",\"endpoint\":\"{s}\",\"wallet_type\":\"{s}\"}}",
            .{ sig_str, from_str, to_address_str, lamports, sol_amount, network, adapter.endpoint, wallet_type_str },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        return mcp.tools.textResult(allocator, response) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    if (std.ascii.eqlIgnoreCase(chain_name, "ethereum") or std.ascii.eqlIgnoreCase(chain_name, "avalanche") or std.ascii.eqlIgnoreCase(chain_name, "bnb") or std.ascii.eqlIgnoreCase(chain_name, "bsc") or std.ascii.eqlIgnoreCase(chain_name, "polygon") or std.ascii.eqlIgnoreCase(chain_name, "evm")) {
        const amount_value = if (amount_str) |value| blk: {
            break :blk evm_helpers.parseWeiAmount(value) catch {
                return mcp.tools.errorResult(allocator, "Invalid amount (expected integer wei)") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            };
        } else blk: {
            const value = amount_int.?;
            if (value <= 0) {
                return mcp.tools.errorResult(allocator, "Amount must be positive") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk @as(Wei, @intCast(value));
        };

        const private_key_override = mcp.tools.getString(args, "private_key");
        const keypair_path = mcp.tools.getString(args, "keypair_path");
        const tx_type_str = mcp.tools.getString(args, "tx_type") orelse "eip1559";
        const confirmations_raw = mcp.tools.getInteger(args, "confirmations") orelse 0;
        const confirmations = if (confirmations_raw < 0) 0 else confirmations_raw;

        const to_address = evm_helpers.parseAddress(to_address_str) catch {
            return mcp.tools.errorResult(allocator, "Invalid EVM address") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };
        defer adapter.deinit();

        const private_key = wallet.loadEvmPrivateKey(allocator, private_key_override, keypair_path) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to resolve private key: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const from_address = wallet.deriveEvmAddress(private_key) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to derive EVM address: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const use_legacy = std.ascii.eqlIgnoreCase(tx_type_str, "legacy");
        const tx_type = if (use_legacy) TransactionTypes.legacy else TransactionTypes.london;
        const confirmations_u8: u8 = if (confirmations > std.math.maxInt(u8))
            std.math.maxInt(u8)
        else
            @intCast(confirmations);

        const transfer_result = adapter.sendTransfer(
            private_key,
            from_address,
            to_address,
            amount_value,
            tx_type,
            confirmations_u8,
        ) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Failed to send transaction: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        };

        const hash_hex = std.fmt.bytesToHex(transfer_result.tx_hash, .lower);
        const receipt_info = if (transfer_result.receipt) |receipt| blk: {
            const status = receiptStatus(receipt);
            const block_number = receiptBlockNumber(receipt);

            const status_str = if (status) |value| if (value) "true" else "false" else "null";
            const block_str = if (block_number) |value|
                std.fmt.allocPrint(allocator, "{d}", .{value}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                }
            else
                try allocator.dupe(u8, "null");
            defer allocator.free(block_str);

            break :blk try std.fmt.allocPrint(
                allocator,
                ",\"receipt_status\":{s},\"receipt_block\":{s}",
                .{ status_str, block_str },
            );
        } else blk: {
            break :blk try allocator.dupe(u8, "");
        };
        defer allocator.free(receipt_info);

        const amount_wei_str = evm_helpers.formatU256(allocator, amount_value) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(amount_wei_str);

        const response = std.fmt.allocPrint(
            allocator,
            "{{\"chain\":\"{s}\",\"tx_hash\":\"0x{s}\",\"to\":\"{s}\",\"amount_wei\":\"{s}\",\"tx_type\":\"{s}\",\"network\":\"{s}\",\"endpoint\":\"{s}\"{s}}}",
            .{ chain_name, hash_hex, to_address_str, amount_wei_str, tx_type_str, network, adapter.endpoint, receipt_info },
        ) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        return mcp.tools.textResult(allocator, response) catch {
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

fn receiptStatus(receipt: TransactionReceipt) ?bool {
    return switch (receipt) {
        .legacy => |value| value.status,
        .cancun => |value| value.status,
        .op_receipt => |value| value.status,
        .arbitrum_receipt => |value| value.status,
        .deposit_receipt => |value| value.status,
    };
}

fn receiptBlockNumber(receipt: TransactionReceipt) ?u64 {
    return switch (receipt) {
        .legacy => |value| value.blockNumber,
        .cancun => |value| value.blockNumber,
        .op_receipt => |value| value.blockNumber,
        .arbitrum_receipt => |value| value.blockNumber,
        .deposit_receipt => |value| value.blockNumber,
    };
}
