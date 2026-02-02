use serde_json::json;

#[derive(Debug, Clone)]
pub struct EvmChainInfo {
    pub chain_id: u64,
    pub name: &'static str,
    pub default_rpc_url: &'static str,
}

pub fn evm_default_chains() -> Vec<EvmChainInfo> {
    vec![
        EvmChainInfo {
            chain_id: 1,
            name: "ethereum",
            default_rpc_url: "https://ethereum-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 11155111,
            name: "sepolia",
            default_rpc_url: "https://ethereum-sepolia-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 8453,
            name: "base",
            default_rpc_url: "https://mainnet.base.org",
        },
        EvmChainInfo {
            chain_id: 84532,
            name: "base-sepolia",
            default_rpc_url: "https://sepolia.base.org",
        },
        EvmChainInfo {
            chain_id: 42161,
            name: "arbitrum-one",
            default_rpc_url: "https://arbitrum-one-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 421614,
            name: "arbitrum-sepolia",
            default_rpc_url: "https://arbitrum-sepolia-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 10,
            name: "optimism",
            default_rpc_url: "https://optimism-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 11155420,
            name: "optimism-sepolia",
            default_rpc_url: "https://optimism-sepolia-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 137,
            name: "polygon-pos",
            default_rpc_url: "https://polygon-bor-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 80002,
            name: "polygon-amoy",
            default_rpc_url: "https://polygon-amoy-bor-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 43114,
            name: "avalanche-c",
            default_rpc_url: "https://avalanche-c-chain-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 43113,
            name: "avalanche-fuji",
            default_rpc_url: "https://avalanche-fuji-c-chain-rpc.publicnode.com",
        },
        EvmChainInfo {
            chain_id: 42220,
            name: "celo",
            default_rpc_url: "https://forno.celo.org",
        },
        EvmChainInfo {
            chain_id: 44787,
            name: "celo-alfajores",
            default_rpc_url: "https://alfajores-forno.celo-testnet.org",
        },
        EvmChainInfo {
            chain_id: 2222,
            name: "kava",
            default_rpc_url: "https://evm.kava.io",
        },
        EvmChainInfo {
            chain_id: 2221,
            name: "kava-testnet",
            default_rpc_url: "https://evm.testnet.kava.io",
        },
        EvmChainInfo {
            chain_id: 480,
            name: "worldchain",
            default_rpc_url: "https://worldchain-mainnet.g.alchemy.com/public",
        },
        EvmChainInfo {
            chain_id: 4801,
            name: "worldchain-sepolia",
            default_rpc_url: "https://worldchain-sepolia.g.alchemy.com/public",
        },
        EvmChainInfo {
            chain_id: 143,
            name: "monad",
            default_rpc_url: "https://rpc.monad.xyz",
        },
        EvmChainInfo {
            chain_id: 10143,
            name: "monad-testnet",
            default_rpc_url: "https://testnet-rpc.monad.xyz",
        },
        EvmChainInfo {
            chain_id: 8217,
            name: "kaia",
            default_rpc_url: "https://public-en.node.kaia.io",
        },
        EvmChainInfo {
            chain_id: 1001,
            name: "kaia-kairos",
            default_rpc_url: "https://public-en-kairos.node.kaia.io",
        },
        EvmChainInfo {
            chain_id: 998,
            name: "hyperevm-testnet",
            default_rpc_url: "https://api.hyperliquid-testnet.xyz/evm",
        },
    ]
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
                "rpc_url_effective": env_override.clone().unwrap_or_else(|| c.default_rpc_url.to_string())
            })
        })
        .collect::<Vec<_>>();

    json!({"chains": items})
}
