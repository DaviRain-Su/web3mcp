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

mod types;
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
