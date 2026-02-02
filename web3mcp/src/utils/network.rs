use crate::Web3McpServer;

impl Web3McpServer {
    pub fn resolve_network(network: Option<String>) -> String {
        network
            .or_else(|| std::env::var("SUI_NETWORK").ok())
            .unwrap_or_else(|| "mainnet".to_string())
    }
}
