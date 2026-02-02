//! Grid Trading Strategy Tool
//!
//! Automate grid trading strategy setup by:
//! 1. Calculating optimal price levels (arithmetic or geometric)
//! 2. Determining order amounts for each level
//! 3. Creating all buy and sell orders in batch
//!
//! Grid trading is a strategy where you place buy and sell orders at regular
//! intervals around a target price, profiting from market volatility.
//!
//! Example: SOL/USDC grid
//! - Current price: $100
//! - Range: $80-$120
//! - Grids: 10
//! - Result: Buy orders at $80, $84, $88, $92, $96
//!           Sell orders at $104, $108, $112, $116, $120

const std = @import("std");
const mcp = @import("mcp");
const solana_helpers = @import("../../../core/solana_helpers.zig");
const batch_trigger_orders = @import("../defi/jupiter/batch/batch_trigger_orders.zig");

/// Grid calculation strategy
pub const GridStrategy = enum {
    arithmetic, // Equal price intervals (e.g., 100, 110, 120, 130)
    geometric, // Equal percentage intervals (e.g., 100, 110, 121, 133.1)

    pub fn fromString(s: []const u8) ?GridStrategy {
        if (std.mem.eql(u8, s, "arithmetic")) return .arithmetic;
        if (std.mem.eql(u8, s, "geometric")) return .geometric;
        return null;
    }
};

/// Order side (buy or sell)
const OrderSide = enum { buy, sell };

/// Single grid level with calculated price and amounts
const GridLevel = struct {
    price: f64,
    making_amount: u64, // Amount to sell (in input token units)
    taking_amount: u64, // Amount to receive (in output token units)
    side: OrderSide,
};

