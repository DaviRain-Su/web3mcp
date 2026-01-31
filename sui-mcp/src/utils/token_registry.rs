use crate::SuiMcpServer;

impl SuiMcpServer {
    /// Resolve a Sui coin type from a human token symbol (e.g. "USDC").
    ///
    /// Resolution order:
    /// 1) Environment variables (override)
    /// 2) Built-in defaults (mainnet/testnet)
    ///
    /// Supported env vars:
    /// - SUI_USDC_COIN_TYPE
    /// - SUI_USDT_COIN_TYPE
    pub fn resolve_sui_coin_type(symbol: &str) -> Option<String> {
        let symbol = symbol.trim().to_lowercase();
        match symbol.as_str() {
            "usdc" => std::env::var("SUI_USDC_COIN_TYPE")
                .ok()
                .or_else(|| Some(Self::builtin_sui_usdc_coin_type())),
            "usdt" => std::env::var("SUI_USDT_COIN_TYPE")
                .ok()
                .or_else(|| Self::builtin_sui_usdt_coin_type()),
            _ => None,
        }
    }

    fn builtin_sui_usdc_coin_type() -> String {
        // Source: Circle Docs "USDC Contract Addresses" (preferred)
        // https://developers.circle.com/stablecoins/usdc-contract-addresses
        //
        // Also referenced in Circle blog:
        // https://www.circle.com/blog/now-available-native-usdc-on-sui
        // Mainnet: 0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC
        // Testnet: 0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC
        //
        // We pick based on SUI_NETWORK (mainnet|testnet|devnet) if present, otherwise infer from SUI_RPC_URL.
        let network = std::env::var("SUI_NETWORK")
            .ok()
            .unwrap_or_default()
            .to_lowercase();
        if network.contains("test") {
            return "0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC".to_string();
        }
        if network.contains("dev") {
            // No official Circle USDC devnet address published in the source.
            // Default to mainnet address unless overridden by env.
            return "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC".to_string();
        }

        let rpc = std::env::var("SUI_RPC_URL")
            .ok()
            .unwrap_or_default()
            .to_lowercase();
        if rpc.contains("testnet") {
            return "0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC".to_string();
        }

        "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC".to_string()
    }

    fn builtin_sui_usdt_coin_type() -> Option<String> {
        // No official Circle USDT-on-Sui mapping in our checked sources yet.
        // Keep USDT env-only for now.
        None
    }
}
