use anyhow::{bail, Result};
use rmcp::handler::server::router::prompt::PromptRouter;
use rmcp::handler::server::router::tool::ToolRouter;
use std::sync::Arc;
use sui_sdk::{SuiClient, SuiClientBuilder};

/// Web3MCP Server - provides tools for interacting with chains (Sui, Solana, EVM) via RPC
#[derive(Clone)]
pub struct Web3McpServer {
    pub rpc_url: String,
    pub client: SuiClient,
    pub tool_router: ToolRouter<Self>,
    pub prompt_router: PromptRouter<Self>,

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
            prompt_router: Self::build_prompt_router(),
            solana_idl_cache: Arc::new(crate::utils::solana_idl_cache::SolanaIdlCache::new()),
        })
    }

    /// Best-effort network kind, used for safety gates (e.g., require pending confirmation on mainnet).
    ///
    /// If the server was constructed with `network`, `rpc_url` will usually contain it.
    pub fn resolve_network_kind(&self) -> String {
        let u = self.rpc_url.to_lowercase();
        if u.contains("testnet") {
            return "testnet".to_string();
        }
        if u.contains("devnet") {
            return "devnet".to_string();
        }
        if u.contains("local") || u.contains("127.0.0.1") || u.contains("localhost") {
            return "localnet".to_string();
        }
        "mainnet".to_string()
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
