use crate::Web3McpServer;
use rmcp::model::*;
use serde_json::{json, Value};
use std::borrow::Cow;
use sui_json_rpc_types::{
    SuiMoveNormalizedFunction, SuiMoveNormalizedModule, SuiMoveNormalizedType,
};
use sui_types::object::Owner;

impl Web3McpServer {
    pub fn format_move_type(ty: &SuiMoveNormalizedType) -> String {
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

    pub fn move_param_hint(ty: &SuiMoveNormalizedType) -> (String, Value, bool) {
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

    pub fn param_requirements(ty: &SuiMoveNormalizedType) -> (bool, Vec<&'static str>) {
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

    pub fn owner_kind(owner: &Owner) -> &'static str {
        match owner {
            Owner::AddressOwner(_) => "owned",
            Owner::ObjectOwner(_) => "object_owner",
            Owner::Shared { .. } => "shared",
            Owner::Immutable => "immutable",
            Owner::ConsensusAddressOwner { .. } => "consensus",
        }
    }

    pub fn is_auto_arg(value: &Value) -> bool {
        matches!(value, Value::Null)
            || matches!(value, Value::String(s) if s == "<auto>" || s == "auto")
    }

    pub fn validate_pure_arg(ty: &SuiMoveNormalizedType, value: &Value) -> Result<(), ErrorData> {
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

    pub fn build_move_call_template(
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

    pub fn move_type_schema(
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
            SuiMoveNormalizedType::TypeParameter(index) => {
                json!({"type": "string", "x-move-type": format!("T{}", index)})
            }
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

    pub fn move_call_form_schema(
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
}
