use base64::Engine;
use rmcp::model::{ErrorCode, ErrorData};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::str::FromStr;

#[derive(Clone, Debug)]
pub struct IdlArg {
    pub name: String,
    pub ty: Value,
}

#[derive(Clone, Debug)]
pub struct IdlAccount {
    pub name: String,
    pub is_mut: bool,
    pub is_signer: bool,
}

#[derive(Clone, Debug)]
pub struct IdlInstruction {
    pub name: String,
    pub accounts: Vec<IdlAccount>,
    pub args: Vec<IdlArg>,
}

fn flatten_idl_accounts(accounts: &Value, out: &mut Vec<IdlAccount>) {
    // Anchor IDL accounts can be either:
    // - flat: [{name,isMut,isSigner}, ...]
    // - nested: [{name, accounts:[...]}, ...]
    // We'll flatten nested structures (dropping the grouping node).
    if let Some(arr) = accounts.as_array() {
        for a in arr {
            if let Some(inner) = a.get("accounts") {
                flatten_idl_accounts(inner, out);
                continue;
            }

            let name = a
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            if name.is_empty() {
                continue;
            }
            let is_mut = a.get("isMut").and_then(|v| v.as_bool()).unwrap_or(false);
            let is_signer = a.get("isSigner").and_then(|v| v.as_bool()).unwrap_or(false);
            out.push(IdlAccount {
                name,
                is_mut,
                is_signer,
            });
        }
    }
}

pub fn normalize_idl_instruction(idl: &Value, ix_name: &str) -> Result<IdlInstruction, ErrorData> {
    let ix = idl
        .get("instructions")
        .and_then(|v| v.as_array())
        .and_then(|arr| {
            arr.iter().find(|i| {
                i.get("name").and_then(|n| n.as_str()).map(|s| s == ix_name) == Some(true)
            })
        })
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Instruction not found in IDL (expected idl.instructions[].name)"),
            data: Some(serde_json::json!({"instruction": ix_name})),
        })?;

    let accounts_raw = ix.get("accounts").ok_or_else(|| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("IDL instruction missing accounts"),
        data: Some(serde_json::json!({"instruction": ix_name})),
    })?;

    let mut accounts: Vec<IdlAccount> = Vec::new();
    flatten_idl_accounts(accounts_raw, &mut accounts);

    let args = ix
        .get("args")
        .and_then(|v| v.as_array())
        .unwrap_or(&vec![])
        .iter()
        .map(|a| {
            let name = a
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let ty = a.get("type").cloned().unwrap_or(Value::Null);
            IdlArg { name, ty }
        })
        .collect::<Vec<_>>();

    Ok(IdlInstruction {
        name: ix_name.to_string(),
        accounts,
        args,
    })
}

pub fn anchor_discriminator(ix_name: &str) -> [u8; 8] {
    let preimage = format!("global:{}", ix_name);
    let h = Sha256::digest(preimage.as_bytes());
    let mut out = [0u8; 8];
    out.copy_from_slice(&h[..8]);
    out
}

pub fn encode_anchor_ix_data(
    idl: &Value,
    ix_name: &str,
    args: &[(IdlArg, Value)],
) -> Result<Vec<u8>, ErrorData> {
    let mut out = Vec::new();
    out.extend_from_slice(&anchor_discriminator(ix_name));
    for (arg, v) in args {
        let mut enc = encode_borsh_value(idl, &arg.ty, v)?;
        out.append(&mut enc);
    }
    Ok(out)
}

fn as_u64(v: &Value) -> Option<u64> {
    if let Some(n) = v.as_u64() {
        return Some(n);
    }
    if let Some(s) = v.as_str() {
        return s.parse::<u64>().ok();
    }
    None
}

fn as_i64(v: &Value) -> Option<i64> {
    if let Some(n) = v.as_i64() {
        return Some(n);
    }
    if let Some(s) = v.as_str() {
        return s.parse::<i64>().ok();
    }
    None
}

fn as_bytes(v: &Value) -> Option<Vec<u8>> {
    if let Some(s) = v.as_str() {
        // accept 0x... hex or base64
        if let Some(hex) = s.strip_prefix("0x") {
            return hex::decode(hex).ok();
        }
        if let Ok(b) = base64::engine::general_purpose::STANDARD.decode(s.as_bytes()) {
            return Some(b);
        }
        return None;
    }
    if let Some(arr) = v.as_array() {
        let mut out = Vec::new();
        for x in arr {
            let b = x.as_u64()?;
            out.push(b as u8);
        }
        return Some(out);
    }
    None
}

