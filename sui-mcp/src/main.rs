use anyhow::Result;

#[path = "intent/adapters.rs"]
mod intent_adapters;
use base64::engine::general_purpose::STANDARD as Base64Engine;
use base64::Engine;
use fastcrypto_zkp::bn254::zk_login::ZkLoginInputs;
use move_core_types::identifier::Identifier;
use move_core_types::language_storage::{StructTag, TypeTag};
use rmcp::{
    handler::server::wrapper::Parameters, model::*, tool, tool_handler, tool_router, ServerHandler,
    ServiceExt,
};
// (moved) tool request schemas live in src/types.rs
use serde_json::{json, Value};
use std::borrow::Cow;
use std::collections::HashMap;
// (moved) Future used in src/sui/dynamic_fields.rs
// (moved) std::io::Write used in utils/audit.rs
// (moved) Pin used in src/sui/dynamic_fields.rs
use std::str::FromStr;
// (moved) SystemTime/UNIX_EPOCH used in utils/audit.rs
use sui_crypto::simple::SimpleVerifier;
use sui_crypto::Verifier;
use sui_graphql::Client as GraphqlClient;
// (moved) SuiJsonValue parsing in utils/sui_parse.rs
use sui_json_rpc_types::{
    CheckpointId, DryRunTransactionBlockResponse, EventFilter, RPCTransactionRequestParams,
    SuiObjectDataOptions, SuiObjectResponseQuery, SuiTransactionBlockEffectsAPI,
    SuiTransactionBlockResponse, SuiTransactionBlockResponseOptions,
    SuiTransactionBlockResponseQuery, SuiTypeTag, TransactionFilter, ZkLoginIntentScope,
};
use sui_keys::keystore::AccountKeystore;
use sui_rpc::proto::sui::rpc::v2::GetServiceInfoRequest as RpcGetServiceInfoRequest;
use sui_rpc::Client as RpcClient;
// SuiClient is part of SuiMcpServer in src/server.rs
use sui_sdk_types::SimpleSignature;
use sui_types::base_types::{ObjectID, SequenceNumber, SuiAddress};
use sui_types::crypto::{Signature, ToFromBytes};
// (moved) digests parsing in utils/sui_parse.rs
// (moved) dynamic_field helpers in src/sui/dynamic_fields.rs
use sui_types::object::Owner;
use sui_types::programmable_transaction_builder::ProgrammableTransactionBuilder;
use sui_types::signature::GenericSignature;
use sui_types::sui_serde::BigInt;
use sui_types::transaction::{
    CallArg, ObjectArg, Transaction, TransactionData, TransactionDataAPI,
};
use sui_types::zk_login_authenticator::ZkLoginAuthenticator;
use tracing::info;
use tracing_subscriber::EnvFilter;

// SuiMcpServer struct moved to src/server.rs

impl SuiMcpServer {
    // Utilities moved to src/utils/* (json/errors)

    async fn preflight_tx_data(
        &self,
        tx_data: &TransactionData,
    ) -> Result<DryRunTransactionBlockResponse, ErrorData> {
        self.client
            .read_api()
            .dry_run_transaction_block(tx_data.clone())
            .await
            .map_err(|e| Self::sdk_error("preflight_tx", e))
    }

    // Utilities moved to src/utils/errors.rs

    // Utilities moved to src/utils/audit.rs

    // Utilities moved to src/utils/base64.rs

    // Utilities moved to src/utils/sui_parse.rs and src/utils/json.rs

    // Sui tx/object helpers moved to src/sui/tx.rs

    // Dynamic field helpers moved to src/sui/dynamic_fields.rs

    // Move schema/helpers moved to src/move_schema.rs

    fn resolve_network(network: Option<String>) -> String {
        network
            .or_else(|| std::env::var("SUI_NETWORK").ok())
            .unwrap_or_else(|| "mainnet".to_string())
    }

