//! Unified Sign and Send Transaction Tool
//!
//! Signs and sends a transaction using either:
//! - Local keypair (Solana only for now)
//! - Privy embedded wallet (Solana/Ethereum)
//!
//! This tool bridges the gap between tools that return unsigned transactions
//! (like Jupiter swap, dFlow, Meteora) and actual on-chain execution.

const std = @import("std");
const mcp = @import("mcp");
const wallet_provider = @import("../../core/wallet_provider.zig");

/// Sign and send a transaction using the specified wallet provider
///
/// Parameters:
/// - chain: "solana" or "ethereum" (required)
/// - transaction: Base64 encoded unsigned transaction (required)
/// - wallet_type: "local" or "privy" (required)
/// - wallet_id: Privy wallet ID (required if wallet_type=privy)
/// - keypair_path: Path to local keypair (optional, for wallet_type=local)
/// - private_key: EVM private key (optional, for wallet_type=local + ethereum)
/// - network: Network for signing - mainnet/devnet/testnet (optional, default: devnet)
/// - sponsor: Enable gas sponsorship (optional, Privy only, default: false)
///
/// Returns JSON with transaction signature/hash
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // Get chain
    const chain_str = mcp.tools.getString(args, "chain") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: chain") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const chain = wallet_provider.ChainType.fromString(chain_str) orelse {
        return mcp.tools.errorResult(allocator, "Invalid chain. Use 'solana' or 'ethereum'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Get transaction
    const transaction = mcp.tools.getString(args, "transaction") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: transaction (base64 encoded)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Get wallet type
    const wallet_id = mcp.tools.getString(args, "wallet_id");
    const wallet_type_str = mcp.tools.getString(args, "wallet_type") orelse if (wallet_id != null) "privy" else {
        return mcp.tools.errorResult(allocator, "Missing required parameter: wallet_type ('local' or 'privy')") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const wallet_type = wallet_provider.WalletType.fromString(wallet_type_str) orelse {
        return mcp.tools.errorResult(allocator, "Invalid wallet_type. Use 'local' or 'privy'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Get optional parameters
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const private_key = mcp.tools.getString(args, "private_key");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const sponsor = mcp.tools.getBoolean(args, "sponsor") orelse false;

    // Validate wallet configuration
    if (wallet_type == .privy and wallet_id == null) {
        return mcp.tools.errorResult(allocator, "wallet_id is required when wallet_type='privy'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (wallet_type == .privy and !wallet_provider.isPrivyConfigured()) {
        return mcp.tools.errorResult(allocator, "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET environment variables.") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Build wallet config
    const config = wallet_provider.WalletConfig{
        .wallet_type = wallet_type,
        .chain = chain,
        .keypair_path = keypair_path,
        .private_key = private_key,
        .wallet_id = wallet_id,
        .network = network,
        .sponsor = sponsor,
    };

    // Sign and send based on chain
    switch (chain) {
        .solana => {
            const result = wallet_provider.signAndSendSolanaTransaction(allocator, config, transaction) catch |err| {
                const msg = switch (err) {
                    error.MissingWalletId => "wallet_id is required for Privy signing",
                    error.ParseError => "Failed to parse Privy API response",
                    error.SendFailed => "Transaction send failed",
                    error.FetchFailed => "Failed to connect to Privy API",
                    else => @errorName(err),
                };
                const error_msg = std.fmt.allocPrint(allocator, "Sign and send failed: {s}", .{msg}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                defer allocator.free(error_msg);
                return mcp.tools.errorResult(allocator, error_msg) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            };
            defer if (result.signature) |sig| allocator.free(sig);

            // Build response
            const response = if (result.signature) |sig|
                std.fmt.allocPrint(
                    allocator,
                    "{{\"chain\":\"solana\",\"wallet_type\":\"{s}\",\"signature\":\"{s}\",\"sent\":true,\"network\":\"{s}\"}}",
                    .{ wallet_type_str, sig, network },
                )
            else
                std.fmt.allocPrint(
                    allocator,
                    "{{\"chain\":\"solana\",\"wallet_type\":\"{s}\",\"error\":\"No signature returned\",\"sent\":false}}",
                    .{wallet_type_str},
                );

            const response_str = response catch return mcp.tools.ToolError.OutOfMemory;
            defer allocator.free(response_str);

            return mcp.tools.textResult(allocator, response_str) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        },
        .ethereum => {
            // EVM signing will be added later
            return mcp.tools.errorResult(allocator, "EVM sign+send not yet implemented. Use Privy tools directly for EVM transactions.") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        },
    }
}