pub fn encode_borsh_value(idl: &Value, ty: &Value, v: &Value) -> Result<Vec<u8>, ErrorData> {
    // Anchor IDL types:
    // - string literal: "u64" | "bool" | "string" | "publicKey" | "bytes" | ...
    // - object: {"vec": <type>} | {"option": <type>} | {"array": [<type>, <len>]} | {"defined": "Type"}

    if let Some(t) = ty.as_str() {
        return encode_borsh_primitive(t, v);
    }

    if let Some(obj) = ty.as_object() {
        if let Some(inner) = obj.get("option") {
            // Option<T>: u8 tag then value
            if v.is_null() {
                return Ok(vec![0u8]);
            }
            let mut out = vec![1u8];
            out.extend_from_slice(&encode_borsh_value(idl, inner, v)?);
            return Ok(out);
        }

        if let Some(inner) = obj.get("vec") {
            let arr = v.as_array().ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Expected array for vec type"),
                data: Some(serde_json::json!({"value": v})),
            })?;
            let mut out = Vec::new();
            out.extend_from_slice(&(arr.len() as u32).to_le_bytes());
            for x in arr {
                out.extend_from_slice(&encode_borsh_value(idl, inner, x)?);
            }
            return Ok(out);
        }

        if let Some(arrspec) = obj.get("array").and_then(|a| a.as_array()) {
            if arrspec.len() == 2 {
                let inner = &arrspec[0];
                let len = as_u64(&arrspec[1]).unwrap_or(0) as usize;
                let arr = v.as_array().ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Expected array for fixed array type"),
                    data: None,
                })?;
                if arr.len() != len {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Expected array length {} but got {}",
                            len,
                            arr.len()
                        )),
                        data: None,
                    });
                }
                let mut out = Vec::new();
                for x in arr {
                    out.extend_from_slice(&encode_borsh_value(idl, inner, x)?);
                }
                return Ok(out);
            }
        }

        if let Some(def) = obj.get("defined") {
            let name = def.as_str().unwrap_or("");
            return encode_defined_type(idl, name, v);
        }
    }

    Err(ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Unsupported IDL type"),
        data: Some(serde_json::json!({"type": ty, "value": v})),
    })
}

fn idl_find_defined<'a>(idl: &'a Value, name: &str) -> Option<&'a Value> {
    idl.get("types")
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
}

fn encode_defined_type(idl: &Value, name: &str, v: &Value) -> Result<Vec<u8>, ErrorData> {
    let ty = idl_find_defined(idl, name).ok_or_else(|| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Unknown defined type in IDL"),
        data: Some(serde_json::json!({"defined": name})),
    })?;

    let kind = ty.get("kind").and_then(|k| k.as_str()).unwrap_or("");
    match kind {
        "struct" => encode_defined_struct(idl, name, ty, v),
        "enum" => encode_defined_enum(idl, name, ty, v),
        _ => Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Unsupported defined type kind"),
            data: Some(serde_json::json!({"defined": name, "kind": kind})),
        }),
    }
}

fn encode_defined_struct(
    idl: &Value,
    name: &str,
    ty: &Value,
    v: &Value,
) -> Result<Vec<u8>, ErrorData> {
    let fields = ty
        .get("fields")
        .and_then(|f| f.as_array())
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Defined struct missing fields[]"),
            data: Some(serde_json::json!({"defined": name})),
        })?;

    let obj = v.as_object().ok_or_else(|| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Expected object for struct value"),
        data: Some(serde_json::json!({"defined": name, "value": v})),
    })?;

    let mut out = Vec::new();
    for f in fields {
        let fname = f.get("name").and_then(|x| x.as_str()).unwrap_or("");
        let fty = f.get("type").cloned().unwrap_or(Value::Null);
        let fv = obj.get(fname).cloned().unwrap_or(Value::Null);

        // If field type is option and value missing, we can treat as null.
        if fv.is_null() {
            // If the field isn't option, this will error downstream; that's fine.
        }

        out.extend_from_slice(&encode_borsh_value(idl, &fty, &fv)?);
    }
    Ok(out)
}

