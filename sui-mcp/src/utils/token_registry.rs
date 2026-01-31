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

    /// Resolve an EVM token contract address for a symbol on a given chain.
    ///
    /// Resolution order:
    /// 1) Env var override: EVM_<SYMBOL>_ADDRESS_<chain_id> (e.g. EVM_USDC_ADDRESS_8453)
    /// 2) Built-in defaults (Circle USDC contract addresses)
    pub fn resolve_evm_token_address(symbol: &str, chain_id: u64) -> Option<String> {
        let symbol_upper = symbol.trim().to_uppercase();
        let key = format!("EVM_{}_ADDRESS_{}", symbol_upper, chain_id);
        if let Ok(v) = std::env::var(&key) {
            return Some(v);
        }

        let symbol = symbol.trim().to_lowercase();
        match symbol.as_str() {
            "usdc" => Self::builtin_evm_usdc_address(chain_id).map(|s| s.to_string()),
            "usdt" => Self::builtin_evm_usdt_address(chain_id).map(|s| s.to_string()),
            _ => None,
        }
    }

    fn builtin_evm_usdc_address(chain_id: u64) -> Option<&'static str> {
        // Source: Circle Docs “USDC Contract Addresses”
        // https://developers.circle.com/stablecoins/usdc-contract-addresses
        match chain_id {
            // Ethereum
            1 => Some("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            11155111 => Some("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"),

            // Base
            8453 => Some("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"),
            84532 => Some("0x036CbD53842c5426634e7929541eC2318f3dCF7e"),

            // Arbitrum
            42161 => Some("0xaf88d065e77c8cC2239327C5EDb3A432268e5831"),
            421614 => Some("0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"),

            // OP Mainnet / OP Sepolia
            10 => Some("0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"),
            11155420 => Some("0x5fd84259d66Cd46123540766Be93DFE6D43130D7"),

            // Monad (Circle docs)
            143 => Some("0x754704bc059f8c67012fed69bc8a327a5aafb603"),

            // HyperEVM (Circle docs)
            998 => Some("0xb88339CB7199b77E23DB6E890353E22632Ba630f"),

            _ => None,
        }
    }

    fn builtin_evm_usdt_address(chain_id: u64) -> Option<&'static str> {
        // We only add values when we have a trusted, network-specific source.
        //
        // Kaia (mainnet): user-provided address (needs upstream canonical source to expand further).
        // Chain id source (Kaia Mainnet = 8217): chainid.network
        // https://chainid.network/chains.json
        match chain_id {
            // Kaia Mainnet
            8217 => Some("0xd077a400968890eacc75cdc901f0356c943e4fdb"),

            // Avalanche C-Chain Mainnet
            43114 => Some("0x9702230a8ea53601f5cd2dc00fdbc13d4df4a8c7"),

            // Kava EVM Mainnet
            2222 => Some("0x919c1c267bc06a7039e03fcc2ef738525769109c"),

            // Celo Mainnet
            42220 => Some("0x48065fbbe25f71c9282ddf5e1cd6d6a887483d5e"),

            _ => None,
        }
    }
}
