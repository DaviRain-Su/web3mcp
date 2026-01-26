//! Jupiter Batch Trigger Orders Tool
//!
//! Create multiple limit orders in a single tool call.
//! This is useful for:
//! - Grid trading strategies (multiple buy/sell orders at different prices)
//! - Laddered limit orders (scaling in/out of positions)
//! - Market making (placing orders on both sides)
//!
//! Each order is created independently. If one fails, others continue
//! (unless fail_fast is enabled).

const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../../../core/solana_helpers.zig");
const secure_http = @import("../../../../../core/secure_http.zig");
const wallet_provider = @import("../../../../../core/wallet_provider.zig");
const wallet = @import("../../../../../core/wallet.zig");
const jupiter_helpers = @import("../helpers.zig");

/// Single trigger order request in a batch
const TriggerOrderRequest = struct {
    making_amount: []const u8, // How much input token to sell
    taking_amount: []const u8, // How much output token to receive
    expired_at: ?i64 = null, // Optional expiration timestamp
};

/// Result for a single trigger order in the batch
const TriggerOrderResult = struct {
    index: usize,
    making_amount: []const u8,
    taking_amount: []const u8,
    price: f64, // Calculated price (taking/making)
    success: bool,
    signature: ?[]const u8 = null,
    order_id: ?[]const u8 = null,
    err: ?[]const u8 = null,
};

