use serde_json::{json, Value};

/// Best-effort example generator for Anchor IDL arg values.
///
/// Goal: help agents/users understand the *shape* expected by complex types
/// (option/vec/array/defined enum/struct) without needing bespoke per-program docs.
///
/// This is intentionally conservative and small.
pub fn example_for_type(idl: &Value, ty: &Value) -> Option<Value> {
    // Primitive string types
    if let Some(t) = ty.as_str() {
        return match t {
            "bool" => Some(json!(true)),
            "u8" | "u16" | "u32" | "u64" => Some(json!("123")),
            "i8" | "i16" | "i32" | "i64" => Some(json!("-123")),
            // Force strings for 128-bit ints.
            "u128" => Some(json!("123")),
            "i128" => Some(json!("-123")),
            "string" => Some(json!("...")),
            "publicKey" | "pubkey" => Some(json!("<BASE58_PUBKEY>")),
            "bytes" => Some(json!({"_bytes": {"hex": "0x...", "base64": "..."}})),
            _ => None,
        };
    }

    // Composite types
    if let Some(obj) = ty.as_object() {
        if let Some(inner) = obj.get("option") {
            return Some(json!({
                "_option": {
                    "some": example_for_type(idl, inner),
                    "or_null": null
                }
            }));
        }
        if let Some(inner) = obj.get("vec") {
            return Some(json!([example_for_type(idl, inner).unwrap_or(json!(null))]));
        }
        if let Some(arrspec) = obj.get("array").and_then(|a| a.as_array()) {
            if !arrspec.is_empty() {
                return Some(json!([example_for_type(idl, &arrspec[0]).unwrap_or(json!(null))]));
            }
        }
        if let Some(def) = obj.get("defined").and_then(|d| d.as_str()) {
            return example_for_defined(idl, def);
        }
    }

    None
}

fn example_for_defined(idl: &Value, name: &str) -> Option<Value> {
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
        .and_then(|t| t.get("type"))?;

    let kind = ty.get("kind").and_then(|k| k.as_str()).unwrap_or("");
    match kind {
        "struct" => {
            let fields = ty.get("fields")?.as_array()?;
            let mut obj = serde_json::Map::new();
            for f in fields.iter().take(6) {
                let fname = f.get("name")?.as_str()?.to_string();
                let fty = f.get("type").cloned().unwrap_or(Value::Null);
                obj.insert(fname, example_for_type(idl, &fty).unwrap_or(json!(null)));
            }
            Some(Value::Object(obj))
        }
        "enum" => {
            let variants = ty.get("variants")?.as_array()?;
            let names: Vec<String> = variants
                .iter()
                .filter_map(|v| v.get("name").and_then(|x| x.as_str()).map(|s| s.to_string()))
                .collect();

            let shown: Vec<String> = names.into_iter().take(3).collect();
            if shown.is_empty() {
                return None;
            }

            let primary = &shown[0];
            let other = if shown.len() > 1 { Some(&shown[1..]) } else { None };

            Some(json!({
                "_enum": {
                    "variants": shown,
                    "as_string_for_unit": primary,
                    "as_object": { primary: null },
                    "as_tagged": { "variant": primary, "value": null },
                    "other_variants": other
                }
            }))
        }
        _ => None,
    }
}
