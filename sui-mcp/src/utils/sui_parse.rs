use crate::SuiMcpServer;
use rmcp::model::*;
use serde_json::Value;
use std::borrow::Cow;
use std::str::FromStr;
use sui_json::SuiJsonValue;
use sui_types::base_types::{ObjectID, SuiAddress};
use sui_types::digests::{CheckpointDigest, TransactionDigest};

impl SuiMcpServer {
    pub fn parse_address(address: &str) -> Result<SuiAddress, ErrorData> {
        SuiAddress::from_str(address).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid Sui address: {}", e)),
            data: None,
        })
    }

    pub fn parse_object_id(object_id: &str) -> Result<ObjectID, ErrorData> {
        ObjectID::from_str(object_id).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid object ID: {}", e)),
            data: None,
        })
    }

    pub fn parse_digest(digest: &str) -> Result<TransactionDigest, ErrorData> {
        TransactionDigest::from_str(digest).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction digest: {}", e)),
            data: None,
        })
    }

    pub fn parse_checkpoint_digest(digest: &str) -> Result<CheckpointDigest, ErrorData> {
        CheckpointDigest::from_str(digest).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid checkpoint digest: {}", e)),
            data: None,
        })
    }

    pub fn parse_addresses(addresses: &[String]) -> Result<Vec<SuiAddress>, ErrorData> {
        addresses
            .iter()
            .map(|addr| Self::parse_address(addr))
            .collect()
    }

    pub fn parse_object_ids(object_ids: &[String]) -> Result<Vec<ObjectID>, ErrorData> {
        object_ids
            .iter()
            .map(|id| Self::parse_object_id(id))
            .collect()
    }

    pub fn parse_json_args(args: &[Value]) -> Result<Vec<SuiJsonValue>, ErrorData> {
        args.iter()
            .map(|value| {
                SuiJsonValue::new(value.clone()).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid Move argument: {}", e)),
                    data: None,
                })
            })
            .collect()
    }
}
