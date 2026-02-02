use crate::{AutoFillMoveCallRequest, SuiMcpServer};
use move_core_types::language_storage::{StructTag, TypeTag};
use rmcp::model::*;
use serde_json::{json, Value};
use std::borrow::Cow;
use std::collections::HashMap;
use sui_json_rpc_types::{SuiObjectDataOptions, SuiObjectResponseQuery};
use sui_types::base_types::ObjectID;
use sui_types::object::Owner;

#[derive(Debug, Clone)]
pub(crate) struct AutoFilledMoveCall {
    pub type_args: Vec<String>,
    pub arguments: Vec<Value>,
    pub gas_budget: Option<u64>,
    pub gas_object_id: Option<String>,
    pub gas_price: Option<u64>,
    pub warnings: Vec<Value>,
    pub gas: Option<Value>,
}

impl SuiMcpServer {
    pub(crate) async fn auto_fill_move_call_internal(
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
            } else if !owner_kinds.is_empty() {
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
}