fn encode_defined_enum(
    idl: &Value,
    name: &str,
    ty: &Value,
    v: &Value,
) -> Result<Vec<u8>, ErrorData> {
    let variants = ty
        .get("variants")
        .and_then(|x| x.as_array())
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Defined enum missing variants[]"),
            data: Some(serde_json::json!({"defined": name})),
        })?;

    // Accept:
    // - "VariantName" (string) for no-field variants
    // - {"VariantName": <payload>} (single-key object)
    // - {"variant":"VariantName","value":<payload>} / {"variant":"VariantName","fields":<payload>}

    let (variant_name, payload): (String, Value) = if let Some(s) = v.as_str() {
        (s.to_string(), Value::Null)
    } else if let Some(obj) = v.as_object() {
        if let Some(var) = obj.get("variant").and_then(|x| x.as_str()) {
            let p = obj
                .get("value")
                .or_else(|| obj.get("fields"))
                .cloned()
                .unwrap_or(Value::Null);
            (var.to_string(), p)
        } else if obj.len() == 1 {
            let (k, val) = obj.iter().next().unwrap();
            (k.to_string(), val.clone())
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Enum value must be string or single-key object"),
                data: Some(serde_json::json!({"defined": name, "value": v})),
            });
        }
    } else {
        return Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Enum value must be string or object"),
            data: Some(serde_json::json!({"defined": name, "value": v})),
        });
    };

    let mut idx: Option<u8> = None;
    let mut variant_def: Option<&Value> = None;
    for (i, vv) in variants.iter().enumerate() {
        let n = vv.get("name").and_then(|x| x.as_str()).unwrap_or("");
        if n == variant_name {
            idx = Some(i as u8);
            variant_def = Some(vv);
            break;
        }
    }

    let idx = idx.ok_or_else(|| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Unknown enum variant"),
        data: Some(serde_json::json!({"defined": name, "variant": variant_name})),
    })?;
    let variant_def = variant_def.unwrap();

    let mut out = vec![idx];

    let fields = variant_def.get("fields");
    if fields.is_none() {
        // no payload
        return Ok(out);
    }

    // fields can be array of types or array of named {name,type}
    let empty: Vec<Value> = Vec::new();
    let fields_arr = fields.and_then(|x| x.as_array()).unwrap_or(&empty);
    let named = fields_arr.first().and_then(|x| x.get("name")).is_some();

    if named {
        let pobj = payload.as_object().ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Expected object payload for named enum variant"),
            data: Some(
                serde_json::json!({"defined": name, "variant": variant_name, "payload": payload}),
            ),
        })?;

        for f in fields_arr {
            let fname = f.get("name").and_then(|x| x.as_str()).unwrap_or("");
            let fty = f.get("type").cloned().unwrap_or(Value::Null);
            let fv = pobj.get(fname).cloned().unwrap_or(Value::Null);
            out.extend_from_slice(&encode_borsh_value(idl, &fty, &fv)?);
        }
    } else {
        let parr = payload.as_array().ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Expected array payload for tuple enum variant"),
            data: Some(
                serde_json::json!({"defined": name, "variant": variant_name, "payload": payload}),
            ),
        })?;

        if parr.len() != fields_arr.len() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Tuple enum payload length mismatch"),
                data: Some(serde_json::json!({
                    "defined": name,
                    "variant": variant_name,
                    "expected": fields_arr.len(),
                    "got": parr.len()
                })),
            });
        }

        for (i, f) in fields_arr.iter().enumerate() {
            // tuple fields may be raw type or {type: ...}
            let fty = f.get("type").cloned().unwrap_or_else(|| f.clone());
            out.extend_from_slice(&encode_borsh_value(idl, &fty, &parr[i])?);
        }
    }

    Ok(out)
}

fn encode_borsh_primitive(t: &str, v: &Value) -> Result<Vec<u8>, ErrorData> {
    match t {
        "bool" => Ok(vec![if v.as_bool().unwrap_or(false) { 1 } else { 0 }]),
        "u8" => Ok(vec![as_u64(v).ok_or_else(|| err_expected(t, v))? as u8]),
        "i8" => Ok(vec![as_i64(v).ok_or_else(|| err_expected(t, v))? as i8 as u8]),
        "u16" => Ok((as_u64(v).ok_or_else(|| err_expected(t, v))? as u16)
            .to_le_bytes()
            .to_vec()),
        "i16" => Ok((as_i64(v).ok_or_else(|| err_expected(t, v))? as i16)
            .to_le_bytes()
            .to_vec()),
        "u32" => Ok((as_u64(v).ok_or_else(|| err_expected(t, v))? as u32)
            .to_le_bytes()
            .to_vec()),
        "i32" => Ok((as_i64(v).ok_or_else(|| err_expected(t, v))? as i32)
            .to_le_bytes()
            .to_vec()),
        "u64" => Ok((as_u64(v).ok_or_else(|| err_expected(t, v))? as u64)
            .to_le_bytes()
            .to_vec()),
        "i64" => Ok((as_i64(v).ok_or_else(|| err_expected(t, v))? as i64)
            .to_le_bytes()
            .to_vec()),
        "u128" => {
            let n = v
                .as_str()
                .and_then(|s| s.parse::<u128>().ok())
                .or_else(|| v.as_u64().map(|x| x as u128))
                .ok_or_else(|| err_expected(t, v))?;
            Ok(n.to_le_bytes().to_vec())
        }
        "i128" => {
            let n = v
                .as_str()
                .and_then(|s| s.parse::<i128>().ok())
                .or_else(|| v.as_i64().map(|x| x as i128))
                .ok_or_else(|| err_expected(t, v))?;
            Ok(n.to_le_bytes().to_vec())
        }
        "string" => {
            let s = v.as_str().ok_or_else(|| err_expected(t, v))?;
            let mut out = Vec::new();
            out.extend_from_slice(&(s.len() as u32).to_le_bytes());
            out.extend_from_slice(s.as_bytes());
            Ok(out)
        }
        "publicKey" | "pubkey" => {
            let s = v.as_str().ok_or_else(|| err_expected(t, v))?;
            let pk = solana_sdk::pubkey::Pubkey::from_str(s).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid publicKey: {}", e)),
                data: None,
            })?;
            Ok(pk.to_bytes().to_vec())
        }
        "bytes" => {
            let b = as_bytes(v).ok_or_else(|| err_expected(t, v))?;
            let mut out = Vec::new();
            out.extend_from_slice(&(b.len() as u32).to_le_bytes());
            out.extend_from_slice(&b);
            Ok(out)
        }
        _ => Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Unsupported primitive type: {}", t)),
            data: None,
        }),
    }
}

