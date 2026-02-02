//! Arbitrage Detection Engine
//!
//! Identifies profitable arbitrage opportunities across multiple DEXs.
//!
//! Strategy:
//! 1. Query prices from multiple DEXs (Jupiter, Meteora, dFlow)
//! 2. Calculate net profit after fees and slippage
//! 3. Filter opportunities by minimum profit threshold
//! 4. Sort by profitability
//!
//! Example:
//! - DEX A: SOL/USDC = 100 USDC
//! - DEX B: SOL/USDC = 102 USDC
//! - Opportunity: Buy on A, sell on B = 2% profit (minus fees)

const std = @import("std");

/// DEX identifier
pub const DexId = enum {
    jupiter,
    meteora_dlmm,
    meteora_damm,
    dflow,
    orca,
    raydium,

    pub fn fromString(s: []const u8) ?DexId {
        if (std.mem.eql(u8, s, "jupiter")) return .jupiter;
        if (std.mem.eql(u8, s, "meteora_dlmm")) return .meteora_dlmm;
        if (std.mem.eql(u8, s, "meteora_damm")) return .meteora_damm;
        if (std.mem.eql(u8, s, "dflow")) return .dflow;
        if (std.mem.eql(u8, s, "orca")) return .orca;
        if (std.mem.eql(u8, s, "raydium")) return .raydium;
        return null;
    }

    pub fn toString(self: DexId) []const u8 {
        return switch (self) {
            .jupiter => "jupiter",
            .meteora_dlmm => "meteora_dlmm",
            .meteora_damm => "meteora_damm",
            .dflow => "dflow",
            .orca => "orca",
            .raydium => "raydium",
        };
    }
};

/// Price quote from a DEX
pub const DexQuote = struct {
    dex: DexId,
    input_mint: []const u8,
    output_mint: []const u8,
    input_amount: u64,
    output_amount: u64,
    price: f64, // output per input
    fee_bps: u16, // Basis points (100 = 1%)
    slippage_bps: u16, // Expected slippage in basis points
    pool_address: ?[]const u8 = null,
    route_info: ?[]const u8 = null,
};

/// Arbitrage opportunity
pub const ArbitrageOpportunity = struct {
    /// Buy from this DEX (lower price)
    buy_dex: DexId,
    buy_price: f64,
    buy_output: u64,
    buy_pool: ?[]const u8,

    /// Sell to this DEX (higher price)
    sell_dex: DexId,
    sell_price: f64,
    sell_output: u64,
    sell_pool: ?[]const u8,

    /// Token pair
    input_mint: []const u8,
    output_mint: []const u8,
    amount: u64,

    /// Profit calculation
    gross_profit: f64, // Before fees
    total_fees: f64, // Combined fees from both DEXs
    net_profit: f64, // After fees and slippage
    profit_percentage: f64, // Net profit as percentage

    /// Execution priority (higher = more urgent)
    priority: f64,

    /// Confidence score (0.0 - 1.0)
    confidence: f64,
};

/// Arbitrage detection configuration
pub const ArbitrageConfig = struct {
    /// Minimum profit percentage to consider (e.g., 0.5 = 0.5%)
    min_profit_pct: f64 = 0.5,

    /// Maximum acceptable slippage in basis points (default: 50 = 0.5%)
    max_slippage_bps: u16 = 50,

    /// Include gas/transaction costs in calculation
    include_gas_cost: bool = true,

    /// Estimated gas cost in lamports (default: 0.001 SOL = 1_000_000 lamports)
    gas_cost_lamports: u64 = 1_000_000,
};

