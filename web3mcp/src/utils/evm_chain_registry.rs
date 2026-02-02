use serde_json::json;

#[derive(Debug, Clone)]
pub struct EvmChainInfo {
    pub chain_id: u64,
    pub name: &'static str,
    pub default_rpc_url: &'static str,
    pub explorer_base: Option<&'static str>,
    pub confirmations: u64,
}

pub fn evm_default_chains() -> Vec<EvmChainInfo> {
    // confirmations here means "how many blocks deep before we treat as settled".
    // It's a conservative default; clients can still apply their own policy.
    vec![
        EvmChainInfo {
            chain_id: 1,
            name: "ethereum",
            default_rpc_url: "https://ethereum-rpc.publicnode.com",
            explorer_base: Some("https://etherscan.io"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 11155111,
            name: "sepolia",
            default_rpc_url: "https://ethereum-sepolia-rpc.publicnode.com",
            explorer_base: Some("https://sepolia.etherscan.io"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 8453,
            name: "base",
            default_rpc_url: "https://mainnet.base.org",
            explorer_base: Some("https://basescan.org"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 84532,
            name: "base-sepolia",
            default_rpc_url: "https://sepolia.base.org",
            explorer_base: Some("https://sepolia.basescan.org"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 42161,
            name: "arbitrum-one",
            default_rpc_url: "https://arbitrum-one-rpc.publicnode.com",
            explorer_base: Some("https://arbiscan.io"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 421614,
            name: "arbitrum-sepolia",
            default_rpc_url: "https://arbitrum-sepolia-rpc.publicnode.com",
            explorer_base: Some("https://sepolia.arbiscan.io"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 56,
            name: "bsc",
            default_rpc_url: "https://bsc-rpc.publicnode.com",
            explorer_base: Some("https://bscscan.com"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 97,
            name: "bsc-testnet",
            default_rpc_url: "https://bsc-testnet-rpc.publicnode.com",
            explorer_base: Some("https://testnet.bscscan.com"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 10,
            name: "optimism",
            default_rpc_url: "https://optimism-rpc.publicnode.com",
            explorer_base: Some("https://optimistic.etherscan.io"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 11155420,
            name: "optimism-sepolia",
            default_rpc_url: "https://optimism-sepolia-rpc.publicnode.com",
            explorer_base: Some("https://sepolia-optimism.etherscan.io"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 137,
            name: "polygon-pos",
            default_rpc_url: "https://polygon-bor-rpc.publicnode.com",
            explorer_base: Some("https://polygonscan.com"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 80002,
            name: "polygon-amoy",
            default_rpc_url: "https://polygon-amoy-bor-rpc.publicnode.com",
            explorer_base: Some("https://amoy.polygonscan.com"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 43114,
            name: "avalanche-c",
            default_rpc_url: "https://avalanche-c-chain-rpc.publicnode.com",
            explorer_base: Some("https://snowtrace.io"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 43113,
            name: "avalanche-fuji",
            default_rpc_url: "https://avalanche-fuji-c-chain-rpc.publicnode.com",
            explorer_base: Some("https://testnet.snowtrace.io"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 42220,
            name: "celo",
            default_rpc_url: "https://forno.celo.org",
            explorer_base: Some("https://celoscan.io"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 44787,
            name: "celo-alfajores",
            default_rpc_url: "https://alfajores-forno.celo-testnet.org",
            explorer_base: Some("https://alfajores.celoscan.io"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 2222,
            name: "kava",
            default_rpc_url: "https://evm.kava.io",
            explorer_base: Some("https://kavascan.com"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 2221,
            name: "kava-testnet",
            default_rpc_url: "https://evm.testnet.kava.io",
            explorer_base: None,
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 480,
            name: "worldchain",
            default_rpc_url: "https://worldchain-mainnet.g.alchemy.com/public",
            explorer_base: None,
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 4801,
            name: "worldchain-sepolia",
            default_rpc_url: "https://worldchain-sepolia.g.alchemy.com/public",
            explorer_base: None,
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 143,
            name: "monad",
            default_rpc_url: "https://rpc.monad.xyz",
            explorer_base: None,
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 10143,
            name: "monad-testnet",
            default_rpc_url: "https://testnet-rpc.monad.xyz",
            explorer_base: None,
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 8217,
            name: "kaia",
            default_rpc_url: "https://public-en.node.kaia.io",
            explorer_base: Some("https://scope.klaytn.com"),
            confirmations: 3,
        },
        EvmChainInfo {
            chain_id: 1001,
            name: "kaia-kairos",
            default_rpc_url: "https://public-en-kairos.node.kaia.io",
            explorer_base: Some("https://baobab.scope.klaytn.com"),
            confirmations: 2,
        },
        EvmChainInfo {
            chain_id: 998,
            name: "hyperevm-testnet",
            default_rpc_url: "https://api.hyperliquid-testnet.xyz/evm",
            explorer_base: None,
            confirmations: 2,
        },
    ]
}

pub fn explorer_tx_url(chain_id: u64, tx_hash: &str) -> Option<String> {
    let tx_hash = tx_hash.trim();
    let tx_hash = tx_hash.strip_prefix("0x").unwrap_or(tx_hash);
    let base = evm_default_chains()
        .into_iter()
        .find(|c| c.chain_id == chain_id)
        .and_then(|c| c.explorer_base)?;
    Some(format!("{}/tx/0x{}", base.trim_end_matches('/'), tx_hash))
}

pub fn explorer_address_url(chain_id: u64, address: &str) -> Option<String> {
    let address = address.trim();
    let address = address.strip_prefix("0x").unwrap_or(address);
    let base = evm_default_chains()
        .into_iter()
        .find(|c| c.chain_id == chain_id)
        .and_then(|c| c.explorer_base)?;
    Some(format!(
        "{}/address/0x{}",
        base.trim_end_matches('/'),
        address
    ))
}

pub fn confirmations_for_chain(chain_id: u64) -> Option<u64> {
    evm_default_chains()
        .into_iter()
        .find(|c| c.chain_id == chain_id)
        .map(|c| c.confirmations)
}

pub fn evm_chain_list_json() -> serde_json::Value {
    let items = evm_default_chains()
        .into_iter()
        .map(|c| {
            let env_key = format!("EVM_RPC_URL_{}", c.chain_id);
            let env_override = std::env::var(&env_key).ok();
            json!({
                "chain_id": c.chain_id,
                "name": c.name,
                "default_rpc_url": c.default_rpc_url,
                "env_key": env_key,
                "env_override": env_override,
                "rpc_url_effective": env_override.clone().unwrap_or_else(|| c.default_rpc_url.to_string()),
                "explorer_base": c.explorer_base,
                "confirmations": c.confirmations
            })
        })
        .collect::<Vec<_>>();

    json!({"chains": items})
}
