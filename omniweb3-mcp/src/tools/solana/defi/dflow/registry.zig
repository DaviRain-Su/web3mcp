//! dFlow Swap API tools registry.
//! Docs: https://pond.dflow.net/swap-api-reference/introduction

// Imperative Swap API (precise route control)
pub const get_quote = @import("get_quote.zig");
pub const swap = @import("swap.zig");
pub const swap_instructions = @import("swap_instructions.zig");

// Declarative Swap API (intent-based, deferred routing)
pub const get_intent = @import("get_intent.zig");
pub const submit_intent = @import("submit_intent.zig");

// Order API
pub const get_order = @import("get_order.zig");
pub const get_order_status = @import("get_order_status.zig");

// Token API
pub const get_tokens = @import("get_tokens.zig");
pub const get_tokens_with_decimals = @import("get_tokens_with_decimals.zig");

// Venue API
pub const get_venues = @import("get_venues.zig");

// Prediction Market Swap API
pub const prediction_market_init = @import("prediction_market_init.zig");

// Prediction Market Metadata API
pub const prediction = @import("prediction/registry.zig");