/// Arbitrage detector
pub const ArbitrageDetector = struct {
    allocator: std.mem.Allocator,
    config: ArbitrageConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ArbitrageConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // No cleanup needed for now
    }

    /// Detect arbitrage opportunities from a list of quotes
    pub fn detectOpportunities(
        self: *Self,
        quotes: []const DexQuote,
    ) ![]ArbitrageOpportunity {
        if (quotes.len < 2) {
            return &.{}; // Need at least 2 quotes to compare
        }

        var opportunities: std.ArrayList(ArbitrageOpportunity) = .empty;
        errdefer opportunities.deinit(self.allocator);

        // Compare all pairs of quotes
        for (quotes, 0..) |buy_quote, i| {
            for (quotes[i + 1 ..]) |sell_quote| {
                // Must be same token pair (or reverse)
                const same_pair = std.mem.eql(u8, buy_quote.input_mint, sell_quote.input_mint) and
                    std.mem.eql(u8, buy_quote.output_mint, sell_quote.output_mint);

                if (!same_pair) continue;

                // Calculate if profitable
                if (try self.calculateArbitrage(buy_quote, sell_quote)) |opportunity| {
                    if (opportunity.net_profit > 0 and
                        opportunity.profit_percentage >= self.config.min_profit_pct)
                    {
                        try opportunities.append(self.allocator, opportunity);
                    }
                }

                // Also check reverse direction
                if (try self.calculateArbitrage(sell_quote, buy_quote)) |opportunity| {
                    if (opportunity.net_profit > 0 and
                        opportunity.profit_percentage >= self.config.min_profit_pct)
                    {
                        try opportunities.append(self.allocator, opportunity);
                    }
                }
            }
        }

        // Sort by profitability (descending)
        const items = try opportunities.toOwnedSlice(self.allocator);
        std.mem.sort(ArbitrageOpportunity, items, {}, compareOpportunities);

        return items;
    }

    /// Calculate arbitrage profit between two quotes
    fn calculateArbitrage(
        self: *Self,
        buy_quote: DexQuote,
        sell_quote: DexQuote,
    ) !?ArbitrageOpportunity {
        // For same-direction quotes (e.g., both SOL->USDC):
        // Strategy: USDC -> SOL (reverse of buy_quote) -> USDC (sell_quote)
        //
        // Example:
        // buy_quote: 1 SOL -> 100 USDC (price = 100 USDC/SOL)
        // sell_quote: 1 SOL -> 102 USDC (price = 102 USDC/SOL)
        //
        // Arbitrage:
        // 1. Use 100 USDC to buy 1 SOL (reverse of buy_quote)
        // 2. Sell 1 SOL for 102 USDC (sell_quote)
        // 3. Profit = 102 - 100 = 2 USDC

        const buy_output = @as(f64, @floatFromInt(buy_quote.output_amount));
        const sell_output = @as(f64, @floatFromInt(sell_quote.output_amount));

        // Gross profit: difference in output amounts
        const gross_profit = sell_output - buy_output;
        if (gross_profit <= 0) return null; // No profit

        // Calculate total fees (as percentage of amounts)
        const buy_fee = buy_output * @as(f64, @floatFromInt(buy_quote.fee_bps)) / 10000.0;
        const sell_fee = sell_output * @as(f64, @floatFromInt(sell_quote.fee_bps)) / 10000.0;
        var total_fees = buy_fee + sell_fee;

        // Add gas cost if enabled (convert lamports to output token units)
        // Note: This is simplified - in reality, gas cost depends on token price
        if (self.config.include_gas_cost) {
            const gas_cost = @as(f64, @floatFromInt(self.config.gas_cost_lamports)) / 1e9;
            // Assume gas cost in output token units (simplified)
            total_fees += gas_cost * buy_quote.price;
        }

        // Calculate net profit
        const net_profit = gross_profit - total_fees;
        if (net_profit <= 0) return null; // No profit after fees

        // Calculate profit percentage (relative to initial investment)
        const initial_investment = buy_output; // Amount needed to start arbitrage
        const profit_percentage = (net_profit / initial_investment) * 100.0;

        // Calculate priority score (higher profit + lower slippage = higher priority)
        const slippage_penalty = @as(f64, @floatFromInt(buy_quote.slippage_bps + sell_quote.slippage_bps)) / 10000.0;
        const priority = profit_percentage / (1.0 + slippage_penalty);

        // Calculate confidence score (based on slippage and liquidity)
        const max_slippage = @max(buy_quote.slippage_bps, sell_quote.slippage_bps);
        const confidence = if (max_slippage <= self.config.max_slippage_bps)
            1.0 - (@as(f64, @floatFromInt(max_slippage)) / @as(f64, @floatFromInt(self.config.max_slippage_bps)))
        else
            0.0;

        return ArbitrageOpportunity{
            .buy_dex = buy_quote.dex,
            .buy_price = buy_quote.price,
            .buy_output = buy_quote.output_amount,
            .buy_pool = buy_quote.pool_address,
            .sell_dex = sell_quote.dex,
            .sell_price = sell_quote.price,
            .sell_output = sell_quote.output_amount,
            .sell_pool = sell_quote.pool_address,
            .input_mint = buy_quote.input_mint,
            .output_mint = buy_quote.output_mint,
            .amount = buy_quote.input_amount,
            .gross_profit = gross_profit,
            .total_fees = total_fees,
            .net_profit = net_profit,
            .profit_percentage = profit_percentage,
            .priority = priority,
            .confidence = confidence,
        };
    }
};

/// Compare opportunities by priority (descending)
fn compareOpportunities(_: void, a: ArbitrageOpportunity, b: ArbitrageOpportunity) bool {
    return a.priority > b.priority;
}
