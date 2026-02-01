use rmcp::model::{ErrorCode, ErrorData};
use serde_json::Value;
use sha2::{Digest, Sha256};
use base64::Engine;
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

pub fn normalize_idl_instruction(idl: &Value, ix_name: &str) -> Result<IdlInstruction, ErrorData> {
    let ix = idl
        .get("instructions")
        .and_then(|v| v.as_array())
        .and_then(|arr| {
            arr.iter()
                .find(|i| i.get("name").and_then(|n| n.as_str()).map(|s| s == ix_name) == Some(true))
        })
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Instruction not found in IDL (expected idl.instructions[].name)"),
            data: Some(serde_json::json!({"instruction": ix_name})),
        })?;

    let accounts = ix
        .get("accounts")
        .and_then(|v| v.as_array())
        .ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("IDL instruction missing accounts[]"),
            data: Some(serde_json::json!({"instruction": ix_name})),
        })?
        .iter()
        .map(|a| {
            let name = a
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let is_mut = a.get("isMut").and_then(|v| v.as_bool()).unwrap_or(false);
            let is_signer = a
                .get("isSigner")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            IdlAccount {
                name,
                is_mut,
                is_signer,
            }
        })
        .collect::<Vec<_>>();

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

pub fn encode_anchor_ix_data(ix_name: &str, args: &[(IdlArg, Value)]) -> Result<Vec<u8>, ErrorData> {
    let mut out = Vec::new();
    out.extend_from_slice(&anchor_discriminator(ix_name));
    for (arg, v) in args {
        let mut enc = encode_borsh_value(&arg.ty, v)?;
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

pub fn encode_borsh_value(ty: &Value, v: &Value) -> Result<Vec<u8>, ErrorData> {
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
            out.extend_from_slice(&encode_borsh_value(inner, v)?);
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
                out.extend_from_slice(&encode_borsh_value(inner, x)?);
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
                        message: Cow::from(format!("Expected array length {} but got {}", len, arr.len())),
                        data: None,
                    });
                }
                let mut out = Vec::new();
                for x in arr {
                    out.extend_from_slice(&encode_borsh_value(inner, x)?);
                }
                return Ok(out);
            }
        }

        if let Some(def) = obj.get("defined") {
            // For now: we don't expand custom defined structs/enums.
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("defined types not supported yet (provide primitive/vec/option)"),
                data: Some(serde_json::json!({"defined": def})),
            });
        }
    }

    Err(ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Unsupported IDL type"),
        data: Some(serde_json::json!({"type": ty, "value": v})),
    })
}

fn encode_borsh_primitive(t: &str, v: &Value) -> Result<Vec<u8>, ErrorData> {
    match t {
        "bool" => Ok(vec![if v.as_bool().unwrap_or(false) { 1 } else { 0 }]),
        "u8" => Ok(vec![as_u64(v).ok_or_else(|| err_expected(t))? as u8]),
        "i8" => Ok(vec![as_i64(v).ok_or_else(|| err_expected(t))? as i8 as u8]),
        "u16" => Ok((as_u64(v).ok_or_else(|| err_expected(t))? as u16).to_le_bytes().to_vec()),
        "i16" => Ok((as_i64(v).ok_or_else(|| err_expected(t))? as i16).to_le_bytes().to_vec()),
        "u32" => Ok((as_u64(v).ok_or_else(|| err_expected(t))? as u32).to_le_bytes().to_vec()),
        "i32" => Ok((as_i64(v).ok_or_else(|| err_expected(t))? as i32).to_le_bytes().to_vec()),
        "u64" => Ok((as_u64(v).ok_or_else(|| err_expected(t))? as u64).to_le_bytes().to_vec()),
        "i64" => Ok((as_i64(v).ok_or_else(|| err_expected(t))? as i64).to_le_bytes().to_vec()),
        "u128" => {
            let n = v
                .as_str()
                .and_then(|s| s.parse::<u128>().ok())
                .or_else(|| v.as_u64().map(|x| x as u128))
                .ok_or_else(|| err_expected(t))?;
            Ok(n.to_le_bytes().to_vec())
        }
        "i128" => {
            let n = v
                .as_str()
                .and_then(|s| s.parse::<i128>().ok())
                .or_else(|| v.as_i64().map(|x| x as i128))
                .ok_or_else(|| err_expected(t))?;
            Ok(n.to_le_bytes().to_vec())
        }
        "string" => {
            let s = v.as_str().ok_or_else(|| err_expected(t))?;
            let mut out = Vec::new();
            out.extend_from_slice(&(s.len() as u32).to_le_bytes());
            out.extend_from_slice(s.as_bytes());
            Ok(out)
        }
        "publicKey" | "pubkey" => {
            let s = v.as_str().ok_or_else(|| err_expected(t))?;
            let pk = solana_sdk::pubkey::Pubkey::from_str(s).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid publicKey: {}", e)),
                data: None,
            })?;
            Ok(pk.to_bytes().to_vec())
        }
        "bytes" => {
            let b = as_bytes(v).ok_or_else(|| err_expected(t))?;
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

fn err_expected(t: &str) -> ErrorData {
    ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from(format!("Invalid value for type {}", t)),
        data: None,
    }
}
