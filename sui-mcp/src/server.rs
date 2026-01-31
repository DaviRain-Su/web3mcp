use anyhow::{bail, Result};
use rmcp::handler::server::router::tool::ToolRouter;
use sui_sdk::{SuiClient, SuiClientBuilder};

/// Sui MCP Server - provides tools for interacting with the Sui blockchain via RPC
#[derive(Clone)]
pub struct SuiMcpServer {
    pub rpc_url: String,
    pub client: SuiClient,
    pub tool_router: ToolRouter<Self>,
}

impl SuiMcpServer {
    pub async fn new(rpc_url: Option<String>, network: Option<String>) -> Result<Self> {
        let url = Self::resolve_rpc_url(rpc_url, network)?;
        let client = SuiClientBuilder::default().build(&url).await?;
        Ok(Self {
            rpc_url: url,
            client,
            tool_router: Self::tool_router(),
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