/// Create multiple Jupiter trigger (limit) orders in a batch.
///
/// Parameters:
/// - orders: Array of order requests [{ making_amount, taking_amount, expired_at? }]
/// - input_mint: Input token mint address (required)
/// - output_mint: Output token mint address (required)
/// - wallet_type: "local" or "privy" (required)
/// - wallet_id: Privy wallet ID (required if wallet_type=privy)
/// - keypair_path: Local keypair path (optional, for wallet_type=local)
/// - network: Network - mainnet/devnet (optional, default: mainnet)
/// - sponsor: Enable Privy gas sponsorship (optional, default: false)
/// - fail_fast: Stop on first error (optional, default: false)
/// - endpoint: Override Jupiter API endpoint (optional)
///
/// Returns JSON with array of results, one per order:
/// {
///   "total": 5,
///   "successful": 4,
///   "failed": 1,
///   "results": [
///     { "index": 0, "making_amount": "...", "taking_amount": "...", "price": 1.5, "success": true, "signature": "...", "order_id": "..." },
///     { "index": 1, "making_amount": "...", "taking_amount": "...", "price": 1.6, "success": false, "error": "..." },
///     ...
///   ]
/// }
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    // === Step 0: Parse and validate parameters ===

    const orders_array_opt = mcp.tools.getArray(args, "orders");

    if (orders_array_opt == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: orders (array)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const orders_array = orders_array_opt.?.items;
    if (orders_array.len == 0) {
        return mcp.tools.errorResult(allocator, "orders array cannot be empty") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (orders_array.len > 20) {
        return mcp.tools.errorResult(allocator, "Maximum 20 orders per batch") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

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

    // Validate and collect order requests
    var order_requests: std.ArrayList(TriggerOrderRequest) = .empty;
    defer order_requests.deinit(allocator);

    for (orders_array) |order_obj| {
        if (order_obj != .object) {
            return mcp.tools.errorResult(allocator, "Each order must be an object with making_amount, taking_amount") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const making_amount = if (order_obj.object.get("making_amount")) |v| blk: {
            if (v == .string) {
                break :blk v.string;
            } else if (v == .number_string) {
                break :blk v.number_string;
            } else if (v == .integer) {
                const amount_str = std.fmt.allocPrint(allocator, "{d}", .{v.integer}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                break :blk amount_str;
            } else {
                return mcp.tools.errorResult(allocator, "making_amount must be a string or number") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
        } else {
            return mcp.tools.errorResult(allocator, "Missing making_amount in order request") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const taking_amount = if (order_obj.object.get("taking_amount")) |v| blk: {
            if (v == .string) {
                break :blk v.string;
            } else if (v == .number_string) {
                break :blk v.number_string;
            } else if (v == .integer) {
                const amount_str = std.fmt.allocPrint(allocator, "{d}", .{v.integer}) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
                break :blk amount_str;
            } else {
                return mcp.tools.errorResult(allocator, "taking_amount must be a string or number") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
        } else {
            return mcp.tools.errorResult(allocator, "Missing taking_amount in order request") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const expired_at = if (order_obj.object.get("expired_at")) |v| blk: {
            if (v == .integer) {
                break :blk @as(?i64, v.integer);
            } else {
                break :blk @as(?i64, null);
            }
        } else null;

        order_requests.append(allocator, .{
            .making_amount = making_amount,
            .taking_amount = taking_amount,
            .expired_at = expired_at,
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
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const sponsor = mcp.tools.getBoolean(args, "sponsor") orelse false;
    const fail_fast = mcp.tools.getBoolean(args, "fail_fast") orelse false;
    const endpoint_base = mcp.tools.getString(args, "endpoint") orelse "https://api.jup.ag/trigger/v1";
    const insecure = mcp.tools.getBoolean(args, "insecure") orelse false;

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

    // === Step 1: Get user's public key (maker address) ===

    const maker = blk: {
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
    defer allocator.free(maker);

    // === Step 2: Create each trigger order ===

    var results: std.ArrayList(TriggerOrderResult) = .empty;
    defer {
        for (results.items) |*result| {
            if (result.signature) |sig| allocator.free(sig);
            if (result.order_id) |oid| allocator.free(oid);
            if (result.err) |e| allocator.free(e);
        }
        results.deinit(allocator);
    }

    var successful: usize = 0;
    var failed: usize = 0;

    for (order_requests.items, 0..) |order_req, i| {
        // Calculate price for display
        const making_f = std.fmt.parseFloat(f64, order_req.making_amount) catch 0.0;
        const taking_f = std.fmt.parseFloat(f64, order_req.taking_amount) catch 0.0;
        const price = if (making_f > 0.0) taking_f / making_f else 0.0;

        std.log.info("Creating trigger order {d}/{d}: making={s}, taking={s}, price={d:.6}", .{
            i + 1,
            order_requests.items.len,
            order_req.making_amount,
            order_req.taking_amount,
            price,
        });

        const result = createTriggerOrder(
            allocator,
            order_req,
            input_mint,
            output_mint,
            maker,
            wallet_type,
            wallet_id,
            keypair_path,
            network,
            sponsor,
            endpoint_base,
            insecure,
        ) catch |err| blk: {
            const error_msg = std.fmt.allocPrint(allocator, "Order creation error: {s}", .{@errorName(err)}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            std.log.err("Order {d} failed: {s}", .{ i, error_msg });

            failed += 1;
            break :blk TriggerOrderResult{
                .index = i,
                .making_amount = order_req.making_amount,
                .taking_amount = order_req.taking_amount,
                .price = price,
                .success = false,
                .err = error_msg,
            };
        };

        results.append(allocator, result) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        if (result.success) {
            successful += 1;
            std.log.info("Order {d} created: {s}", .{ i, result.signature orelse result.order_id orelse "no-id" });
        } else {
            failed += 1;
            std.log.err("Order {d} failed: {s}", .{ i, result.err.? });

            if (fail_fast) {
                std.log.info("fail_fast enabled, stopping after first failure", .{});
                break;
            }
        }

        // Note: Natural spacing via network latency is sufficient
    }

    // === Step 3: Build response ===

    var response = std.json.ObjectMap.init(allocator);
    defer response.deinit();

    response.put("total", .{ .integer = @intCast(order_requests.items.len) }) catch {
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
        result_obj.put("making_amount", .{ .string = result.making_amount }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        result_obj.put("taking_amount", .{ .string = result.taking_amount }) catch {
            result_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        result_obj.put("price", .{ .float = result.price }) catch {
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

        if (result.order_id) |oid| {
            result_obj.put("order_id", .{ .string = oid }) catch {
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

/// Create a single trigger order (internal helper)
fn createTriggerOrder(
    allocator: std.mem.Allocator,
    order_req: TriggerOrderRequest,
    input_mint: []const u8,
    output_mint: []const u8,
    maker: []const u8,
    wallet_type: wallet_provider.WalletType,
    wallet_id: ?[]const u8,
    keypair_path: ?[]const u8,
    network: []const u8,
    sponsor: bool,
    endpoint_base: []const u8,
    insecure: bool,
) !TriggerOrderResult {
    const making_f = std.fmt.parseFloat(f64, order_req.making_amount) catch 0.0;
    const taking_f = std.fmt.parseFloat(f64, order_req.taking_amount) catch 0.0;
    const price = if (making_f > 0.0) taking_f / making_f else 0.0;

    // Step 1: Create order via API
    const create_url = try std.fmt.allocPrint(allocator, "{s}/createOrder", .{endpoint_base});
    defer allocator.free(create_url);

    var request_obj = std.json.ObjectMap.init(allocator);
    defer request_obj.deinit();

    try request_obj.put("inputMint", .{ .string = input_mint });
    try request_obj.put("outputMint", .{ .string = output_mint });
    try request_obj.put("maker", .{ .string = maker });
    try request_obj.put("makingAmount", .{ .string = order_req.making_amount });
    try request_obj.put("takingAmount", .{ .string = order_req.taking_amount });

    if (order_req.expired_at) |exp| {
        try request_obj.put("expiredAt", .{ .integer = exp });
    }

    const request_body = try solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .object = request_obj });
    defer allocator.free(request_body);

    const create_response = secure_http.securePost(allocator, create_url, request_body, true, insecure) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to create order: {s}", .{@errorName(err)});
        return TriggerOrderResult{
            .index = 0,
            .making_amount = order_req.making_amount,
            .taking_amount = order_req.taking_amount,
            .price = price,
            .success = false,
            .err = error_msg,
        };
    };
    defer allocator.free(create_response);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, create_response, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse response: {s}", .{@errorName(err)});
        return TriggerOrderResult{
            .index = 0,
            .making_amount = order_req.making_amount,
            .taking_amount = order_req.taking_amount,
            .price = price,
            .success = false,
            .err = error_msg,
        };
    };
    defer parsed.deinit();

    // Extract transaction from response
    const tx = blk: {
        if (parsed.value == .object) {
            if (parsed.value.object.get("tx")) |tx_val| {
                if (tx_val == .string) {
                    break :blk tx_val.string;
                }
            }
        }
        const error_msg = try allocator.dupe(u8, "No tx in createOrder response");
        return TriggerOrderResult{
            .index = 0,
            .making_amount = order_req.making_amount,
            .taking_amount = order_req.taking_amount,
            .price = price,
            .success = false,
            .err = error_msg,
        };
    };

    // Step 2: Sign and send transaction
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
        tx,
    ) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to sign and send: {s}", .{@errorName(err)});
        return TriggerOrderResult{
            .index = 0,
            .making_amount = order_req.making_amount,
            .taking_amount = order_req.taking_amount,
            .price = price,
            .success = false,
            .err = error_msg,
        };
    };

    const sig = sign_result.signature orelse {
        allocator.free(sign_result.signed_transaction);
        const error_msg = try allocator.dupe(u8, "No signature in sign result");
        return TriggerOrderResult{
            .index = 0,
            .making_amount = order_req.making_amount,
            .taking_amount = order_req.taking_amount,
            .price = price,
            .success = false,
            .err = error_msg,
        };
    };

    const signature_copy = try allocator.dupe(u8, sig);

    // Clean up sign result allocations
    allocator.free(sign_result.signed_transaction);
    allocator.free(sig);

    // Try to extract order ID from response (if available)
    const order_id = blk: {
        if (parsed.value == .object) {
            if (parsed.value.object.get("orderId")) |oid_val| {
                if (oid_val == .string) {
                    break :blk try allocator.dupe(u8, oid_val.string);
                }
            }
        }
        break :blk null;
    };

    return TriggerOrderResult{
        .index = 0,
        .making_amount = order_req.making_amount,
        .taking_amount = order_req.taking_amount,
        .price = price,
        .success = true,
        .signature = signature_copy,
        .order_id = order_id,
    };
}
