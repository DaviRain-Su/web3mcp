use rmcp::model::{ErrorCode, ErrorData};
use serde_json::{json, Value};
use std::borrow::Cow;

/// Best-effort helper: for a given Anchor IDL arg type, return allowed enum variants (if the type
/// is or contains an enum).
///
/// Supports:
/// - {"defined":"MyEnum"}
/// - {"option": {"defined":"MyEnum"}}
/// - {"vec": {"defined":"MyEnum"}} (returns enum variants, still useful)
pub fn enum_variants_for_type(idl: &Value, ty: &Value) -> Option<Vec<String>> {
    // Unwrap option/vec/array
    if let Some(obj) = ty.as_object() {
        if let Some(inner) = obj.get("option") {
            return enum_variants_for_type(idl, inner);
        }
        if let Some(inner) = obj.get("vec") {
            return enum_variants_for_type(idl, inner);
        }
        if let Some(arrspec) = obj.get("array").and_then(|a| a.as_array()) {
            if !arrspec.is_empty() {
                return enum_variants_for_type(idl, &arrspec[0]);
            }
        }
        if let Some(def) = obj.get("defined").and_then(|d| d.as_str()) {
            return enum_variants_for_defined(idl, def).ok().flatten();
        }
    }

    None
}

fn enum_variants_for_defined(idl: &Value, name: &str) -> Result<Option<Vec<String>>, ErrorData> {
    let ty = idl
        .get("types")
        .and_then(|v| v.as_array())
        .and_then(|arr| {
            arr.iter().find(|t| {
                t.get("name")
                    .and_then(|n| n.as_str())
                    .map(|s| s == name)
                    .unwrap_or(false)
            })
        })
        .and_then(|t| t.get("type"))
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Unknown defined type in IDL"),
            data: Some(json!({"defined": name})),
        })?;

    let kind = ty.get("kind").and_then(|k| k.as_str()).unwrap_or("");
    if kind != "enum" {
        return Ok(None);
    }

    let variants = ty
        .get("variants")
        .and_then(|x| x.as_array())
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Defined enum missing variants[]"),
            data: Some(json!({"defined": name})),
        })?;

    let mut out: Vec<String> = Vec::new();
    for v in variants {
        if let Some(n) = v.get("name").and_then(|x| x.as_str()) {
            out.push(n.to_string());
        }
    }

    Ok(Some(out))
}
