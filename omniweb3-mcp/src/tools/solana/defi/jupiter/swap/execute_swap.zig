//! Jupiter Execute Swap Tool
//!
//! One-stop tool that combines:
//! 1. Get quote
//! 2. Build swap transaction
//! 3. Sign and send (via Privy or local wallet)
//!
//! This simplifies the swap flow for AI agents by handling the entire
//! swap lifecycle in a single tool call.

const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const wallet_provider = @import("../../../../../core/wallet_provider.zig");
const wallet = @import("../../../../../core/wallet.zig");

/// Execute a Jupiter swap from quote to on-chain transaction.
///
/// This tool handles the complete swap flow:
/// 1. Fetch quote from Jupiter API
/// 2. Build unsigned swap transaction
/// 3. Sign and send via specified wallet (local or Privy)
///
/// Parameters:
/// - input_mint: Input token mint address (required)
/// - output_mint: Output token mint address (required)
/// - amount: Amount in smallest units (required)
/// - wallet_type: "local" or "privy" (required)
/// - wallet_id: Privy wallet ID (required if wallet_type=privy)
/// - keypair_path: Local keypair path (optional, for wallet_type=local)
/// - slippage_bps: Slippage tolerance in basis points (optional, default: 50)
/// - network: Network - mainnet/devnet (optional, default: mainnet for Jupiter)
/// - sponsor: Enable Privy gas sponsorship (optional, default: false)
///
/// Returns JSON with swap result including transaction signature
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // === Step 0: Parse and validate parameters ===

    const input_mint = mcp.tools.getString(args, "input_mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: input_mint") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const output_mint = mcp.tools.getString(args, "output_mint") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: output_mint") catch {
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

    const amount_value: []const u8 = if (amount_str) |s| s else blk: {
        if (amount_int.? < 0) {
            return mcp.tools.errorResult(allocator, "amount must be non-negative") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        break :blk std.fmt.allocPrint(allocator, "{d}", .{amount_int.?}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer if (amount_str == null) allocator.free(amount_value);

    // Wallet configuration
    const wallet_type_str = mcp.tools.getString(args, "wallet_type") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: wallet_type ('local' or 'privy')") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const wallet_type = wallet_provider.WalletType.fromString(wallet_type_str) orelse {
        return mcp.tools.errorResult(allocator, "Invalid wallet_type. Use 'local' or 'privy'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const wallet_id = mcp.tools.getString(args, "wallet_id");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const slippage_bps = mcp.tools.getInteger(args, "slippage_bps") orelse 50;
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const sponsor = mcp.tools.getBoolean(args, "sponsor") orelse false;

    // Validate wallet configuration
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

    // === Step 1: Get user's public key ===

    const user_public_key = blk: {
        switch (wallet_type) {
            .local => {
                const keypair = wallet.loadSolanaKeypair(allocator, keypair_path) catch |err| {
                    const msg = std.fmt.allocPrint(allocator, "Failed to load keypair: {s}", .{@errorName(err)}) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                    defer allocator.free(msg);
                    return mcp.tools.errorResult(allocator, msg) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                };
                var buf: [44]u8 = undefined;
                const addr = keypair.pubkey().toBase58(&buf);
                break :blk allocator.dupe(u8, addr) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            },
            .privy => {
                // Get address from Privy wallet
                const config = wallet_provider.WalletConfig{
                    .wallet_type = .privy,
                    .chain = .solana,
                    .wallet_id = wallet_id,
                    .network = network,
                };
                break :blk wallet_provider.getWalletAddress(allocator, config) catch |err| {
                    const msg = std.fmt.allocPrint(allocator, "Failed to get Privy wallet address: {s}", .{@errorName(err)}) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                    defer allocator.free(msg);
                    return mcp.tools.errorResult(allocator, msg) catch {
                        return mcp.tools.ToolError.OutOfMemory;
                    };
                };
            },
        }
    };
    defer allocator.free(user_public_key);

    // === Step 2: Get quote from Jupiter ===

    const quote_url = std.fmt.allocPrint(
        allocator,
        "{s}?inputMint={s}&outputMint={s}&amount={s}&slippageBps={d}",
        .{ endpoints.jupiter.quote, input_mint, output_mint, amount_value, slippage_bps },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(quote_url);

    const quote_response = secure_http.secureGet(allocator, quote_url, true, false) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to get Jupiter quote: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(quote_response);

    // Parse quote to verify it's valid
    const parsed_quote = std.json.parseFromSlice(std.json.Value, allocator, quote_response, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse Jupiter quote response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed_quote.deinit();

    // Check for error in quote
    if (parsed_quote.value == .object) {
        if (parsed_quote.value.object.get("error")) |_| {
            const msg = std.fmt.allocPrint(allocator, "Jupiter quote error: {s}", .{quote_response}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            defer allocator.free(msg);
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
        }
    }

    // === Step 3: Build swap transaction ===

    var swap_request = std.json.ObjectMap.init(allocator);
    defer swap_request.deinit();

    swap_request.put("quoteResponse", parsed_quote.value) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    swap_request.put("userPublicKey", .{ .string = user_public_key }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    swap_request.put("wrapAndUnwrapSol", .{ .bool = true }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    swap_request.put("useSharedAccounts", .{ .bool = true }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    const swap_request_body = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = swap_request }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(swap_request_body);

    const swap_response = secure_http.securePost(allocator, endpoints.jupiter.swap, swap_request_body, true, false) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to build swap transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(swap_response);

    // Parse swap response to get transaction
    const parsed_swap = std.json.parseFromSlice(std.json.Value, allocator, swap_response, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse swap response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };
    defer parsed_swap.deinit();

    // Extract swapTransaction (base64)
    const swap_transaction = blk: {
        if (parsed_swap.value == .object) {
            if (parsed_swap.value.object.get("swapTransaction")) |tx| {
                if (tx == .string) {
                    break :blk tx.string;
                }
            }
        }
        return mcp.tools.errorResult(allocator, "No swapTransaction in Jupiter response") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // === Step 4: Sign and send transaction ===

    const wallet_config = wallet_provider.WalletConfig{
        .wallet_type = wallet_type,
        .chain = .solana,
        .keypair_path = keypair_path,
        .wallet_id = wallet_id,
        .network = network,
        .sponsor = sponsor,
    };

    const sign_result = wallet_provider.signAndSendSolanaTransaction(allocator, wallet_config, swap_transaction) catch |err| {
        const error_msg = switch (err) {
            error.LocalSignAndSendNotImplemented => "Local wallet sign+send not yet implemented. Use wallet_type='privy' or sign manually with privy_sign_and_send_transaction.",
            error.MissingWalletId => "wallet_id is required for Privy signing",
            error.ParseError => "Failed to parse Privy API response",
            error.SendFailed => "Transaction send failed",
            error.FetchFailed => "Failed to connect to Privy API",
            else => @errorName(err),
        };
        const msg = std.fmt.allocPrint(allocator, "Sign and send failed: {s}", .{error_msg}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer if (sign_result.signature) |sig| allocator.free(sig);

    // === Step 5: Build response ===

    // Extract output amount from quote for response
    var out_amount: []const u8 = "unknown";
    if (parsed_quote.value == .object) {
        if (parsed_quote.value.object.get("outAmount")) |oa| {
            if (oa == .string) {
                out_amount = oa.string;
            }
        }
    }

    const response = if (sign_result.signature) |sig|
        std.fmt.allocPrint(
            allocator,
            "{{\"success\":true,\"signature\":\"{s}\",\"input_mint\":\"{s}\",\"output_mint\":\"{s}\",\"input_amount\":\"{s}\",\"output_amount\":\"{s}\",\"wallet_type\":\"{s}\",\"network\":\"{s}\"}}",
            .{ sig, input_mint, output_mint, amount_value, out_amount, wallet_type_str, network },
        )
    else
        std.fmt.allocPrint(
            allocator,
            "{{\"success\":false,\"error\":\"No signature returned\",\"input_mint\":\"{s}\",\"output_mint\":\"{s}\"}}",
            .{ input_mint, output_mint },
        );

    const response_str = response catch return mcp.tools.ToolError.OutOfMemory;
    defer allocator.free(response_str);

    return mcp.tools.textResult(allocator, response_str) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
