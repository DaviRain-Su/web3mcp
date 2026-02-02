//! Jupiter Batch Swap Tool
//!
//! Execute multiple swaps in a single tool call.
//! This is useful for:
//! - Portfolio rebalancing (sell multiple tokens, buy target allocation)
//! - Batch liquidation
//! - Dollar-cost averaging across multiple tokens
//! - Reducing API calls and improving efficiency
//!
//! Unlike single swaps, batch swaps:
//! - Fetch all quotes in parallel
//! - Build and send transactions sequentially (to avoid nonce conflicts)
//! - Return status for each swap
//!
//! Note: Each swap is a separate transaction. Solana transaction size limits
//! prevent combining multiple swaps into a single transaction in most cases.

const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const endpoints = @import("../../../../../core/endpoints.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const wallet_provider = @import("../../../../../core/wallet_provider.zig");
const wallet = @import("../../../../../core/wallet.zig");

/// Single swap request in a batch
const SwapRequest = struct {
    input_mint: []const u8,
    output_mint: []const u8,
    amount: []const u8,
};

/// Result for a single swap in the batch
const SwapResult = struct {
    index: usize,
    input_mint: []const u8,
    output_mint: []const u8,
    amount: []const u8,
    success: bool,
    signature: ?[]const u8 = null,
    err: ?[]const u8 = null,
};

/// Execute multiple Jupiter swaps in a batch.
///
/// Parameters:
/// - swaps: Array of swap requests [{ input_mint, output_mint, amount }]
/// - wallet_type: "local" or "privy" (required)
/// - wallet_id: Privy wallet ID (required if wallet_type=privy)
/// - keypair_path: Local keypair path (optional, for wallet_type=local)
/// - slippage_bps: Slippage tolerance in basis points (optional, default: 50)
/// - network: Network - mainnet/devnet (optional, default: mainnet)
/// - sponsor: Enable Privy gas sponsorship (optional, default: false)
/// - fail_fast: Stop on first error (optional, default: false)
///
/// Returns JSON with array of results, one per swap:
/// {
///   "total": 3,
///   "successful": 2,
///   "failed": 1,
///   "results": [
///     { "index": 0, "input_mint": "...", "output_mint": "...", "amount": "...", "success": true, "signature": "..." },
///     { "index": 1, "input_mint": "...", "output_mint": "...", "amount": "...", "success": false, "error": "..." },
///     ...
///   ]
/// }
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // === Step 0: Parse and validate parameters ===

    const swaps_array_opt = mcp.tools.getArray(args, "swaps");

    if (swaps_array_opt == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: swaps (array)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const swaps_array = swaps_array_opt.?.items;
    if (swaps_array.len == 0) {
        return mcp.tools.errorResult(allocator, "swaps array cannot be empty") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (swaps_array.len > 10) {
        return mcp.tools.errorResult(allocator, "Maximum 10 swaps per batch (current: {d})") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Validate and collect swap requests
    var swap_requests: std.ArrayList(SwapRequest) = .empty;
    defer swap_requests.deinit(allocator);

    for (swaps_array) |swap_obj| {
        if (swap_obj != .object) {
            return mcp.tools.errorResult(allocator, "Each swap must be an object with input_mint, output_mint, amount") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const input_mint = if (swap_obj.object.get("input_mint")) |v| blk: {
            if (v == .string) break :blk v.string else return mcp.tools.errorResult(allocator, "input_mint must be a string") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        } else {
            return mcp.tools.errorResult(allocator, "Missing input_mint in swap request") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const output_mint = if (swap_obj.object.get("output_mint")) |v| blk: {
            if (v == .string) break :blk v.string else return mcp.tools.errorResult(allocator, "output_mint must be a string") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        } else {
            return mcp.tools.errorResult(allocator, "Missing output_mint in swap request") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const amount = if (swap_obj.object.get("amount")) |v| blk: {
            if (v == .string) {
                break :blk v.string;
            } else if (v == .number_string) {
                break :blk v.number_string;
            } else if (v == .integer) {
                const amount_str = std.fmt.allocPrint(allocator, "{d}", .{v.integer}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                // Will be freed when swap_requests is deinited
                break :blk amount_str;
            } else {
                return mcp.tools.errorResult(allocator, "amount must be a string or number") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
        } else {
            return mcp.tools.errorResult(allocator, "Missing amount in swap request") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        swap_requests.append(allocator, .{
            .input_mint = input_mint,
            .output_mint = output_mint,
            .amount = amount,
        }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    // Wallet configuration
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

    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const slippage_bps = mcp.tools.getInteger(args, "slippage_bps") orelse 50;
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const sponsor = mcp.tools.getBoolean(args, "sponsor") orelse false;
    const fail_fast = mcp.tools.getBoolean(args, "fail_fast") orelse false;

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

    // === Step 2: Execute each swap ===

    var results: std.ArrayList(SwapResult) = .empty;
    defer {
        for (results.items) |*result| {
            if (result.signature) |sig| allocator.free(sig);
            if (result.err) |e| allocator.free(e);
        }
        results.deinit(allocator);
    }

    var successful: usize = 0;
    var failed: usize = 0;

    for (swap_requests.items, 0..) |swap_req, i| {
        std.log.info("Executing swap {d}/{d}: {s} -> {s}, amount={s}", .{
            i + 1,
            swap_requests.items.len,
            swap_req.input_mint,
            swap_req.output_mint,
            swap_req.amount,
        });

        const result = executeSwap(
            allocator,
            swap_req,
            user_public_key,
            slippage_bps,
            wallet_type,
            wallet_id,
            keypair_path,
            network,
            sponsor,
        ) catch |err| blk: {
            const error_msg = std.fmt.allocPrint(allocator, "Swap execution error: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            std.log.err("Swap {d} failed: {s}", .{ i, error_msg });

            failed += 1;
            break :blk SwapResult{
                .index = i,
                .input_mint = swap_req.input_mint,
                .output_mint = swap_req.output_mint,
                .amount = swap_req.amount,
                .success = false,
                .err = error_msg,
            };
        };

        results.append(allocator, result) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        if (result.success) {
            successful += 1;
            std.log.info("Swap {d} successful: {s}", .{ i, result.signature.? });
        } else {
            failed += 1;
            std.log.err("Swap {d} failed: {s}", .{ i, result.err.? });

            if (fail_fast) {
                std.log.info("fail_fast enabled, stopping after first failure", .{});
                break;
            }
        }

        // Note: Transactions are executed sequentially to avoid nonce conflicts.
        // The sequential execution and network latency provide natural spacing.
        // Additional delay can be added here if needed for rate limiting.
    }

    // === Step 3: Build response ===

    var response = std.json.ObjectMap.init(allocator);
    defer response.deinit();

    response.put("total", .{ .integer = @intCast(swap_requests.items.len) }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    response.put("successful", .{ .integer = @intCast(successful) }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    response.put("failed", .{ .integer = @intCast(failed) }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    // Build results array
    var results_array = std.json.Array.init(allocator);
    defer results_array.deinit();

    for (results.items) |result| {
        var result_obj = std.json.ObjectMap.init(allocator);

        result_obj.put("index", .{ .integer = @intCast(result.index) }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        result_obj.put("input_mint", .{ .string = result.input_mint }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        result_obj.put("output_mint", .{ .string = result.output_mint }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        result_obj.put("amount", .{ .string = result.amount }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        result_obj.put("success", .{ .bool = result.success }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };

        if (result.signature) |sig| {
            result_obj.put("signature", .{ .string = sig }) catch {
                result_obj.deinit();
                return mcp.tools.ToolError.OutOfMemory;
            };
        }

        if (result.err) |e| {
            result_obj.put("error", .{ .string = e }) catch {
                result_obj.deinit();
                return mcp.tools.ToolError.OutOfMemory;
            };
        }

        results_array.append(.{ .object = result_obj }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    response.put("results", std.json.Value{ .array = results_array }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    const response_json = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = response }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(response_json);

    return mcp.tools.textResult(allocator, response_json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

/// Execute a single swap (internal helper)
fn executeSwap(
    allocator: std.mem.Allocator,
    swap_req: SwapRequest,
    user_public_key: []const u8,
    slippage_bps: i64,
    wallet_type: wallet_provider.WalletType,
    wallet_id: ?[]const u8,
    keypair_path: ?[]const u8,
    network: []const u8,
    sponsor: bool,
) !SwapResult {
    // Step 1: Get quote
    const quote_url = try std.fmt.allocPrint(
        allocator,
        "{s}?inputMint={s}&outputMint={s}&amount={s}&slippageBps={d}",
        .{ endpoints.jupiter.quote, swap_req.input_mint, swap_req.output_mint, swap_req.amount, slippage_bps },
    );
    defer allocator.free(quote_url);

    const quote_response = secure_http.secureGet(allocator, quote_url, true, false) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to get quote: {s}", .{@errorName(err)});
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };
    defer allocator.free(quote_response);

    const parsed_quote = std.json.parseFromSlice(std.json.Value, allocator, quote_response, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse quote: {s}", .{@errorName(err)});
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };
    defer parsed_quote.deinit();

    // Check for error in quote
    if (parsed_quote.value == .object) {
        if (parsed_quote.value.object.get("error")) |_| {
            const error_msg = try std.fmt.allocPrint(allocator, "Jupiter quote error: {s}", .{quote_response});
            return SwapResult{
                .index = 0,
                .input_mint = swap_req.input_mint,
                .output_mint = swap_req.output_mint,
                .amount = swap_req.amount,
                .success = false,
                .err = error_msg,
            };
        }
    }

    // Step 2: Build swap transaction
    var swap_request = std.json.ObjectMap.init(allocator);
    defer swap_request.deinit();

    try swap_request.put("quoteResponse", parsed_quote.value);
    try swap_request.put("userPublicKey", .{ .string = user_public_key });
    try swap_request.put("wrapAndUnwrapSol", .{ .bool = true });
    try swap_request.put("useSharedAccounts", .{ .bool = true });

    const swap_request_body = try solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = swap_request });
    defer allocator.free(swap_request_body);

    const swap_response = secure_http.securePost(allocator, endpoints.jupiter.swap, swap_request_body, true, false) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to build swap tx: {s}", .{@errorName(err)});
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };
    defer allocator.free(swap_response);

    const parsed_swap = std.json.parseFromSlice(std.json.Value, allocator, swap_response, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse swap response: {s}", .{@errorName(err)});
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };
    defer parsed_swap.deinit();

    const swap_transaction = blk: {
        if (parsed_swap.value == .object) {
            if (parsed_swap.value.object.get("swapTransaction")) |tx| {
                if (tx == .string) {
                    break :blk tx.string;
                }
            }
        }
        const error_msg = try allocator.dupe(u8, "No swapTransaction in Jupiter response");
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };

    // Step 3: Sign and send
    const wallet_config = wallet_provider.WalletConfig{
        .wallet_type = wallet_type,
        .chain = .solana,
        .wallet_id = wallet_id,
        .keypair_path = keypair_path,
        .network = network,
        .sponsor = sponsor,
    };

    const sign_result = wallet_provider.signAndSendSolanaTransaction(
        allocator,
        wallet_config,
        swap_transaction,
    ) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to sign and send: {s}", .{@errorName(err)});
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };

    // Sign result always has a signature after send
    const sig = sign_result.signature orelse {
        allocator.free(sign_result.signed_transaction);
        const error_msg = try allocator.dupe(u8, "No signature in sign result");
        return SwapResult{
            .index = 0,
            .input_mint = swap_req.input_mint,
            .output_mint = swap_req.output_mint,
            .amount = swap_req.amount,
            .success = false,
            .err = error_msg,
        };
    };

    const signature_copy = try allocator.dupe(u8, sig);

    // Clean up sign result allocations
    allocator.free(sign_result.signed_transaction);
    allocator.free(sig);

    return SwapResult{
        .index = 0,
        .input_mint = swap_req.input_mint,
        .output_mint = swap_req.output_mint,
        .amount = swap_req.amount,
        .success = true,
        .signature = signature_copy,
    };
}
