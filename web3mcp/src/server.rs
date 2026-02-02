use anyhow::{bail, Result};
use rmcp::handler::server::router::tool::ToolRouter;
use std::sync::Arc;
use sui_sdk::{SuiClient, SuiClientBuilder};

/// Web3MCP Server - provides tools for interacting with chains (Sui, Solana, EVM) via RPC
#[derive(Clone)]
pub struct Web3McpServer {
    pub rpc_url: String,
    pub client: SuiClient,
    pub tool_router: ToolRouter<Self>,

    // In-memory caches
    pub solana_idl_cache: Arc<crate::utils::solana_idl_cache::SolanaIdlCache>,
}

impl Web3McpServer {
    pub async fn new(rpc_url: Option<String>, network: Option<String>) -> Result<Self> {
        let url = Self::resolve_rpc_url(rpc_url, network)?;
        let client = SuiClientBuilder::default().build(&url).await?;
        Ok(Self {
            rpc_url: url,
            client,
            tool_router: Self::tool_router(),
            solana_idl_cache: Arc::new(crate::utils::solana_idl_cache::SolanaIdlCache::new()),
        })
    }

    pub fn resolve_rpc_url(rpc_url: Option<String>, network: Option<String>) -> Result<String> {
        if let Some(url) = rpc_url {
            return Ok(url);
        }

        let network = network.unwrap_or_else(|| "mainnet".to_string());
        let url = match network.as_str() {
            "mainnet" => "https://fullnode.mainnet.sui.io:443",
            "testnet" => "https://fullnode.testnet.sui.io:443",
            "devnet" => "https://fullnode.devnet.sui.io:443",
            "localnet" => "http://127.0.0.1:9000",
            other => bail!("Unsupported network: {}", other),
        };

        Ok(url.to_string())
    }
}
