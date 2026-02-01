use rmcp::model::{ErrorCode, ErrorData};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::borrow::Cow;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingSolanaConfirmation {
    pub id: String,
    pub tx_base64: String,
    pub created_ms: u64,
    pub expires_ms: u64,
    pub tx_summary_hash: String,
    pub source_tool: String,
    pub summary: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Store {
    pub pending: BTreeMap<String, PendingSolanaConfirmation>,
}

pub fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

pub fn default_ttl_ms() -> u64 {
    15 * 60 * 1000
}

pub fn store_path() -> PathBuf {
    let mut p = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    p.push("confirm_store");
    p.push("solana_confirm_store.json");
    p
}

fn ensure_parent(path: &Path) -> Result<(), ErrorData> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to create confirm_store dir: {}", e)),
            data: Some(serde_json::json!({"dir": dir.to_string_lossy()})),
        })?;
    }
    Ok(())
}

fn read_store() -> Result<Store, ErrorData> {
    let path = store_path();
    if !path.exists() {
        return Ok(Store::default());
    }
    let data = fs::read_to_string(&path).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to read solana confirm store: {}", e)),
        data: Some(serde_json::json!({"path": path.to_string_lossy()})),
    })?;

    serde_json::from_str(&data).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Invalid solana confirm store json: {}", e)),
        data: Some(serde_json::json!({"path": path.to_string_lossy()})),
    })
}

fn write_store(store: &Store) -> Result<(), ErrorData> {
    let path = store_path();
    ensure_parent(&path)?;
    let data = serde_json::to_string_pretty(store).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to serialize solana confirm store: {}", e)),
        data: None,
    })?;
    fs::write(&path, data).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to write solana confirm store: {}", e)),
        data: Some(serde_json::json!({"path": path.to_string_lossy()})),
    })?;
    Ok(())
}

pub fn tx_summary_hash(tx_bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let h = Sha256::digest(tx_bytes);
    hex::encode(h)
}

pub fn cleanup_expired() -> Result<usize, ErrorData> {
    let mut store = read_store()?;
    let now = now_ms();
    let before = store.pending.len();
    store.pending.retain(|_, v| v.expires_ms > now);
    let removed = before.saturating_sub(store.pending.len());
    if removed > 0 {
        write_store(&store)?;
    }
    Ok(removed)
}

pub fn insert_pending(
    id: &str,
    tx_base64: &str,
    created_ms: u64,
    expires_ms: u64,
    tx_summary_hash: &str,
    source_tool: &str,
    summary: Option<Value>,
) -> Result<(), ErrorData> {
    let mut store = read_store()?;
    store.pending.insert(
        id.to_string(),
        PendingSolanaConfirmation {
            id: id.to_string(),
            tx_base64: tx_base64.to_string(),
            created_ms,
            expires_ms,
            tx_summary_hash: tx_summary_hash.to_string(),
            source_tool: source_tool.to_string(),
            summary,
        },
    );
    write_store(&store)
}

pub fn get_pending(id: &str) -> Result<PendingSolanaConfirmation, ErrorData> {
    let store = read_store()?;
    store.pending.get(id).cloned().ok_or_else(|| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Unknown confirmation id"),
        data: Some(serde_json::json!({"id": id})),
    })
}

pub fn remove_pending(id: &str) -> Result<(), ErrorData> {
    let mut store = read_store()?;
    store.pending.remove(id);
    write_store(&store)
}
