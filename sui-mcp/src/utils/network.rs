use crate::SuiMcpServer;

impl SuiMcpServer {
    pub fn resolve_network(network: Option<String>) -> String {
        network
            .or_else(|| std::env::var("SUI_NETWORK").ok())
            .unwrap_or_else(|| "mainnet".to_string())
    }
}
