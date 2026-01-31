use crate::SuiMcpServer;
use move_core_types::language_storage::{StructTag, TypeTag};
use std::collections::HashMap;
use sui_json_rpc_types::SuiMoveNormalizedType;

impl SuiMcpServer {
    pub fn is_object_param_match(param: &SuiMoveNormalizedType, tag: &StructTag) -> bool {
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

    pub fn match_type_param(
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

    pub fn infer_type_args(
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

    pub fn merge_type_args(
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

    pub fn type_args_from_mapping(mapping: &HashMap<usize, TypeTag>, count: usize) -> Vec<String> {
        (0..count)
            .map(|index| {
                mapping
                    .get(&index)
                    .map(|tag| tag.to_string())
                    .unwrap_or_else(|| format!("<T{}>", index))
            })
            .collect()
    }
}
