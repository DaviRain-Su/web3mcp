use anyhow::{bail, Result};

#[path = "intent/adapters.rs"]
mod intent_adapters;
use base64::engine::general_purpose::STANDARD as Base64Engine;
use base64::Engine;
use fastcrypto_zkp::bn254::zk_login::ZkLoginInputs;
use move_core_types::identifier::Identifier;
use move_core_types::language_storage::{StructTag, TypeTag};
use rmcp::{
    handler::server::{router::tool::ToolRouter, wrapper::Parameters},
    model::*,
    tool, tool_handler, tool_router, ServerHandler, ServiceExt,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::borrow::Cow;
use std::collections::HashMap;
use std::future::Future;
use std::io::Write;
use std::pin::Pin;
use std::str::FromStr;
use std::time::{SystemTime, UNIX_EPOCH};
use sui_crypto::simple::SimpleVerifier;
use sui_crypto::Verifier;
use sui_graphql::Client as GraphqlClient;
use sui_json::SuiJsonValue;
use sui_json_rpc_types::{
    CheckpointId, DryRunTransactionBlockResponse, EventFilter, RPCTransactionRequestParams,
    SuiMoveNormalizedFunction, SuiMoveNormalizedModule, SuiMoveNormalizedType,
    SuiObjectDataOptions, SuiObjectResponseQuery, SuiTransactionBlockEffectsAPI,
    SuiTransactionBlockResponse, SuiTransactionBlockResponseOptions,
    SuiTransactionBlockResponseQuery, SuiTypeTag, TransactionFilter, ZkLoginIntentScope,
};
use sui_keys::keystore::AccountKeystore;
use sui_rpc::proto::sui::rpc::v2::GetServiceInfoRequest as RpcGetServiceInfoRequest;
use sui_rpc::Client as RpcClient;
use sui_sdk::{SuiClient, SuiClientBuilder};
use sui_sdk_types::SimpleSignature;
use sui_types::base_types::{ObjectID, SequenceNumber, SuiAddress};
use sui_types::crypto::{Signature, ToFromBytes};
use sui_types::digests::{CheckpointDigest, TransactionDigest};
use sui_types::dynamic_field::{DynamicFieldName, DynamicFieldType};
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

/// Sui MCP Server - provides tools for interacting with the Sui blockchain via RPC
#[derive(Clone)]
struct SuiMcpServer {
    rpc_url: String,
    client: SuiClient,
    tool_router: ToolRouter<Self>,
}

impl SuiMcpServer {
    async fn new(rpc_url: Option<String>, network: Option<String>) -> Result<Self> {
        let url = Self::resolve_rpc_url(rpc_url, network)?;
        let client = SuiClientBuilder::default().build(&url).await?;
        Ok(Self {
            rpc_url: url,
            client,
            tool_router: Self::tool_router(),
        })
    }

    fn resolve_rpc_url(rpc_url: Option<String>, network: Option<String>) -> Result<String> {
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

    fn pretty_json<T: Serialize>(value: &T) -> Result<String, ErrorData> {
        serde_json::to_string_pretty(value).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize: {}", e)),
            data: None,
        })
    }

    fn clamp_limit(limit: Option<usize>, default: usize, max: usize) -> usize {
        limit.unwrap_or(default).min(max)
    }

    fn sdk_error(context: &str, error: impl std::fmt::Display) -> ErrorData {
        let error_string = error.to_string();
        let mut message = format!("{} failed: {}", context, error_string);
        if let Some(hint) = Self::error_hint(&error_string) {
            message = format!("{} (hint: {})", message, hint);
        }
        ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(message),
            data: None,
        }
    }

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

    fn error_hint(error: &str) -> Option<&'static str> {
        let lower = error.to_lowercase();
        if lower.contains("insufficient gas") || lower.contains("insufficientgas") {
            return Some("Increase gas_budget or ensure your gas coin has enough balance");
        }
        if lower.contains("insufficient funds") || lower.contains("insufficientbalance") {
            return Some("Check sender balance or select different input coins");
        }
        if lower.contains("objectnotfound") || lower.contains("object not found") {
            return Some("Verify the object id and ownership, and ensure it still exists");
        }
        if lower.contains("locked") || lower.contains("sequencenumber") || lower.contains("version")
        {
            return Some(
                "The object may be locked or outdated; retry later or fetch the latest version",
            );
        }
        if lower.contains("signature") && lower.contains("invalid") {
            return Some(
                "Ensure the signer matches the transaction sender and the signature is correct",
            );
        }
        if lower.contains("gas budget")
            || lower.contains("gasbudget")
            || lower.contains("gas too low")
        {
            return Some("Increase gas_budget or rerun with gas estimation enabled");
        }
        if lower.contains("object locked") || lower.contains("objectlocked") {
            return Some("Object is locked by another transaction; retry after it completes");
        }
        if lower.contains("version") && lower.contains("mismatch") {
            return Some("Object version mismatch; refetch object and rebuild the transaction");
        }
        None
    }

    fn write_audit_log(&self, tool: &str, entry: Value) {
        let path = if let Ok(path) = std::env::var("SUI_MCP_AUDIT_LOG") {
            std::path::PathBuf::from(path)
        } else if let Ok(home) = std::env::var("HOME") {
            std::path::PathBuf::from(home)
                .join(".sui-mcp")
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
            let _ = writeln!(file, "{}", record.to_string());
        }
    }

    fn decode_base64(label: &str, value: &str) -> Result<Vec<u8>, ErrorData> {
        Base64Engine.decode(value).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid base64 for {}: {}", label, e)),
            data: None,
        })
    }

    fn encode_tx_bytes(tx_data: &TransactionData) -> Result<String, ErrorData> {
        let bytes = bcs::to_bytes(tx_data).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        Ok(Base64Engine.encode(bytes))
    }

    fn parse_address(address: &str) -> Result<SuiAddress, ErrorData> {
        SuiAddress::from_str(address).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid Sui address: {}", e)),
            data: None,
        })
    }

    fn parse_object_id(object_id: &str) -> Result<ObjectID, ErrorData> {
        ObjectID::from_str(object_id).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid object ID: {}", e)),
            data: None,
        })
    }

    fn parse_digest(digest: &str) -> Result<TransactionDigest, ErrorData> {
        TransactionDigest::from_str(digest).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction digest: {}", e)),
            data: None,
        })
    }

    fn parse_checkpoint_digest(digest: &str) -> Result<CheckpointDigest, ErrorData> {
        CheckpointDigest::from_str(digest).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid checkpoint digest: {}", e)),
            data: None,
        })
    }

    fn parse_addresses(addresses: &[String]) -> Result<Vec<SuiAddress>, ErrorData> {
        addresses
            .iter()
            .map(|addr| Self::parse_address(addr))
            .collect()
    }

    fn parse_object_ids(object_ids: &[String]) -> Result<Vec<ObjectID>, ErrorData> {
        object_ids
            .iter()
            .map(|id| Self::parse_object_id(id))
            .collect()
    }

    fn parse_json_args(args: &[Value]) -> Result<Vec<SuiJsonValue>, ErrorData> {
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

    fn tx_response(tx_data: &TransactionData) -> Result<String, ErrorData> {
        let payload = json!({
            "tx_bytes": Self::encode_tx_bytes(tx_data)?,
        });
        Self::pretty_json(&payload)
    }

    fn summarize_transaction(response: &SuiTransactionBlockResponse) -> Value {
        let (status, error) = response
            .effects
            .as_ref()
            .map(|effects| match effects.status() {
                sui_json_rpc_types::SuiExecutionStatus::Success => ("success".to_string(), None),
                sui_json_rpc_types::SuiExecutionStatus::Failure { error } => {
                    ("failure".to_string(), Some(error.clone()))
                }
            })
            .unwrap_or_else(|| ("unknown".to_string(), None));
        let gas_used = response.effects.as_ref().map(|effects| {
            let summary = effects.gas_cost_summary();
            json!({
                "computation_cost": summary.computation_cost,
                "storage_cost": summary.storage_cost,
                "storage_rebate": summary.storage_rebate,
                "non_refundable_storage_fee": summary.non_refundable_storage_fee,
                "total_gas_used": summary.gas_used(),
            })
        });

        let created = response
            .effects
            .as_ref()
            .map(|effects| effects.created().len())
            .unwrap_or(0);
        let mutated = response
            .effects
            .as_ref()
            .map(|effects| effects.mutated().len())
            .unwrap_or(0);
        let deleted = response
            .effects
            .as_ref()
            .map(|effects| effects.deleted().len())
            .unwrap_or(0);

        json!({
            "digest": response.digest,
            "status": status,
            "success": response.status_ok(),
            "error": error,
            "checkpoint": response.checkpoint,
            "timestamp_ms": response.timestamp_ms,
            "gas_used": gas_used,
            "created": created,
            "mutated": mutated,
            "deleted": deleted,
            "events": response.events.as_ref().map(|events| events.data.len()),
            "balance_changes": response.balance_changes.as_ref().map(|changes| changes.len()),
        })
    }

    fn tx_options_from_request(
        request: Option<TransactionResponseOptionsRequest>,
    ) -> SuiTransactionBlockResponseOptions {
        if let Some(options) = request {
            let mut response = SuiTransactionBlockResponseOptions::new();
            if options.show_input.unwrap_or(false) {
                response = response.with_input();
            }
            if options.show_raw_input.unwrap_or(false) {
                response = response.with_raw_input();
            }
            if options.show_effects.unwrap_or(false) {
                response = response.with_effects();
            }
            if options.show_events.unwrap_or(false) {
                response = response.with_events();
            }
            if options.show_object_changes.unwrap_or(false) {
                response = response.with_object_changes();
            }
            if options.show_balance_changes.unwrap_or(false) {
                response = response.with_balance_changes();
            }
            if options.show_raw_effects.unwrap_or(false) {
                response = response.with_raw_effects();
            }
            response
        } else {
            SuiTransactionBlockResponseOptions::full_content()
        }
    }

    fn object_options_from_request(request: Option<ObjectOptionsRequest>) -> SuiObjectDataOptions {
        let mut options = SuiObjectDataOptions::new();
        if let Some(request) = request {
            if request.show_type.unwrap_or(false) {
                options.show_type = true;
            }
            if request.show_owner.unwrap_or(false) {
                options.show_owner = true;
            }
            if request.show_previous_transaction.unwrap_or(false) {
                options.show_previous_transaction = true;
            }
            if request.show_display.unwrap_or(false) {
                options.show_display = true;
            }
            if request.show_content.unwrap_or(false) {
                options.show_content = true;
            }
            if request.show_bcs.unwrap_or(false) {
                options.show_bcs = true;
            }
            if request.show_storage_rebate.unwrap_or(false) {
                options.show_storage_rebate = true;
            }
        }
        options
    }

    fn parse_dynamic_field_name(
        name_type: &str,
        name_value: Value,
    ) -> Result<DynamicFieldName, ErrorData> {
        let type_tag = SuiTypeTag::new(name_type.to_string())
            .try_into()
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid dynamic field name type: {}", e)),
                data: None,
            })?;

        Ok(DynamicFieldName {
            type_: type_tag,
            value: name_value,
        })
    }

    fn format_move_type(ty: &SuiMoveNormalizedType) -> String {
        match ty {
            SuiMoveNormalizedType::Bool => "bool".to_string(),
            SuiMoveNormalizedType::U8 => "u8".to_string(),
            SuiMoveNormalizedType::U16 => "u16".to_string(),
            SuiMoveNormalizedType::U32 => "u32".to_string(),
            SuiMoveNormalizedType::U64 => "u64".to_string(),
            SuiMoveNormalizedType::U128 => "u128".to_string(),
            SuiMoveNormalizedType::U256 => "u256".to_string(),
            SuiMoveNormalizedType::Address => "address".to_string(),
            SuiMoveNormalizedType::Signer => "signer".to_string(),
            SuiMoveNormalizedType::Struct { inner } => {
                let base = format!("{}::{}::{}", inner.address, inner.module, inner.name);
                if inner.type_arguments.is_empty() {
                    base
                } else {
                    let args = inner
                        .type_arguments
                        .iter()
                        .map(Self::format_move_type)
                        .collect::<Vec<_>>()
                        .join(", ");
                    format!("{}<{}>", base, args)
                }
            }
            SuiMoveNormalizedType::Vector(inner) => {
                format!("vector<{}>", Self::format_move_type(inner))
            }
            SuiMoveNormalizedType::TypeParameter(index) => format!("T{}", index),
            SuiMoveNormalizedType::Reference(inner) => {
                format!("&{}", Self::format_move_type(inner))
            }
            SuiMoveNormalizedType::MutableReference(inner) => {
                format!("&mut {}", Self::format_move_type(inner))
            }
        }
    }

    fn move_param_hint(ty: &SuiMoveNormalizedType) -> (String, Value, bool) {
        let (kind, placeholder, is_object) = match ty {
            SuiMoveNormalizedType::Bool => ("bool", json!(false), false),
            SuiMoveNormalizedType::U8
            | SuiMoveNormalizedType::U16
            | SuiMoveNormalizedType::U32
            | SuiMoveNormalizedType::U64
            | SuiMoveNormalizedType::U128
            | SuiMoveNormalizedType::U256 => ("number", json!(0), false),
            SuiMoveNormalizedType::Address => ("address", json!("<address>"), false),
            SuiMoveNormalizedType::Signer => ("signer", json!("<signer>"), false),
            SuiMoveNormalizedType::Struct { .. } => ("struct", json!("<object_or_value>"), true),
            SuiMoveNormalizedType::Vector(_) => ("vector", json!([]), false),
            SuiMoveNormalizedType::TypeParameter(index) => {
                ("type_parameter", json!(format!("<T{}>", index)), false)
            }
            SuiMoveNormalizedType::Reference(inner) => {
                if matches!(inner.as_ref(), SuiMoveNormalizedType::Struct { .. }) {
                    ("object", json!("<object_id>"), true)
                } else {
                    ("reference", json!("<value>"), false)
                }
            }
            SuiMoveNormalizedType::MutableReference(inner) => {
                if matches!(inner.as_ref(), SuiMoveNormalizedType::Struct { .. }) {
                    ("object_mut", json!("<object_id>"), true)
                } else {
                    ("reference_mut", json!("<value>"), false)
                }
            }
        };

        (kind.to_string(), placeholder, is_object)
    }

    fn param_requirements(ty: &SuiMoveNormalizedType) -> (bool, Vec<&'static str>) {
        let requires_mutable = matches!(ty, SuiMoveNormalizedType::MutableReference(_))
            || matches!(ty, SuiMoveNormalizedType::Struct { .. });
        let is_object = matches!(ty, SuiMoveNormalizedType::Struct { .. })
            || matches!(ty, SuiMoveNormalizedType::Reference(inner) if matches!(inner.as_ref(), SuiMoveNormalizedType::Struct { .. }))
            || matches!(ty, SuiMoveNormalizedType::MutableReference(inner) if matches!(inner.as_ref(), SuiMoveNormalizedType::Struct { .. }));

        if !is_object {
            return (requires_mutable, vec![]);
        }

        if matches!(ty, SuiMoveNormalizedType::MutableReference(_))
            || matches!(ty, SuiMoveNormalizedType::Struct { .. })
        {
            (true, vec!["owned", "object_owner", "shared", "consensus"])
        } else {
            (
                false,
                vec!["owned", "immutable", "shared", "object_owner", "consensus"],
            )
        }
    }

    fn owner_kind(owner: &Owner) -> &'static str {
        match owner {
            Owner::AddressOwner(_) => "owned",
            Owner::ObjectOwner(_) => "object_owner",
            Owner::Shared { .. } => "shared",
            Owner::Immutable => "immutable",
            Owner::ConsensusAddressOwner { .. } => "consensus",
        }
    }

    fn is_auto_arg(value: &Value) -> bool {
        matches!(value, Value::Null)
            || matches!(value, Value::String(s) if s == "<auto>" || s == "auto")
    }

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

    fn validate_pure_arg(ty: &SuiMoveNormalizedType, value: &Value) -> Result<(), ErrorData> {
        let invalid = || ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!(
                "Invalid value for type {}",
                Self::format_move_type(ty)
            )),
            data: None,
        };

        match ty {
            SuiMoveNormalizedType::Bool => match value {
                Value::Bool(_) => Ok(()),
                _ => Err(invalid()),
            },
            SuiMoveNormalizedType::U8
            | SuiMoveNormalizedType::U16
            | SuiMoveNormalizedType::U32
            | SuiMoveNormalizedType::U64
            | SuiMoveNormalizedType::U128
            | SuiMoveNormalizedType::U256 => match value {
                Value::Number(n) if n.is_u64() => Ok(()),
                Value::String(s) if s.parse::<u128>().is_ok() => Ok(()),
                _ => Err(invalid()),
            },
            SuiMoveNormalizedType::Address => match value {
                Value::String(s) if s.starts_with("0x") => Ok(()),
                _ => Err(invalid()),
            },
            SuiMoveNormalizedType::Signer => match value {
                Value::String(s) if s.starts_with("0x") => Ok(()),
                _ => Err(invalid()),
            },
            SuiMoveNormalizedType::Vector(inner) => match value {
                Value::Array(items) => {
                    for item in items {
                        Self::validate_pure_arg(inner, item)?;
                    }
                    Ok(())
                }
                _ => Err(invalid()),
            },
            SuiMoveNormalizedType::Struct { .. } => match value {
                Value::Object(_) => Ok(()),
                Value::String(_) => Ok(()),
                _ => Err(invalid()),
            },
            SuiMoveNormalizedType::TypeParameter(_) => Ok(()),
            SuiMoveNormalizedType::Reference(inner)
            | SuiMoveNormalizedType::MutableReference(inner) => {
                if matches!(inner.as_ref(), SuiMoveNormalizedType::Struct { .. }) {
                    match value {
                        Value::String(s) if s.starts_with("0x") => Ok(()),
                        _ => Err(invalid()),
                    }
                } else {
                    Self::validate_pure_arg(inner, value)
                }
            }
        }
    }

    fn build_move_call_template(
        package: &str,
        module: &str,
        function: &str,
        function_def: &SuiMoveNormalizedFunction,
    ) -> Value {
        let type_args = (0..function_def.type_parameters.len())
            .map(|index| format!("<T{}>", index))
            .collect::<Vec<_>>();
        let arguments = function_def
            .parameters
            .iter()
            .enumerate()
            .map(|(index, ty)| {
                let (kind, placeholder, is_object) = Self::move_param_hint(ty);
                json!({
                    "index": index,
                    "type": Self::format_move_type(ty),
                    "kind": kind,
                    "is_object": is_object,
                    "value": placeholder,
                })
            })
            .collect::<Vec<_>>();

        json!({
            "package": package,
            "module": module,
            "function": function,
            "type_args": type_args,
            "arguments": arguments,
            "gas_budget": 0,
            "gas_object_id": null,
            "gas_price": null
        })
    }

    fn move_type_schema(
        ty: &SuiMoveNormalizedType,
        modules: &std::collections::BTreeMap<String, SuiMoveNormalizedModule>,
        depth: usize,
        max_depth: usize,
    ) -> Value {
        match ty {
            SuiMoveNormalizedType::Bool => json!({"type": "boolean", "x-move-type": "bool"}),
            SuiMoveNormalizedType::U8 => json!({"type": "string", "x-move-type": "u8"}),
            SuiMoveNormalizedType::U16 => json!({"type": "string", "x-move-type": "u16"}),
            SuiMoveNormalizedType::U32 => json!({"type": "string", "x-move-type": "u32"}),
            SuiMoveNormalizedType::U64 => json!({"type": "string", "x-move-type": "u64"}),
            SuiMoveNormalizedType::U128 => json!({"type": "string", "x-move-type": "u128"}),
            SuiMoveNormalizedType::U256 => json!({"type": "string", "x-move-type": "u256"}),
            SuiMoveNormalizedType::Address => json!({
                "type": "string",
                "pattern": "^0x[0-9a-fA-F]+$",
                "x-move-type": "address"
            }),
            SuiMoveNormalizedType::Signer => json!({"type": "string", "x-move-type": "signer"}),
            SuiMoveNormalizedType::Vector(inner) => json!({
                "type": "array",
                "items": Self::move_type_schema(inner, modules, depth + 1, max_depth),
                "x-move-type": "vector"
            }),
            SuiMoveNormalizedType::TypeParameter(index) => json!({
                "type": "string",
                "x-move-type": format!("T{}", index)
            }),
            SuiMoveNormalizedType::Reference(inner)
            | SuiMoveNormalizedType::MutableReference(inner) => match inner.as_ref() {
                SuiMoveNormalizedType::Struct { .. } => json!({
                    "type": "string",
                    "description": "object id",
                    "x-move-type": Self::format_move_type(inner)
                }),
                _ => Self::move_type_schema(inner, modules, depth + 1, max_depth),
            },
            SuiMoveNormalizedType::Struct { inner } => {
                let struct_name = format!("{}::{}::{}", inner.address, inner.module, inner.name);
                if depth >= max_depth {
                    return json!({"type": "string", "x-move-type": struct_name});
                }

                if let Some(module) = modules.get(&inner.module) {
                    if let Some(struct_def) = module.structs.get(&inner.name) {
                        let mut properties = serde_json::Map::new();
                        let mut required = Vec::new();
                        for field in struct_def.fields.iter() {
                            required.push(field.name.clone());
                            properties.insert(
                                field.name.clone(),
                                Self::move_type_schema(&field.type_, modules, depth + 1, max_depth),
                            );
                        }
                        return json!({
                            "type": "object",
                            "properties": properties,
                            "required": required,
                            "x-move-type": struct_name
                        });
                    }
                }

                json!({"type": "string", "x-move-type": struct_name})
            }
        }
    }

    fn move_call_form_schema(
        package: &str,
        module: &str,
        function: &str,
        function_def: &SuiMoveNormalizedFunction,
        modules: &std::collections::BTreeMap<String, SuiMoveNormalizedModule>,
        max_depth: usize,
    ) -> Value {
        let argument_schemas = function_def
            .parameters
            .iter()
            .enumerate()
            .map(|(index, ty)| {
                json!({
                    "index": index,
                    "type": Self::format_move_type(ty),
                    "schema": Self::move_type_schema(ty, modules, 0, max_depth),
                })
            })
            .collect::<Vec<_>>();

        let ui_arguments = function_def
            .parameters
            .iter()
            .enumerate()
            .map(|(index, ty)| {
                let (kind, placeholder, is_object) = Self::move_param_hint(ty);
                json!({
                    "index": index,
                    "label": format!("arg{}", index),
                    "type": Self::format_move_type(ty),
                    "kind": kind,
                    "placeholder": placeholder,
                    "is_object": is_object
                })
            })
            .collect::<Vec<_>>();

        let ui_schema = json!({
            "sender": {
                "label": "Sender",
                "placeholder": "0x...",
                "widget": "address"
            },
            "gas_budget": {
                "label": "Gas Budget",
                "placeholder": "1000000"
            },
            "gas_object_id": {
                "label": "Gas Object",
                "placeholder": "0x..."
            },
            "gas_price": {
                "label": "Gas Price",
                "placeholder": "1000"
            },
            "arguments": ui_arguments
        });

        json!({
            "title": format!("{}::{}::{}", package, module, function),
            "type": "object",
            "properties": {
                "sender": {
                    "type": "string",
                    "title": "Sender"
                },
                "package": {"type": "string"},
                "module": {"type": "string"},
                "function": {"type": "string"},
                "type_args": {
                    "type": "array",
                    "items": {"type": "string"}
                },
                "arguments": {
                    "type": "array",
                    "items": {"type": "object"}
                },
                "gas_budget": {"type": "integer"},
                "gas_object_id": {"type": "string"},
                "gas_price": {"type": "integer"}
            },
            "required": ["sender", "package", "module", "function", "arguments", "gas_budget"],
            "x-arguments": argument_schemas,
            "ui_schema": ui_schema
        })
    }

    fn is_object_param_match(param: &SuiMoveNormalizedType, tag: &StructTag) -> bool {
        let inner = match param {
            SuiMoveNormalizedType::Reference(inner)
            | SuiMoveNormalizedType::MutableReference(inner) => inner.as_ref(),
            _ => return false,
        };

        let SuiMoveNormalizedType::Struct { inner } = inner else {
            return false;
        };

        let address_match =
            inner.address.to_lowercase() == tag.address.to_hex_literal().to_lowercase();
        let module_match = inner.module == tag.module.to_string();
        let name_match = inner.name == tag.name.to_string();
        let type_arg_match = inner.type_arguments.len() == tag.type_params.len();

        address_match && module_match && name_match && type_arg_match
    }

    fn match_type_param(
        param: &SuiMoveNormalizedType,
        actual: &TypeTag,
        mapping: &mut HashMap<usize, TypeTag>,
    ) -> bool {
        match (param, actual) {
            (SuiMoveNormalizedType::Bool, TypeTag::Bool)
            | (SuiMoveNormalizedType::U8, TypeTag::U8)
            | (SuiMoveNormalizedType::U16, TypeTag::U16)
            | (SuiMoveNormalizedType::U32, TypeTag::U32)
            | (SuiMoveNormalizedType::U64, TypeTag::U64)
            | (SuiMoveNormalizedType::U128, TypeTag::U128)
            | (SuiMoveNormalizedType::U256, TypeTag::U256)
            | (SuiMoveNormalizedType::Address, TypeTag::Address)
            | (SuiMoveNormalizedType::Signer, TypeTag::Signer) => true,
            (SuiMoveNormalizedType::Vector(inner), TypeTag::Vector(actual_inner)) => {
                Self::match_type_param(inner, actual_inner, mapping)
            }
            (SuiMoveNormalizedType::Struct { inner }, TypeTag::Struct(actual_struct)) => {
                if inner.address.to_lowercase()
                    != actual_struct.address.to_hex_literal().to_lowercase()
                    || inner.module != actual_struct.module.to_string()
                    || inner.name != actual_struct.name.to_string()
                    || inner.type_arguments.len() != actual_struct.type_params.len()
                {
                    return false;
                }

                for (param_arg, actual_arg) in inner
                    .type_arguments
                    .iter()
                    .zip(actual_struct.type_params.iter())
                {
                    if !Self::match_type_param(param_arg, actual_arg, mapping) {
                        return false;
                    }
                }
                true
            }
            (SuiMoveNormalizedType::TypeParameter(index), actual_type) => {
                let key = (*index).into();
                match mapping.get(&key) {
                    Some(existing) => existing == actual_type,
                    None => {
                        mapping.insert(key, actual_type.clone());
                        true
                    }
                }
            }
            (SuiMoveNormalizedType::Reference(inner), actual_type)
            | (SuiMoveNormalizedType::MutableReference(inner), actual_type) => {
                Self::match_type_param(inner, actual_type, mapping)
            }
            _ => false,
        }
    }

    fn infer_type_args(
        param: &SuiMoveNormalizedType,
        struct_tag: &StructTag,
    ) -> Option<HashMap<usize, TypeTag>> {
        let mut mapping = HashMap::new();
        let actual = TypeTag::Struct(Box::new(struct_tag.clone()));
        if Self::match_type_param(param, &actual, &mut mapping) {
            Some(mapping)
        } else {
            None
        }
    }

    fn merge_type_args(
        target: &mut HashMap<usize, TypeTag>,
        incoming: HashMap<usize, TypeTag>,
    ) -> bool {
        for (index, value) in incoming {
            if let Some(existing) = target.get(&index) {
                if existing != &value {
                    return false;
                }
            } else {
                target.insert(index, value);
            }
        }
        true
    }

    fn type_args_from_mapping(mapping: &HashMap<usize, TypeTag>, count: usize) -> Vec<String> {
        (0..count)
            .map(|index| {
                mapping
                    .get(&index)
                    .map(|tag| tag.to_string())
                    .unwrap_or_else(|| format!("<T{}>", index))
            })
            .collect()
    }

    fn fetch_dynamic_field_tree<'a>(
        &'a self,
        object_id: ObjectID,
        depth: usize,
        max_depth: usize,
        limit: usize,
    ) -> Pin<Box<dyn Future<Output = Result<Value, ErrorData>> + Send + 'a>> {
        Box::pin(async move {
            let page = self
                .client
                .read_api()
                .get_dynamic_fields(object_id, None, Some(limit))
                .await
                .map_err(|e| Self::sdk_error("get_dynamic_fields", e))?;

            let mut fields = Vec::new();
            for field in page.data {
                let mut field_value = serde_json::to_value(&field).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to serialize dynamic field: {}", e)),
                    data: None,
                })?;

                if depth < max_depth && field.type_ == DynamicFieldType::DynamicObject {
                    let child = self
                        .fetch_dynamic_field_tree(field.object_id, depth + 1, max_depth, limit)
                        .await?;
                    if let Value::Object(ref mut map) = field_value {
                        map.insert("children".to_string(), child);
                    }
                }

                fields.push(field_value);
            }

            Ok(json!({
                "object_id": object_id,
                "depth": depth,
                "fields": fields,
                "next_cursor": page.next_cursor,
                "has_next_page": page.has_next_page
            }))
        })
    }
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct TransactionResponseOptionsRequest {
    #[schemars(description = "Include transaction input")]
    show_input: Option<bool>,
    #[schemars(description = "Include raw input bytes")]
    show_raw_input: Option<bool>,
    #[schemars(description = "Include effects")]
    show_effects: Option<bool>,
    #[schemars(description = "Include events")]
    show_events: Option<bool>,
    #[schemars(description = "Include object changes")]
    show_object_changes: Option<bool>,
    #[schemars(description = "Include balance changes")]
    show_balance_changes: Option<bool>,
    #[schemars(description = "Include raw effects")]
    show_raw_effects: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetBalanceRequest {
    #[schemars(description = "The Sui address to query (hex format starting with 0x)")]
    address: String,
    #[schemars(description = "Optional coin type (defaults to 0x2::sui::SUI)")]
    coin_type: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetAllBalancesRequest {
    #[schemars(description = "The Sui address to query (hex format starting with 0x)")]
    address: String,
}

// ---- EVM / Base (experimental multi-chain) ----

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmGetBalanceRequest {
    #[schemars(description = "EVM address (0x...) to query")]
    address: String,
    #[schemars(
        description = "Optional chain id (default: EVM_DEFAULT_CHAIN_ID or Base Sepolia 84532)"
    )]
    chain_id: Option<u64>,
    #[schemars(
        description = "Optional ERC20 token contract address. If omitted, returns native ETH balance."
    )]
    token_address: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmGetTransactionRequest {
    #[schemars(description = "Transaction hash (0x...)")]
    tx_hash: String,
    #[schemars(
        description = "Optional chain id (default: EVM_DEFAULT_CHAIN_ID or Base Sepolia 84532)"
    )]
    chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmBuildTransferNativeRequest {
    #[schemars(description = "Sender address (0x...)")]
    sender: String,
    #[schemars(description = "Recipient address (0x...)")]
    recipient: String,
    #[schemars(description = "Amount in wei (decimal string or 0x hex)")]
    amount_wei: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
    #[schemars(description = "Optional hex calldata (0x...) for advanced use")]
    data_hex: Option<String>,
    #[schemars(description = "Optional gas limit override")]
    gas_limit: Option<u64>,
    #[schemars(description = "Require explicit confirmation for large transfers")]
    confirm_large_transfer: Option<bool>,
    #[schemars(description = "Large transfer threshold in wei (default 0.1 ETH)")]
    large_transfer_threshold_wei: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
struct EvmTxRequest {
    #[schemars(description = "Chain id")]
    chain_id: u64,
    #[schemars(description = "Sender address")]
    from: String,
    #[schemars(description = "Recipient address")]
    to: String,
    #[schemars(description = "Value in wei (decimal string)")]
    value_wei: String,
    #[schemars(description = "Optional calldata (0x...) ")]
    data_hex: Option<String>,
    #[schemars(description = "Transaction nonce")]
    nonce: Option<u64>,
    #[schemars(description = "Gas limit")]
    gas_limit: Option<u64>,
    #[schemars(description = "EIP-1559 maxFeePerGas in wei (decimal string)")]
    max_fee_per_gas_wei: Option<String>,
    #[schemars(description = "EIP-1559 maxPriorityFeePerGas in wei (decimal string)")]
    max_priority_fee_per_gas_wei: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmPreflightRequest {
    #[schemars(description = "Transaction request to preflight (fills missing nonce/gas/fees)")]
    tx: EvmTxRequest,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmSignLocalRequest {
    #[schemars(description = "Transaction request (must include nonce, gas_limit, and fees)")]
    tx: EvmTxRequest,
    #[schemars(description = "Allow signer address to differ from tx.from")]
    allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmSendRawTransactionRequest {
    #[schemars(description = "Raw signed tx hex (0x...)")]
    raw_tx: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmExecuteTransferNativeRequest {
    #[schemars(description = "Sender address (0x...)")]
    sender: String,
    #[schemars(description = "Recipient address (0x...)")]
    recipient: String,
    #[schemars(description = "Amount in ETH units (18 decimals), e.g. '0.001'")]
    amount: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
    #[schemars(description = "Optional gas limit override")]
    gas_limit: Option<u64>,
    #[schemars(description = "Require explicit confirmation for large transfers")]
    confirm_large_transfer: Option<bool>,
    #[schemars(description = "Large transfer threshold in wei (default 0.1 ETH)")]
    large_transfer_threshold_wei: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmErc20BalanceOfRequest {
    #[schemars(description = "ERC20 token contract address")]
    token: String,
    #[schemars(description = "Owner address")]
    owner: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmErc20AllowanceRequest {
    #[schemars(description = "ERC20 token contract address")]
    token: String,
    #[schemars(description = "Owner address")]
    owner: String,
    #[schemars(description = "Spender address")]
    spender: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmExecuteErc20TransferRequest {
    #[schemars(
        description = "Sender address (must match EVM_PRIVATE_KEY unless allow_sender_mismatch is true)"
    )]
    sender: String,
    #[schemars(description = "ERC20 token contract address")]
    token: String,
    #[schemars(description = "Recipient address")]
    recipient: String,
    #[schemars(description = "Token amount in base units (raw integer, e.g. USDC has 6 decimals)")]
    amount_raw: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
    #[schemars(description = "Optional gas limit override")]
    gas_limit: Option<u64>,
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmExecuteErc20ApproveRequest {
    #[schemars(
        description = "Owner/sender address (must match EVM_PRIVATE_KEY unless allow_sender_mismatch is true)"
    )]
    sender: String,
    #[schemars(description = "ERC20 token contract address")]
    token: String,
    #[schemars(description = "Spender address")]
    spender: String,
    #[schemars(description = "Token amount in base units (raw integer)")]
    amount_raw: String,
    #[schemars(description = "Optional chain id")]
    chain_id: Option<u64>,
    #[schemars(description = "Optional gas limit override")]
    gas_limit: Option<u64>,
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmRegisterContractRequest {
    #[schemars(description = "EVM chain id")]
    chain_id: u64,
    #[schemars(description = "Contract address")]
    address: String,
    #[schemars(description = "Optional human-friendly name")]
    name: Option<String>,
    #[schemars(description = "Contract ABI JSON (string)")]
    abi_json: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmListContractsRequest {
    #[schemars(description = "Optional chain id filter")]
    chain_id: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmGetContractRequest {
    #[schemars(description = "EVM chain id")]
    chain_id: u64,
    #[schemars(description = "Contract address")]
    address: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmCallViewRequest {
    #[schemars(description = "EVM chain id")]
    chain_id: u64,
    #[schemars(description = "Contract address (optional if contract_name is provided)")]
    address: Option<String>,
    #[schemars(description = "Contract name/alias in ABI registry (optional)")]
    contract_name: Option<String>,
    #[schemars(description = "Function name (e.g. 'balanceOf')")]
    function: String,
    #[schemars(description = "Optional exact function signature (e.g. 'balanceOf(address)')")]
    function_signature: Option<String>,
    #[schemars(
        description = "Arguments as JSON array (supports basic types: address, uint/int, bool, string, bytes)"
    )]
    args: Option<Value>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EvmExecuteContractCallRequest {
    #[schemars(description = "EVM chain id")]
    chain_id: u64,
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Contract address (optional if contract_name is provided)")]
    address: Option<String>,
    #[schemars(description = "Contract name/alias in ABI registry (optional)")]
    contract_name: Option<String>,
    #[schemars(description = "Function name")]
    function: String,
    #[schemars(
        description = "Optional exact function signature (e.g. 'transfer(address,uint256)')"
    )]
    function_signature: Option<String>,
    #[schemars(
        description = "Arguments as JSON array (supports basic types: address, uint/int, bool, string, bytes)"
    )]
    args: Option<Value>,
    #[schemars(description = "Optional value in wei (decimal string or 0x hex)")]
    value_wei: Option<String>,
    #[schemars(description = "Optional gas limit override")]
    gas_limit: Option<u64>,
    #[schemars(description = "Allow signer mismatch between tx.from and EVM_PRIVATE_KEY")]
    allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetObjectRequest {
    #[schemars(description = "The object ID to query (hex format starting with 0x)")]
    object_id: String,
    #[schemars(description = "Include content in response (default: true)")]
    show_content: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetOwnedObjectsRequest {
    #[schemars(description = "The Sui address to query (hex format starting with 0x)")]
    address: String,
    #[schemars(description = "Optional limit on number of results (max 50)")]
    limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetTransactionRequest {
    #[schemars(description = "The transaction digest to query (base58 encoded)")]
    digest: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct QueryEventsRequest {
    #[schemars(description = "The transaction digest to query events for")]
    digest: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetCoinsRequest {
    #[schemars(description = "The Sui address to query")]
    address: String,
    #[schemars(description = "Optional coin type (defaults to 0x2::sui::SUI)")]
    coin_type: Option<String>,
    #[schemars(description = "Optional limit on number of results")]
    limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct WalletOverviewRequest {
    #[schemars(description = "Optional Sui address to query")]
    address: Option<String>,
    #[schemars(
        description = "Optional signer address or alias (used if address is omitted and keystore has multiple accounts)"
    )]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Optional coin type for balance/coins (defaults to 0x2::sui::SUI)")]
    coin_type: Option<String>,
    #[schemars(description = "Include coin objects in response (default: false)")]
    include_coins: Option<bool>,
    #[schemars(description = "Optional limit for coin objects (default: 20, max: 50)")]
    coins_limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct TransactionTemplateRequest {
    #[schemars(description = "Template name: transfer_sui|transfer_object|stake|unstake|pay_sui")]
    template: String,
    #[schemars(description = "Sender address (required for templates)")]
    sender: String,
    #[schemars(description = "Recipient address (transfer_sui, transfer_object, pay_sui)")]
    recipient: Option<String>,
    #[schemars(description = "Object ID to transfer (transfer_object)")]
    object_id: Option<String>,
    #[schemars(description = "Validator address (stake)")]
    validator: Option<String>,
    #[schemars(description = "Staked SUI object id (unstake)")]
    staked_sui: Option<String>,
    #[schemars(description = "Optional amount in raw SUI (transfer_sui/pay_sui/stake)")]
    amount: Option<u64>,
    #[schemars(description = "Recipients for pay_sui")]
    recipients: Option<Vec<String>>,
    #[schemars(description = "Amounts for pay_sui")]
    amounts: Option<Vec<u64>>,
    #[schemars(description = "Optional gas budget (default: 1_000_000)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ZkLoginExecuteTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    tx_bytes: String,
    #[schemars(description = "ZkLogin inputs JSON string from prover")]
    zk_login_inputs_json: String,
    #[schemars(description = "Address seed used for zkLogin (decimal string)")]
    address_seed: String,
    #[schemars(description = "Maximum epoch for the zkLogin signature")]
    max_epoch: u64,
    #[schemars(description = "Ephemeral user signature over tx bytes (base64 flag||sig||pubkey)")]
    user_signature: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct VerifyZkLoginSignatureRequest {
    #[schemars(description = "Base64-encoded bytes to verify (transaction bytes or message)")]
    bytes: String,
    #[schemars(description = "Base64-encoded zkLogin signature bytes")]
    signature: String,
    #[schemars(description = "Sui address that should match the zkLogin address")]
    address: String,
    #[schemars(
        description = "Intent scope: transaction or personal_message (default: transaction)"
    )]
    intent_scope: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct KeystoreAccountsRequest {
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct KeystoreSignTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    tx_bytes: String,
    #[schemars(
        description = "Signer address or alias (required if multiple accounts in keystore)"
    )]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct KeystoreExecuteTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    tx_bytes: String,
    #[schemars(
        description = "Signer address or alias (required if multiple accounts in keystore)"
    )]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildTransferObjectRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Object ID to transfer")]
    object_id: String,
    #[schemars(description = "Recipient address")]
    recipient: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildTransferSuiRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Recipient address")]
    recipient: String,
    #[schemars(description = "Optional amount to transfer; omit to transfer all")]
    amount: Option<u64>,
    #[schemars(description = "Input coin object IDs used for payment")]
    input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Automatically select input coins when empty (default: true)")]
    auto_select_coins: Option<bool>,
    #[schemars(
        description = "Confirm large transfer when amount exceeds threshold (default: false)"
    )]
    confirm_large_transfer: Option<bool>,
    #[schemars(
        description = "Large transfer threshold in raw SUI (default: 1_000_000_000 = 1 SUI)"
    )]
    large_transfer_threshold: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ExecuteTransferSuiRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Recipient address")]
    recipient: String,
    #[schemars(description = "Optional amount to transfer; omit to transfer all")]
    amount: Option<u64>,
    #[schemars(description = "Input coin object IDs used for payment")]
    input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Automatically select input coins when empty (default: true)")]
    auto_select_coins: Option<bool>,
    #[schemars(
        description = "Confirm large transfer when amount exceeds threshold (default: false)"
    )]
    confirm_large_transfer: Option<bool>,
    #[schemars(
        description = "Large transfer threshold in raw SUI (default: 1_000_000_000 = 1 SUI)"
    )]
    large_transfer_threshold: Option<u64>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
    #[schemars(description = "Merge small SUI coins before transfer (default: false)")]
    auto_merge_small_coins: Option<bool>,
    #[schemars(description = "Merge when coin count exceeds this threshold (default: 10)")]
    merge_threshold: Option<usize>,
    #[schemars(description = "Maximum number of coins to merge (default: 10)")]
    merge_max_inputs: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ExecuteTransferObjectRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Object ID to transfer")]
    object_id: String,
    #[schemars(description = "Recipient address")]
    recipient: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ExecutePaySuiRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Recipients")]
    recipients: Vec<String>,
    #[schemars(description = "Amounts in raw SUI")]
    amounts: Vec<u64>,
    #[schemars(description = "Input coin object IDs used for payment")]
    input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ExecuteAddStakeRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Validator address")]
    validator: String,
    #[schemars(description = "Input coin object IDs used for stake")]
    coins: Vec<String>,
    #[schemars(description = "Optional amount to stake")]
    amount: Option<u64>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ExecuteWithdrawStakeRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Staked SUI object id")]
    staked_sui: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildPaySuiRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Recipient addresses")]
    recipients: Vec<String>,
    #[schemars(description = "Amounts for recipients")]
    amounts: Vec<u64>,
    #[schemars(description = "Input coin object IDs used for payment (first coin used as gas)")]
    input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildPayAllSuiRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Recipient address")]
    recipient: String,
    #[schemars(description = "Input coin object IDs used for payment (first coin used as gas)")]
    input_coins: Vec<String>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildMoveCallRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments, e.g. 0x2::sui::SUI")]
    type_args: Vec<String>,
    #[schemars(description = "Move call arguments as JSON values")]
    arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildPublishRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Compiled Move modules (base64 BCS) in order")]
    compiled_modules: Vec<String>,
    #[schemars(description = "Dependency package object IDs")]
    dependencies: Vec<String>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildSplitCoinRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Coin object ID to split")]
    coin_object_id: String,
    #[schemars(description = "Split amounts")]
    split_amounts: Vec<u64>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildMergeCoinsRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Primary coin object ID")]
    primary_coin: String,
    #[schemars(description = "Coin object ID to merge")]
    coin_to_merge: String,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildBatchTransactionRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Batch transaction requests")]
    requests: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ExecuteBatchTransactionRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Batch transaction requests")]
    requests: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Signer address or alias (defaults to sender)")]
    signer: Option<String>,
    #[schemars(
        description = "Optional keystore path (defaults to SUI_KEYSTORE_PATH or ~/.sui/sui_config/sui.keystore)"
    )]
    keystore_path: Option<String>,
    #[schemars(description = "Allow signer to differ from transaction sender (default: false)")]
    allow_sender_mismatch: Option<bool>,
    #[schemars(description = "Run dry-run before execution (default: false)")]
    preflight: Option<bool>,
    #[schemars(description = "Allow execution even if dry-run fails (default: false)")]
    allow_preflight_failure: Option<bool>,
    #[schemars(description = "Confirm sensitive action (required)")]
    confirm: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildAddStakeRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Validator address to stake with")]
    validator: String,
    #[schemars(description = "Coin object IDs to stake")]
    coins: Vec<String>,
    #[schemars(description = "Optional amount to stake (uses all if omitted)")]
    amount: Option<u64>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildWithdrawStakeRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Staked SUI object ID")]
    staked_sui: String,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct BuildUpgradeRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID to upgrade")]
    package_id: String,
    #[schemars(description = "Compiled Move modules (base64 BCS) in order")]
    compiled_modules: Vec<String>,
    #[schemars(description = "Dependency package object IDs")]
    dependencies: Vec<String>,
    #[schemars(description = "Upgrade capability object ID")]
    upgrade_capability: String,
    #[schemars(description = "Upgrade policy as u8")]
    upgrade_policy: u8,
    #[schemars(description = "Digest bytes (base64)")]
    digest: String,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct DryRunTransactionRequest {
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    tx_bytes: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct DevInspectTransactionRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Base64-encoded transaction bytes (BCS TransactionData)")]
    tx_bytes: String,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
    #[schemars(description = "Optional epoch override")]
    epoch: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetStakesRequest {
    #[schemars(description = "Owner address to query stakes for")]
    owner: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetCommitteeInfoRequest {
    #[schemars(description = "Optional epoch to query")]
    epoch: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetCheckpointRequest {
    #[schemars(description = "Checkpoint sequence number")]
    sequence_number: Option<u64>,
    #[schemars(description = "Checkpoint digest")]
    digest: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetCheckpointsRequest {
    #[schemars(description = "Optional cursor (checkpoint sequence number)")]
    cursor: Option<u64>,
    #[schemars(description = "Optional limit on results (max 100)")]
    limit: Option<usize>,
    #[schemars(description = "Return in descending order")]
    descending_order: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct QueryTransactionBlocksRequest {
    #[schemars(description = "Optional transaction filter as JSON")]
    filter: Option<Value>,
    #[schemars(description = "Optional cursor (transaction digest)")]
    cursor: Option<String>,
    #[schemars(description = "Optional limit on results (max 50)")]
    limit: Option<usize>,
    #[schemars(description = "Return in descending order")]
    descending_order: Option<bool>,
    #[schemars(description = "Optional response options")]
    options: Option<TransactionResponseOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct MultiGetTransactionsRequest {
    #[schemars(description = "Transaction digests to fetch")]
    digests: Vec<String>,
    #[schemars(description = "Optional response options")]
    options: Option<TransactionResponseOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct SelectCoinsRequest {
    #[schemars(description = "Owner address to select coins from")]
    owner: String,
    #[schemars(description = "Optional coin type")]
    coin_type: Option<String>,
    #[schemars(description = "Total amount to cover")]
    amount: u128,
    #[schemars(description = "Object IDs to exclude")]
    exclude: Vec<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetCoinMetadataRequest {
    #[schemars(description = "Coin type to query")]
    coin_type: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetTotalSupplyRequest {
    #[schemars(description = "Coin type to query")]
    coin_type: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetNormalizedMoveModulesRequest {
    #[schemars(description = "Package object ID")]
    package: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetDynamicFieldsRequest {
    #[schemars(description = "Parent object ID")]
    object_id: String,
    #[schemars(description = "Optional cursor (dynamic field object ID)")]
    cursor: Option<String>,
    #[schemars(description = "Optional limit on results (max 50)")]
    limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetDynamicFieldObjectRequest {
    #[schemars(description = "Parent object ID")]
    parent_object_id: String,
    #[schemars(description = "Dynamic field name type")]
    name_type: String,
    #[schemars(description = "Dynamic field name value (JSON)")]
    name_value: Value,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetMoveObjectBcsRequest {
    #[schemars(description = "Object ID")]
    object_id: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ObjectOptionsRequest {
    #[schemars(description = "Include object type")]
    show_type: Option<bool>,
    #[schemars(description = "Include owner")]
    show_owner: Option<bool>,
    #[schemars(description = "Include previous transaction")]
    show_previous_transaction: Option<bool>,
    #[schemars(description = "Include display metadata")]
    show_display: Option<bool>,
    #[schemars(description = "Include content")]
    show_content: Option<bool>,
    #[schemars(description = "Include BCS bytes")]
    show_bcs: Option<bool>,
    #[schemars(description = "Include storage rebate")]
    show_storage_rebate: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetPastObjectRequest {
    #[schemars(description = "Object ID")]
    object_id: String,
    #[schemars(description = "Object version")]
    version: u64,
    #[schemars(description = "Optional object response options")]
    options: Option<ObjectOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct PastObjectRequestItem {
    #[schemars(description = "Object ID")]
    object_id: String,
    #[schemars(description = "Object version")]
    version: u64,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct MultiGetPastObjectsRequest {
    #[schemars(description = "Objects to query")]
    objects: Vec<PastObjectRequestItem>,
    #[schemars(description = "Optional object response options")]
    options: Option<ObjectOptionsRequest>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetAllCoinsRequest {
    #[schemars(description = "Owner address")]
    owner: String,
    #[schemars(description = "Optional cursor")]
    cursor: Option<String>,
    #[schemars(description = "Optional limit on results")]
    limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct DescribeMoveFunctionRequest {
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GenerateModuleTemplatesRequest {
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Optional module name to scope results")]
    module: Option<String>,
    #[schemars(description = "Only include entry functions (default true)")]
    entry_only: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct SuggestObjectMethodsRequest {
    #[schemars(description = "Object ID to inspect")]
    object_id: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GetDynamicFieldTreeRequest {
    #[schemars(description = "Parent object ID")]
    object_id: String,
    #[schemars(description = "Maximum recursion depth (default 2)")]
    max_depth: Option<usize>,
    #[schemars(description = "Limit per level (default 50)")]
    limit: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GenerateMoveCallFormSchemaRequest {
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Maximum struct expansion depth (default 2)")]
    max_struct_depth: Option<usize>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct SuggestMoveCallInputsRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Limit owned objects to scan")]
    limit: Option<usize>,
    #[schemars(description = "Optional gas budget for auto gas selection")]
    gas_budget: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ResolveMoveCallArgsRequest {
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments")]
    type_args: Vec<String>,
    #[schemars(description = "Arguments as JSON values")]
    arguments: Vec<Value>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct AutoExecuteMoveCallRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments")]
    type_args: Vec<String>,
    #[schemars(description = "Arguments as JSON values")]
    arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
    #[schemars(description = "ZkLogin inputs JSON string from prover")]
    zk_login_inputs_json: String,
    #[schemars(description = "Address seed used for zkLogin (decimal string)")]
    address_seed: String,
    #[schemars(description = "Maximum epoch for the zkLogin signature")]
    max_epoch: u64,
    #[schemars(description = "Ephemeral user signature over tx bytes (base64 flag||sig||pubkey)")]
    user_signature: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct PrepareMoveCallRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments")]
    type_args: Vec<String>,
    #[schemars(description = "Arguments as JSON values")]
    arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: u64,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct AutoFillMoveCallRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments (optional, will infer if empty)")]
    type_args: Option<Vec<String>>,
    #[schemars(description = "Arguments as JSON values; use null or '<auto>' for object params")]
    arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct DappManifestRequest {
    #[schemars(
        description = "Optional manifest file path (defaults to SUI_DAPP_MANIFEST or ./dapps.json)"
    )]
    path: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct DappMoveCallRequest {
    #[schemars(description = "Dapp name as listed in manifest")]
    dapp: String,
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments (optional)")]
    type_args: Option<Vec<String>>,
    #[schemars(description = "Arguments as JSON values; use null or '<auto>' for object params")]
    arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction (optional)")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
    #[schemars(
        description = "Optional manifest file path (defaults to SUI_DAPP_MANIFEST or ./dapps.json)"
    )]
    manifest_path: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct DappManifest {
    dapps: Vec<DappEntry>,
}

#[derive(Debug, Deserialize, Serialize)]
struct DappEntry {
    name: String,
    package: String,
    modules: Option<Vec<String>>,
    functions: Option<Vec<DappFunctionEntry>>,
}

#[derive(Debug, Deserialize, Serialize)]
struct DappFunctionEntry {
    module: String,
    function: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct AutoPrepareMoveCallRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Type arguments (optional, will infer if empty)")]
    type_args: Option<Vec<String>>,
    #[schemars(description = "Arguments as JSON values; use null or '<auto>' for object params")]
    arguments: Vec<Value>,
    #[schemars(description = "Gas budget for the transaction")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object ID")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price override")]
    gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GenerateMoveCallPayloadRequest {
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Package object ID")]
    package: String,
    #[schemars(description = "Move module name")]
    module: String,
    #[schemars(description = "Move function name")]
    function: String,
    #[schemars(description = "Optional gas budget")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas price")]
    gas_price: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GraphqlQueryRequest {
    #[schemars(description = "GraphQL endpoint (defaults to SUI_GRAPHQL_URL)")]
    endpoint: Option<String>,
    #[schemars(description = "GraphQL query string")]
    query: String,
    #[schemars(description = "GraphQL variables")]
    variables: Option<Value>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct RpcServiceInfoRequest {
    #[schemars(description = "gRPC endpoint (defaults to SUI_GRPC_URL)")]
    endpoint: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct VerifySimpleSignatureRequest {
    #[schemars(description = "Message bytes (base64)")]
    message_base64: String,
    #[schemars(description = "Simple signature (base64 flag||sig||pk)")]
    signature_base64: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct GraphqlHelperRequest {
    #[schemars(description = "GraphQL endpoint (defaults to SUI_GRAPHQL_URL)")]
    endpoint: Option<String>,
    #[schemars(
        description = "Helper type: chain_info|object|balance|transaction|checkpoint|events|coins"
    )]
    helper: String,
    #[schemars(description = "Optional address for balance")]
    address: Option<String>,
    #[schemars(description = "Optional object id")]
    object_id: Option<String>,
    #[schemars(description = "Optional transaction digest")]
    digest: Option<String>,
    #[schemars(description = "Optional checkpoint sequence")]
    checkpoint: Option<u64>,
    #[schemars(description = "Optional limit")]
    limit: Option<u64>,
    #[schemars(description = "Optional selection set for helper")]
    selection: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct IntentRequest {
    #[schemars(description = "Natural language instruction")]
    text: String,
    #[schemars(description = "Optional sender address")]
    sender: Option<String>,
    #[schemars(description = "Optional network override")]
    network: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct IntentExecuteRequest {
    #[schemars(description = "Natural language instruction")]
    text: String,
    #[schemars(description = "Sender address")]
    sender: String,
    #[schemars(description = "Optional network override")]
    network: Option<String>,
    #[schemars(description = "Optional input coins for transfers/staking")]
    input_coins: Option<Vec<String>>,
    #[schemars(description = "Optional amount override")]
    amount: Option<u64>,
    #[schemars(description = "Optional recipient")]
    recipient: Option<String>,
    #[schemars(description = "Optional object id (transfer object)")]
    object_id: Option<String>,
    #[schemars(description = "Optional validator address for staking")]
    validator: Option<String>,
    #[schemars(description = "Optional staked SUI object id for withdraw")]
    staked_sui: Option<String>,
    #[schemars(description = "Optional package for move call intents")]
    package: Option<String>,
    #[schemars(description = "Optional module for move call intents")]
    module: Option<String>,
    #[schemars(description = "Optional function for move call intents")]
    function: Option<String>,
    #[schemars(description = "Optional type arguments for move call intents")]
    type_args: Option<Vec<String>>,
    #[schemars(description = "Optional arguments for move call intents")]
    arguments: Option<Vec<Value>>,
    #[schemars(description = "Gas budget")]
    gas_budget: Option<u64>,
    #[schemars(description = "Optional gas object id")]
    gas_object_id: Option<String>,
    #[schemars(description = "Optional gas price")]
    gas_price: Option<u64>,
    #[schemars(description = "ZkLogin inputs JSON string from prover")]
    zk_login_inputs_json: Option<String>,
    #[schemars(description = "Address seed used for zkLogin (decimal string)")]
    address_seed: Option<String>,
    #[schemars(description = "Maximum epoch for the zkLogin signature")]
    max_epoch: Option<u64>,
    #[schemars(description = "Ephemeral user signature over tx bytes (base64 flag||sig||pubkey)")]
    user_signature: Option<String>,
}

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
