//! Detect Arbitrage Opportunities Tool
//!
//! Compares prices across multiple DEXs to identify profitable arbitrage opportunities.
//!
//! Use cases:
//! - Arbitrage trading bots
//! - Market analysis
//! - Price efficiency monitoring
//!
//! Example workflow:
//! 1. Query prices from multiple DEXs for the same token pair
//! 2. Tool calculates net profit after fees and slippage
//! 3. Returns sorted list of opportunities by profitability

const std = @import("std");
const mcp = @import("mcp");
const arbitrage = @import("../../core/arbitrage_detector.zig");
const solana_helpers = @import("../../core/solana_helpers.zig");

/// Detect arbitrage opportunities across DEXs.
///
/// Parameters:
/// - chain: Must be "solana" (required)
/// - quotes: Array of price quotes from different DEXs (required, min 2)
///   Each quote must have:
///   - dex: DEX identifier (jupiter, meteora_dlmm, meteora_damm, dflow)
///   - input_mint: Input token mint address
///   - output_mint: Output token mint address
///   - input_amount: Input amount in token units
///   - output_amount: Output amount in token units
///   - price: Price (output per input)
///   - fee_bps: Fee in basis points (100 = 1%)
///   - slippage_bps: Expected slippage in basis points
///   - pool_address: (optional) Pool address
/// - min_profit_pct: Minimum profit percentage to report (optional, default: 0.5)
/// - max_slippage_bps: Maximum acceptable slippage (optional, default: 50)
/// - include_gas_cost: Include gas/transaction costs (optional, default: true)
///
/// Returns: JSON array of arbitrage opportunities sorted by profitability
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain = mcp.tools.getString(args, "chain") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: chain") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    if (!std.mem.eql(u8, chain, "solana")) {
        return mcp.tools.errorResult(allocator, "chain must be 'solana'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Get quotes array
    const quotes_array = mcp.tools.getArray(args, "quotes") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: quotes (array)") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    if (quotes_array.items.len < 2) {
        return mcp.tools.errorResult(allocator, "Need at least 2 quotes to detect arbitrage") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    // Parse configuration
    const min_profit_pct = mcp.tools.getFloat(args, "min_profit_pct") orelse 0.5;
    const max_slippage_bps_int = mcp.tools.getInteger(args, "max_slippage_bps") orelse 50;
    const include_gas_cost = mcp.tools.getBoolean(args, "include_gas_cost") orelse true;

    const config = arbitrage.ArbitrageConfig{
        .min_profit_pct = min_profit_pct,
        .max_slippage_bps = @intCast(max_slippage_bps_int),
        .include_gas_cost = include_gas_cost,
    };

    // Parse quotes
    var quotes: std.ArrayList(arbitrage.DexQuote) = .empty;
    defer quotes.deinit(allocator);

    for (quotes_array.items) |quote_val| {
        if (quote_val != .object) {
            return mcp.tools.errorResult(allocator, "Each quote must be an object") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }

        const quote_obj = quote_val.object;

        const dex_str = if (quote_obj.get("dex")) |v| blk: {
            if (v != .string) {
                return mcp.tools.errorResult(allocator, "quote.dex must be a string") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk v.string;
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.dex") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const dex = arbitrage.DexId.fromString(dex_str) orelse {
            const msg = std.fmt.allocPrint(allocator, "Invalid DEX identifier: {s}", .{dex_str}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            };
            defer allocator.free(msg);
            return mcp.tools.errorResult(allocator, msg) catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const input_mint = if (quote_obj.get("input_mint")) |v| blk: {
            if (v != .string) {
                return mcp.tools.errorResult(allocator, "quote.input_mint must be a string") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk v.string;
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.input_mint") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const output_mint = if (quote_obj.get("output_mint")) |v| blk: {
            if (v != .string) {
                return mcp.tools.errorResult(allocator, "quote.output_mint must be a string") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk v.string;
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.output_mint") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const input_amount = if (quote_obj.get("input_amount")) |v| blk: {
            if (v != .integer) {
                return mcp.tools.errorResult(allocator, "quote.input_amount must be an integer") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk @as(u64, @intCast(v.integer));
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.input_amount") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const output_amount = if (quote_obj.get("output_amount")) |v| blk: {
            if (v != .integer) {
                return mcp.tools.errorResult(allocator, "quote.output_amount must be an integer") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk @as(u64, @intCast(v.integer));
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.output_amount") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const price = if (quote_obj.get("price")) |v| blk: {
            if (v != .float) {
                return mcp.tools.errorResult(allocator, "quote.price must be a float") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk v.float;
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.price") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const fee_bps = if (quote_obj.get("fee_bps")) |v| blk: {
            if (v != .integer) {
                return mcp.tools.errorResult(allocator, "quote.fee_bps must be an integer") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk @as(u16, @intCast(v.integer));
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.fee_bps") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const slippage_bps = if (quote_obj.get("slippage_bps")) |v| blk: {
            if (v != .integer) {
                return mcp.tools.errorResult(allocator, "quote.slippage_bps must be an integer") catch {
                    return mcp.tools.ToolError.InvalidArguments;
                };
            }
            break :blk @as(u16, @intCast(v.integer));
        } else {
            return mcp.tools.errorResult(allocator, "Missing quote.slippage_bps") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };

        const pool_address = if (quote_obj.get("pool_address")) |v| blk: {
            if (v != .string) {
                break :blk null;
            }
            break :blk v.string;
        } else null;

        const quote = arbitrage.DexQuote{
            .dex = dex,
            .input_mint = input_mint,
            .output_mint = output_mint,
            .input_amount = input_amount,
            .output_amount = output_amount,
            .price = price,
            .fee_bps = fee_bps,
            .slippage_bps = slippage_bps,
            .pool_address = pool_address,
        };

        try quotes.append(allocator, quote);
    }

    // Detect opportunities
    var detector = arbitrage.ArbitrageDetector.init(allocator, config);
    defer detector.deinit();

    const opportunities = detector.detectOpportunities(quotes.items) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Arbitrage detection failed: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer allocator.free(opportunities);

    // Build response
    var response_array = std.json.Array.init(allocator);
    defer response_array.deinit();

    for (opportunities) |opp| {
        var opp_obj = std.json.ObjectMap.init(allocator);

        opp_obj.put("buy_dex", .{ .string = opp.buy_dex.toString() }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("buy_price", .{ .float = opp.buy_price }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("sell_dex", .{ .string = opp.sell_dex.toString() }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("sell_price", .{ .float = opp.sell_price }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("net_profit", .{ .float = opp.net_profit }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("profit_percentage", .{ .float = opp.profit_percentage }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("confidence", .{ .float = opp.confidence }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        opp_obj.put("priority", .{ .float = opp.priority }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };

        response_array.append(.{ .object = opp_obj }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const response_json = solana_helpers.jsonStringifyAlloc(allocator, std.json.Value{ .array = response_array }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(response_json);

    return mcp.tools.textResult(allocator, response_json) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
