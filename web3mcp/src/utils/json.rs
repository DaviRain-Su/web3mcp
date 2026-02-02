use crate::Web3McpServer;
use rmcp::model::*;
use serde::Serialize;
use serde_json::json;
use std::borrow::Cow;
use sui_types::transaction::TransactionData;

impl Web3McpServer {
    pub fn pretty_json<T: Serialize>(value: &T) -> Result<String, ErrorData> {
        serde_json::to_string_pretty(value).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize: {}", e)),
            data: None,
        })
    }

    pub fn tx_response(tx_data: &TransactionData) -> Result<String, ErrorData> {
        let payload = json!({
            "tx_bytes": Self::encode_tx_bytes(tx_data)?,
        });
        Self::pretty_json(&payload)
    }
}
