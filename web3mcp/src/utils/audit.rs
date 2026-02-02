use crate::Web3McpServer;
use serde_json::{json, Value};
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};

impl Web3McpServer {
    pub fn write_audit_log(&self, tool: &str, entry: Value) {
        // Preferred env var (post-rename): WEB3MCP_AUDIT_LOG
        // Back-compat (pre-rename): SUI_MCP_AUDIT_LOG
        let path = if let Ok(path) = std::env::var("WEB3MCP_AUDIT_LOG") {
            std::path::PathBuf::from(path)
        } else if let Ok(path) = std::env::var("SUI_MCP_AUDIT_LOG") {
            std::path::PathBuf::from(path)
        } else if let Ok(home) = std::env::var("HOME") {
            std::path::PathBuf::from(home)
                .join(".web3mcp")
                .join("audit.log")
        } else {
            return;
        };

        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);

        let record = json!({
            "timestamp_ms": timestamp,
            "tool": tool,
            "entry": entry
        });

        if let Ok(mut file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
        {
            let _ = writeln!(file, "{}", record);
        }
    }
}
