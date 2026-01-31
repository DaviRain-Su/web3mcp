use crate::SuiMcpServer;

impl SuiMcpServer {
    /// Resolve a Sui coin type from a human token symbol (e.g. "USDC").
    ///
    /// This is intentionally config-driven via environment variables to avoid hard-coding
    /// network-specific coin type addresses in code.
    ///
    /// Supported env vars:
    /// - SUI_USDC_COIN_TYPE
    /// - SUI_USDT_COIN_TYPE
    pub fn resolve_sui_coin_type(symbol: &str) -> Option<String> {
        let symbol = symbol.trim().to_lowercase();
        match symbol.as_str() {
            "usdc" => std::env::var("SUI_USDC_COIN_TYPE").ok(),
            "usdt" => std::env::var("SUI_USDT_COIN_TYPE").ok(),
            _ => None,
        }
    }
}
