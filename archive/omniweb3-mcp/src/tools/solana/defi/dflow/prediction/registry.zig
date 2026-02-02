//! dFlow Prediction Market Metadata API tools registry.
//! Docs: https://pond.dflow.net/prediction-market-metadata-api-reference/introduction

// Events API
pub const get_events = @import("get_events.zig");
pub const get_event = @import("get_event.zig");

// Markets API
pub const get_markets = @import("get_markets.zig");
pub const get_market = @import("get_market.zig");
pub const get_market_by_mint = @import("get_market_by_mint.zig");
pub const get_outcome_mints = @import("get_outcome_mints.zig");

// Orderbook API
pub const get_orderbook = @import("get_orderbook.zig");
pub const get_orderbook_by_mint = @import("get_orderbook_by_mint.zig");

// Trades API
pub const get_trades = @import("get_trades.zig");

// Live Data API
pub const get_live_data = @import("get_live_data.zig");

// Series API
pub const get_series = @import("get_series.zig");

// Search API
pub const search_events = @import("search_events.zig");
