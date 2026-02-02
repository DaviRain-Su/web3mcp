use anyhow::Result;
use serde_json::{json, Value};

pub fn extract_revert_reason(err: &str) -> Option<Value> {
    if err.trim().is_empty() {
        return None;
    }

    let lower = err.to_lowercase();

    if let Some(pos) = lower.find("execution reverted") {
        if let Some(colon) = err[pos..].find(':') {
            let reason = err[pos + colon + 1..].trim();
            if !reason.is_empty() {
                return Some(json!({"kind":"execution_reverted","reason":reason}));
            }
        }
        return Some(json!({"kind":"execution_reverted"}));
    }

    fn extract_hex_after(hay: &str, needle: &str) -> Option<String> {
        let idx = hay.to_lowercase().find(&needle.to_lowercase())?;
        let s = &hay[idx..];
        let start = s.find("0x")?;
        let s = &s[start..];
        let mut end = 2;
        for (i, ch) in s[2..].char_indices() {
            if ch.is_ascii_hexdigit() {
                end = 2 + i + ch.len_utf8();
            } else {
                break;
            }
        }
        let hex = &s[..end];
        if hex.len() > 2 {
            Some(hex.to_string())
        } else {
            None
        }
    }

    // Solidity Error(string)
    if let Some(hexdata) = extract_hex_after(err, "0x08c379a0") {
        let raw = hex::decode(hexdata.trim_start_matches("0x")).ok()?;
        if raw.len() >= 4 {
            let payload = &raw[4..];
            if let Ok(tokens) = ethers::abi::decode(&[ethers::abi::ParamType::String], payload) {
                if let Some(s) = tokens.first().and_then(|t| t.clone().into_string()) {
                    return Some(json!({"kind":"error_string","selector":"0x08c379a0","reason":s}));
                }
            }
        }
    }

    // Solidity Panic(uint256)
    if let Some(hexdata) = extract_hex_after(err, "0x4e487b71") {
        let raw = hex::decode(hexdata.trim_start_matches("0x")).ok()?;
        if raw.len() >= 4 {
            let payload = &raw[4..];
            if let Ok(tokens) = ethers::abi::decode(&[ethers::abi::ParamType::Uint(256)], payload) {
                if let Some(code) = tokens.first().and_then(|t| t.clone().into_uint()) {
                    return Some(json!({
                        "kind":"panic",
                        "selector":"0x4e487b71",
                        "code": code.to_string()
                    }));
                }
            }
        }
    }

    None
}

pub fn standard_event_abi() -> Result<ethers::abi::Abi> {
    // A minimal, self-contained ABI containing the most common standard events.
    let abi_json = r#"[
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"approved","type":"address"},{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"Approval","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":false,"internalType":"bool","name":"approved","type":"bool"}],"name":"ApprovalForAll","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"TransferSingle","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"ids","type":"uint256[]"},{"indexed":false,"internalType":"uint256[]","name":"values","type":"uint256[]"}],"name":"TransferBatch","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":false,"internalType":"bool","name":"approved","type":"bool"}],"name":"ApprovalForAll","type":"event"},
  {"anonymous":false,"inputs":[{"indexed":false,"internalType":"string","name":"value","type":"string"},{"indexed":true,"internalType":"uint256","name":"id","type":"uint256"}],"name":"URI","type":"event"}
]"#;

    Ok(serde_json::from_str::<ethers::abi::Abi>(abi_json)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_execution_reverted() {
        let v = extract_revert_reason("execution reverted: NOPE").unwrap();
        assert_eq!(v["kind"], "execution_reverted");
        assert_eq!(v["reason"], "NOPE");
    }

    #[test]
    fn parse_error_string_selector() {
        let reason = "insufficient balance";
        let mut raw = Vec::new();
        raw.extend_from_slice(&hex::decode("08c379a0").unwrap());
        raw.extend_from_slice(&ethers::abi::encode(&[ethers::abi::Token::String(
            reason.to_string(),
        )]));

        let err = format!("rpc error: 0x{}", hex::encode(raw));
        let v = extract_revert_reason(&err).unwrap();
        assert_eq!(v["kind"], "error_string");
        assert_eq!(v["reason"], reason);
    }

    #[test]
    fn standard_abi_contains_transfer_event() {
        let abi = standard_event_abi().unwrap();
        let mut found = false;
        for ev in abi.events() {
            if ev.name == "Transfer" {
                found = true;
                break;
            }
        }
        assert!(found);
    }
}
