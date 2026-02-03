use rmcp::model::{ErrorCode, ErrorData};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::borrow::Cow;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverrideRecord {
    pub run_id: String,
    pub token: String,
    pub created_ms: u64,
    pub expires_ms: u64,
    pub reason: String,
    pub approval_snapshot: Option<Value>,
}

fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn default_ttl_ms() -> u64 {
    5 * 60 * 1000
}

fn override_path(run_id: &str) -> Result<PathBuf, ErrorData> {
    let store = crate::utils::run_store::RunStore::new();
    let dir = store.ensure_run_dir(run_id).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to ensure run dir: {e}")),
        data: None,
    })?;
    Ok(dir.join("override.json"))
}

pub fn create_override(
    run_id: &str,
    reason: &str,
    ttl_ms: Option<u64>,
    approval_snapshot: Option<Value>,
) -> Result<OverrideRecord, ErrorData> {
    let created_ms = now_ms();
    let ttl = ttl_ms.unwrap_or_else(default_ttl_ms);
    let expires_ms = created_ms.saturating_add(ttl);

    let token = uuid::Uuid::new_v4().to_string();

    let rec = OverrideRecord {
        run_id: run_id.to_string(),
        token,
        created_ms,
        expires_ms,
        reason: reason.to_string(),
        approval_snapshot,
    };

    let path = override_path(run_id)?;
    let bytes = serde_json::to_vec_pretty(&rec).unwrap_or_else(|_| b"{}".to_vec());
    fs::write(&path, bytes).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to write override record: {e}")),
        data: Some(serde_json::json!({"path": path})),
    })?;

    Ok(rec)
}

pub fn load_override(run_id: &str) -> Result<Option<OverrideRecord>, ErrorData> {
    let path = override_path(run_id)?;
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs::read(&path).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to read override record: {e}")),
        data: Some(serde_json::json!({"path": path})),
    })?;

    let rec: OverrideRecord = serde_json::from_slice(&bytes).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to parse override record: {e}")),
        data: Some(serde_json::json!({"path": path})),
    })?;

    Ok(Some(rec))
}

pub fn validate_override(run_id: &str, token: &str) -> Result<(bool, Option<Value>), ErrorData> {
    let now = now_ms();
    let rec = match load_override(run_id)? {
        Some(r) => r,
        None => return Ok((false, None)),
    };

    if rec.run_id != run_id {
        return Ok((false, None));
    }

    if now > rec.expires_ms {
        return Ok((false, Some(serde_json::json!({
            "reason": "expired",
            "expires_ms": rec.expires_ms,
            "now_ms": now
        }))));
    }

    if rec.token != token {
        return Ok((false, Some(serde_json::json!({
            "reason": "token_mismatch"
        }))));
    }

    Ok((true, Some(serde_json::json!({
        "created_ms": rec.created_ms,
        "expires_ms": rec.expires_ms,
        "reason": rec.reason,
        "approval_snapshot": rec.approval_snapshot
    }))))
}