fn err_expected(t: &str, v: &Value) -> ErrorData {
    // Improve debuggability for agent workflows.
    let hint = if v.is_number() {
        Some(
            "If this is an integer type, do not pass floats. Use an integer JSON number or a decimal string (e.g. \"1000000\")."
                .to_string(),
        )
    } else {
        None
    };

    ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from(format!("Invalid value for type {}", t)),
        data: Some(json!({
            "expected_type": t,
            "provided": v,
            "hint": hint
        })),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discriminator_matches_sha256_prefix() {
        let d = anchor_discriminator("initialize");
        let h = sha2::Sha256::digest(b"global:initialize");
        assert_eq!(&d[..], &h[..8]);
    }

    #[test]
    fn encode_defined_struct_and_enum() {
        // Minimal Anchor-style IDL with a struct + enum.
        let idl = serde_json::json!({
            "types": [
                {
                    "name": "MyStruct",
                    "type": {
                        "kind": "struct",
                        "fields": [
                            {"name": "a", "type": "u8"},
                            {"name": "b", "type": "u16"}
                        ]
                    }
                },
                {
                    "name": "MyEnum",
                    "type": {
                        "kind": "enum",
                        "variants": [
                            {"name": "A"},
                            {"name": "B", "fields": [{"name": "x", "type": "u64"}]},
                            {"name": "C", "fields": ["u8", "u8"]}
                        ]
                    }
                }
            ]
        });

        // struct: a=1, b=513 => [1, 1, 2]
        let s = serde_json::json!({"a": 1, "b": 513});
        let enc = encode_borsh_value(&idl, &serde_json::json!({"defined":"MyStruct"}), &s).unwrap();
        assert_eq!(enc, vec![1u8, 1u8, 2u8]);

        // enum A: variant index 0
        let a = serde_json::json!("A");
        let enc = encode_borsh_value(&idl, &serde_json::json!({"defined":"MyEnum"}), &a).unwrap();
        assert_eq!(enc, vec![0u8]);

        // enum B {x=9}: variant index 1 + u64(9)
        let b = serde_json::json!({"B": {"x": 9}});
        let enc = encode_borsh_value(&idl, &serde_json::json!({"defined":"MyEnum"}), &b).unwrap();
        assert_eq!(&enc[0..1], &[1u8]);
        assert_eq!(u64::from_le_bytes(enc[1..9].try_into().unwrap()), 9u64);

        // enum C tuple (7,8): variant index 2 + u8 + u8
        let c = serde_json::json!({"variant":"C","value":[7,8]});
        let enc = encode_borsh_value(&idl, &serde_json::json!({"defined":"MyEnum"}), &c).unwrap();
        assert_eq!(enc, vec![2u8, 7u8, 8u8]);
    }
}

#[cfg(test)]
mod accounts_flatten_tests {
    use super::*;

    #[test]
    fn flatten_nested_accounts() {
        let idl = serde_json::json!({
            "instructions": [
                {
                    "name": "ix",
                    "accounts": [
                        {"name": "a", "isMut": false, "isSigner": false},
                        {"name": "group", "accounts": [
                            {"name": "b", "isMut": true, "isSigner": false},
                            {"name": "c", "isMut": false, "isSigner": true}
                        ]}
                    ],
                    "args": []
                }
            ]
        });

        let ix = normalize_idl_instruction(&idl, "ix").unwrap();
        let names: Vec<String> = ix.accounts.into_iter().map(|a| a.name).collect();
        assert_eq!(names, vec!["a", "b", "c"]);
    }
}