    async fn auto_fill_move_call_internal(
        &self,
        request: &AutoFillMoveCallRequest,
    ) -> Result<AutoFilledMoveCall, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let package = Self::parse_object_id(&request.package)?;
        let limit = 200usize;

        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("auto_fill_move_call", e))?;
        let module = modules.get(&request.module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Module not found: {}", request.module)),
            data: None,
        })?;
        let function_def = module
            .exposed_functions
            .get(&request.function)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Function not found: {}", request.function)),
                data: None,
            })?;

        let options = SuiObjectDataOptions::new().with_type().with_owner();
        let query = SuiObjectResponseQuery::new(None, Some(options));
        let owned = self
            .client
            .read_api()
            .get_owned_objects(sender, Some(query), None, Some(limit))
            .await
            .map_err(|e| Self::sdk_error("auto_fill_move_call", e))?;

        let mut owned_metadata: Vec<(ObjectID, StructTag, Owner)> = Vec::new();
        for item in owned.data {
            if let Some(data) = item.data {
                if let Some(object_type) = data.type_ {
                    if let Ok(struct_tag) = object_type.try_into() {
                        if let Some(owner) = data.owner.clone() {
                            owned_metadata.push((data.object_id, struct_tag, owner));
                        }
                    }
                }
            }
        }

        let mut warnings = Vec::new();
        let mut type_mapping: HashMap<usize, TypeTag> = HashMap::new();
        let mut filled_args = request.arguments.clone();

        for (index, param) in function_def.parameters.iter().enumerate() {
            let (requires_mutable, owner_kinds) = Self::param_requirements(param);
            let preferred_order = if requires_mutable {
                vec!["owned", "shared", "object_owner", "consensus"]
            } else {
                vec!["owned", "immutable", "shared", "object_owner", "consensus"]
            };

            let mut recommended: Option<(ObjectID, StructTag, &Owner)> = None;
            for kind in preferred_order.iter() {
                if let Some(candidate) = owned_metadata.iter().find(|(_, struct_tag, owner)| {
                    Self::match_type_param(
                        param,
                        &TypeTag::Struct(Box::new(struct_tag.clone())),
                        &mut HashMap::<usize, TypeTag>::new(),
                    ) && Self::owner_kind(owner) == *kind
                }) {
                    recommended = Some((candidate.0, candidate.1.clone(), &candidate.2));
                    break;
                }
            }

            if let Some((object_id, struct_tag, _owner)) = recommended {
                if let Some(mapping) = Self::infer_type_args(param, &struct_tag) {
                    let _ = Self::merge_type_args(&mut type_mapping, mapping);
                }

                let needs_fill = filled_args
                    .get(index)
                    .map(Self::is_auto_arg)
                    .unwrap_or(true);
                if needs_fill {
                    if filled_args.len() <= index {
                        filled_args.resize(index + 1, Value::Null);
                    }
                    filled_args[index] = Value::String(object_id.to_string());
                }
            } else if owner_kinds.len() > 0 {
                warnings.push(json!({
                    "index": index,
                    "type": Self::format_move_type(param),
                    "message": "No matching object found for parameter"
                }));
            }
        }

        let type_args = if let Some(args) = request.type_args.clone() {
            args
        } else {
            Self::type_args_from_mapping(&type_mapping, function_def.type_parameters.len())
        };

        let gas = if let Some(gas_budget) = request.gas_budget {
            let gas_price = request.gas_price.unwrap_or(
                self.client
                    .read_api()
                    .get_reference_gas_price()
                    .await
                    .map_err(|e| Self::sdk_error("auto_fill_move_call", e))?,
            );
            let gas_object = if let Some(gas_object_id) = request.gas_object_id.clone() {
                Some(json!({"object_id": gas_object_id}))
            } else {
                let gas_object = self
                    .client
                    .transaction_builder()
                    .select_gas(sender, None, gas_budget, vec![], gas_price)
                    .await
                    .map_err(|e| Self::sdk_error("auto_fill_move_call", e))?;
                Some(json!({
                    "object_id": gas_object.0,
                    "version": gas_object.1,
                    "digest": gas_object.2
                }))
            };

            Some(json!({
                "gas_budget": gas_budget,
                "gas_price": gas_price,
                "gas_object": gas_object
            }))
        } else {
            None
        };

        Ok(AutoFilledMoveCall {
            type_args,
            arguments: filled_args,
            gas_budget: request.gas_budget,
            gas_object_id: request.gas_object_id.clone(),
            gas_price: request.gas_price,
            warnings,
            gas,
        })
    }

    // Move schema/helpers moved to src/move_schema.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move type-arg inference helpers moved to src/move_type_args.rs

    // Dynamic field helpers moved to src/sui/dynamic_fields.rs
}

mod move_schema;
mod move_type_args;
mod server;
mod sui;
mod types;
mod utils;

pub use server::SuiMcpServer;
pub use types::*;

struct AutoFilledMoveCall {
    type_args: Vec<String>,
    arguments: Vec<Value>,
    gas_budget: Option<u64>,
    gas_object_id: Option<String>,
    gas_price: Option<u64>,
    warnings: Vec<Value>,
    gas: Option<Value>,
}

include!(concat!(env!("OUT_DIR"), "/router_impl.rs"));
#[tool_handler]
impl ServerHandler for SuiMcpServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::V_2024_11_05,
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            server_info: Implementation::from_build_env(),
            instructions: Some(
                "A Sui blockchain MCP server providing tools for querying the Sui network. \
                 Use the available tools to get balances, objects, transactions, and other blockchain data."
                    .to_string(),
            ),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    // Get RPC URL or network from environment variable if provided
    let rpc_url = std::env::var("SUI_RPC_URL").ok();
    let network = std::env::var("SUI_NETWORK").ok();

    // Create Sui MCP server
    let server = SuiMcpServer::new(rpc_url, network).await?;

    info!("Starting Sui MCP Server");
    info!("Using RPC URL: {}", server.rpc_url);

    // Serve the MCP server via stdio
    let service = server.serve(rmcp::transport::stdio()).await?;

    info!("Sui MCP Server running and ready to accept requests");

    // Wait for server to finish
    service.waiting().await?;

    Ok(())
}
