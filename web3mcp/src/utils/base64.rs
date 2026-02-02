use crate::Web3McpServer;
use base64::engine::general_purpose::STANDARD as Base64Engine;
use base64::Engine;
use rmcp::model::*;
use std::borrow::Cow;
use sui_types::transaction::TransactionData;

impl Web3McpServer {
    pub fn decode_base64(label: &str, value: &str) -> Result<Vec<u8>, ErrorData> {
        Base64Engine.decode(value).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid base64 for {}: {}", label, e)),
            data: None,
        })
    }

    pub fn encode_tx_bytes(tx_data: &TransactionData) -> Result<String, ErrorData> {
        let bytes = bcs::to_bytes(tx_data).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        Ok(Base64Engine.encode(bytes))
    }
}
