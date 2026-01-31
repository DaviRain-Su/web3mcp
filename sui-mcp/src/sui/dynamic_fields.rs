use crate::SuiMcpServer;
use rmcp::model::*;
use serde_json::{json, Value};
use std::borrow::Cow;
use std::future::Future;
use std::pin::Pin;
use sui_json_rpc_types::SuiTypeTag;
use sui_types::base_types::ObjectID;
use sui_types::dynamic_field::{DynamicFieldName, DynamicFieldType};

impl SuiMcpServer {
    pub fn parse_dynamic_field_name(
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

    pub fn fetch_dynamic_field_tree<'a>(
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