/// Create a grid trading strategy.
///
/// This tool automates the entire grid trading setup:
/// 1. Calculates all price levels based on strategy (arithmetic/geometric)
/// 2. Determines order amounts for each level
/// 3. Creates all limit orders via batch_trigger_orders
///
/// Parameters:
/// - input_mint: Base token mint (e.g., SOL) (required)
/// - output_mint: Quote token mint (e.g., USDC) (required)
/// - lower_price: Lower bound of grid range (required)
/// - upper_price: Upper bound of grid range (required)
/// - grid_levels: Number of price levels in the grid (required, 2-20)
/// - total_amount: Total amount to invest in base token units (required)
/// - current_price: Current market price (required for buy/sell split)
/// - strategy: "arithmetic" or "geometric" (optional, default: arithmetic)
/// - wallet_type: "local" or "privy" (required)
/// - wallet_id: Privy wallet ID (required if wallet_type=privy)
/// - keypair_path: Local keypair path (optional, for wallet_type=local)
/// - network: Network - mainnet/devnet (optional, default: mainnet)
/// - sponsor: Enable Privy gas sponsorship (optional, default: false)
/// - endpoint: Override Jupiter API endpoint (optional)
///
/// Returns JSON with grid configuration and order creation results
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

    const lower_price = mcp.tools.getFloat(args, "lower_price") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: lower_price") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const upper_price = mcp.tools.getFloat(args, "upper_price") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: upper_price") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const grid_levels_int = mcp.tools.getInteger(args, "grid_levels") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: grid_levels") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const total_amount = mcp.tools.getFloat(args, "total_amount") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: total_amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const current_price = mcp.tools.getFloat(args, "current_price") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: current_price") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const strategy_str = mcp.tools.getString(args, "strategy") orelse "arithmetic";
    const strategy = GridStrategy.fromString(strategy_str) orelse {
        return mcp.tools.errorResult(allocator, "Invalid strategy. Use 'arithmetic' or 'geometric'") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    // Validate parameters
    if (lower_price <= 0 or upper_price <= 0 or current_price <= 0) {
        return mcp.tools.errorResult(allocator, "Prices must be positive") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (lower_price >= upper_price) {
        return mcp.tools.errorResult(allocator, "lower_price must be less than upper_price") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (current_price < lower_price or current_price > upper_price) {
        return mcp.tools.errorResult(allocator, "current_price must be within grid range") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (grid_levels_int < 2 or grid_levels_int > 20) {
        return mcp.tools.errorResult(allocator, "grid_levels must be between 2 and 20") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    if (total_amount <= 0) {
        return mcp.tools.errorResult(allocator, "total_amount must be positive") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const grid_levels = @as(usize, @intCast(grid_levels_int));

    // === Step 1: Calculate grid levels ===

    std.log.info("Calculating grid: {s} strategy, {d} levels, range {d:.2}-{d:.2}", .{
        strategy_str,
        grid_levels,
        lower_price,
        upper_price,
    });

    var levels: std.ArrayList(GridLevel) = .empty;
    defer levels.deinit(allocator);

    switch (strategy) {
        .arithmetic => {
            // Equal price intervals
            const price_step = (upper_price - lower_price) / @as(f64, @floatFromInt(grid_levels));

            var i: usize = 0;
            while (i <= grid_levels) : (i += 1) {
                const price = lower_price + price_step * @as(f64, @floatFromInt(i));

                // Determine side based on current price
                const side: OrderSide = if (price < current_price) .buy else .sell;

                // Calculate amounts (simplified - equal distribution)
                const amount_per_level = total_amount / @as(f64, @floatFromInt(grid_levels));

                const making_amount: u64 = if (side == .buy)
                    @intFromFloat(amount_per_level * price) // Buying: use quote token
                else
                    @intFromFloat(amount_per_level); // Selling: use base token

                const taking_amount: u64 = if (side == .buy)
                    @intFromFloat(amount_per_level) // Buying: receive base token
                else
                    @intFromFloat(amount_per_level * price); // Selling: receive quote token

                levels.append(allocator, .{
                    .price = price,
                    .making_amount = making_amount,
                    .taking_amount = taking_amount,
                    .side = side,
                }) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            }
        },
        .geometric => {
            // Equal percentage intervals
            const ratio = std.math.pow(f64, upper_price / lower_price, 1.0 / @as(f64, @floatFromInt(grid_levels)));

            var i: usize = 0;
            while (i <= grid_levels) : (i += 1) {
                const price = lower_price * std.math.pow(f64, ratio, @as(f64, @floatFromInt(i)));

                const side: OrderSide = if (price < current_price) .buy else .sell;

                const amount_per_level = total_amount / @as(f64, @floatFromInt(grid_levels));

                const making_amount: u64 = if (side == .buy)
                    @intFromFloat(amount_per_level * price)
                else
                    @intFromFloat(amount_per_level);

                const taking_amount: u64 = if (side == .buy)
                    @intFromFloat(amount_per_level)
                else
                    @intFromFloat(amount_per_level * price);

                levels.append(allocator, .{
                    .price = price,
                    .making_amount = making_amount,
                    .taking_amount = taking_amount,
                    .side = side,
                }) catch {
                    return mcp.tools.ToolError.OutOfMemory;
                };
            }
        },
    }

    // === Step 2: Build orders array for batch creation ===

    var orders_array = std.json.Array.init(allocator);
    defer orders_array.deinit();

    var buy_count: usize = 0;
    var sell_count: usize = 0;

    for (levels.items) |level| {
        var order_obj = std.json.ObjectMap.init(allocator);

        const making_str = std.fmt.allocPrint(allocator, "{d}", .{level.making_amount}) catch {
            order_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(making_str);

        const taking_str = std.fmt.allocPrint(allocator, "{d}", .{level.taking_amount}) catch {
            order_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(taking_str);

        order_obj.put("making_amount", .{ .string = making_str }) catch {
            order_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };
        order_obj.put("taking_amount", .{ .string = taking_str }) catch {
            order_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };

        orders_array.append(.{ .object = order_obj }) catch {
            order_obj.deinit();
            return mcp.tools.ToolError.OutOfMemory;
        };

        if (level.side == .buy) {
            buy_count += 1;
        } else {
            sell_count += 1;
        }
    }

    std.log.info("Grid orders: {d} buy, {d} sell", .{ buy_count, sell_count });

    // === Step 3: Create batch trigger orders ===

    // Build args for batch_trigger_orders
    var batch_args = std.json.ObjectMap.init(allocator);
    defer batch_args.deinit();

    batch_args.put("orders", std.json.Value{ .array = orders_array }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    batch_args.put("input_mint", .{ .string = input_mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    batch_args.put("output_mint", .{ .string = output_mint }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    // Pass through wallet and network parameters
    if (mcp.tools.getString(args, "wallet_type")) |wt| {
        batch_args.put("wallet_type", .{ .string = wt }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (mcp.tools.getString(args, "wallet_id")) |wid| {
        batch_args.put("wallet_id", .{ .string = wid }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (mcp.tools.getString(args, "keypair_path")) |kp| {
        batch_args.put("keypair_path", .{ .string = kp }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (mcp.tools.getString(args, "network")) |net| {
        batch_args.put("network", .{ .string = net }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (mcp.tools.getBoolean(args, "sponsor")) |sp| {
        batch_args.put("sponsor", .{ .bool = sp }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }
    if (mcp.tools.getString(args, "endpoint")) |ep| {
        batch_args.put("endpoint", .{ .string = ep }) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    // Call batch_trigger_orders
    const batch_result = batch_trigger_orders.handle(allocator, std.json.Value{ .object = batch_args }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to create grid orders: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        defer allocator.free(msg);
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    // === Step 4: Build enhanced response with grid info ===

    // Parse batch result
    if (batch_result.content.len == 0) {
        return mcp.tools.errorResult(allocator, "Empty batch result") catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    }

    const batch_content = batch_result.content[0].asText() orelse {
        return mcp.tools.errorResult(allocator, "Batch result is not text") catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const batch_json = std.json.parseFromSlice(std.json.Value, allocator, batch_content, .{}) catch {
        return mcp.tools.errorResult(allocator, "Failed to parse batch result") catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer batch_json.deinit();

    // Build enhanced response
    var response = std.json.ObjectMap.init(allocator);
    defer response.deinit();

    // Grid configuration
    var grid_config = std.json.ObjectMap.init(allocator);
    defer grid_config.deinit();

    grid_config.put("strategy", .{ .string = strategy_str }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("lower_price", .{ .float = lower_price }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("upper_price", .{ .float = upper_price }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("current_price", .{ .float = current_price }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("grid_levels", .{ .integer = grid_levels_int }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("total_amount", .{ .float = total_amount }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("buy_orders", .{ .integer = @intCast(buy_count) }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    grid_config.put("sell_orders", .{ .integer = @intCast(sell_count) }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    response.put("grid_config", std.json.Value{ .object = grid_config }) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    // Add batch result
    response.put("orders_result", batch_json.value) catch {
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
