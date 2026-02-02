use rmcp::model::{ErrorCode, ErrorData};
use rusqlite::OptionalExtension as _;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::borrow::Cow;

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

pub fn pending_db_path_from_cwd() -> Result<std::path::PathBuf, ErrorData> {
    let cwd = std::env::current_dir().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to get current_dir: {}", e)),
        data: None,
    })?;
    Ok(cwd.join(".data").join("pending.sqlite"))
}

fn legacy_json_store_path_from_cwd() -> Result<std::path::PathBuf, ErrorData> {
    let cwd = std::env::current_dir().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to get current_dir: {}", e)),
        data: None,
    })?;
    Ok(cwd.join("confirm_store").join("solana_confirm_store.json"))
}

pub fn store_path() -> std::path::PathBuf {
    pending_db_path_from_cwd().unwrap_or_else(|_| std::path::PathBuf::from(".data/pending.sqlite"))
}

fn connect() -> Result<rusqlite::Connection, ErrorData> {
    let path = pending_db_path_from_cwd()?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to create data dir: {}", e)),
            data: None,
        })?;
    }

    let mut conn = rusqlite::Connection::open(path).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to open sqlite db: {}", e)),
        data: None,
    })?;

    // Base schema
    conn.execute_batch(
        "BEGIN;
         CREATE TABLE IF NOT EXISTS solana_pending_confirmations (
           id TEXT PRIMARY KEY,
           tx_base64 TEXT NOT NULL,
           created_at_ms INTEGER NOT NULL,
           expires_at_ms INTEGER NOT NULL,
           tx_summary_hash TEXT NOT NULL,
           source_tool TEXT NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_solana_pending_expires ON solana_pending_confirmations(expires_at_ms);
         COMMIT;",
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to init sqlite schema: {}", e)),
        data: None,
    })?;

    // Migrations
    let mut existing_cols = std::collections::HashSet::<String>::new();
    {
        let mut stmt = conn
            .prepare("PRAGMA table_info(solana_pending_confirmations)")
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to prepare PRAGMA table_info: {}", e)),
                data: None,
            })?;
        let rows = stmt
            .query_map([], |row| row.get::<_, String>(1))
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to query PRAGMA table_info: {}", e)),
                data: None,
            })?;
        for c in rows.flatten() {
            existing_cols.insert(c);
        }
    }

    let mut alters: Vec<&str> = Vec::new();
    if !existing_cols.contains("updated_at_ms") {
        alters.push("ALTER TABLE solana_pending_confirmations ADD COLUMN updated_at_ms INTEGER");
    }
    if !existing_cols.contains("status") {
        alters.push("ALTER TABLE solana_pending_confirmations ADD COLUMN status TEXT");
    }
    if !existing_cols.contains("signature") {
        alters.push("ALTER TABLE solana_pending_confirmations ADD COLUMN signature TEXT");
    }
    if !existing_cols.contains("last_error") {
        alters.push("ALTER TABLE solana_pending_confirmations ADD COLUMN last_error TEXT");
    }
    if !existing_cols.contains("summary_json") {
        alters.push("ALTER TABLE solana_pending_confirmations ADD COLUMN summary_json TEXT");
    }

    for sql in alters {
        let _ = conn.execute(sql, []);
    }

    let _ = conn.execute(
        "UPDATE solana_pending_confirmations
         SET updated_at_ms = COALESCE(updated_at_ms, created_at_ms),
             status = COALESCE(status, 'pending')
         WHERE updated_at_ms IS NULL OR status IS NULL",
        [],
    );

    // Best-effort migrate legacy JSON store into sqlite (one-way, keep file).
    migrate_legacy_json_store_if_needed(&mut conn)?;

    Ok(conn)
}

fn migrate_legacy_json_store_if_needed(conn: &mut rusqlite::Connection) -> Result<(), ErrorData> {
    // If legacy store exists and sqlite table is empty, import.
    let legacy_path = legacy_json_store_path_from_cwd()?;
    if !legacy_path.exists() {
        return Ok(());
    }

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(1) FROM solana_pending_confirmations",
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);

    if count > 0 {
        return Ok(());
    }

    let data = std::fs::read_to_string(&legacy_path).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to read legacy solana confirm store: {}", e)),
        data: Some(serde_json::json!({"path": legacy_path.to_string_lossy()})),
    })?;

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    struct LegacyStore {
        pending: std::collections::BTreeMap<String, PendingSolanaConfirmation>,
    }

    let store: LegacyStore = serde_json::from_str(&data).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Invalid legacy solana confirm store json: {}", e)),
        data: Some(serde_json::json!({"path": legacy_path.to_string_lossy()})),
    })?;

    let tx = conn.transaction().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to start sqlite transaction: {}", e)),
        data: None,
    })?;

    for (id, v) in store.pending {
        let summary_json = v
            .summary
            .as_ref()
            .map(|vv| serde_json::to_string(vv).unwrap_or_else(|_| "{}".to_string()));

        let _ = tx.execute(
            "INSERT OR REPLACE INTO solana_pending_confirmations
             (id, tx_base64, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, signature, last_error, source_tool, summary_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', NULL, NULL, ?7, ?8)",
            rusqlite::params![
                id,
                v.tx_base64,
                v.created_ms as i64,
                v.created_ms as i64,
                v.expires_ms as i64,
                v.tx_summary_hash,
                v.source_tool,
                summary_json,
            ],
        );
    }

    tx.commit().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to commit sqlite transaction: {}", e)),
        data: None,
    })?;

    Ok(())
}

pub fn tx_summary_hash(tx_bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let h = Sha256::digest(tx_bytes);
    hex::encode(h)
}

pub fn make_confirm_token(id: &str, tx_summary_hash: &str) -> String {
    use sha2::{Digest, Sha256};
    let msg = format!("solana:{}:{}", id, tx_summary_hash);
    let h = Sha256::digest(msg.as_bytes());
    format!("0x{}", hex::encode(h))
}

pub fn list_pending() -> Result<Vec<PendingSolanaConfirmation>, ErrorData> {
    let conn = connect()?;
    let now = now_ms() as i64;

    // best-effort cleanup expired
    let _ = conn.execute(
        "DELETE FROM solana_pending_confirmations WHERE expires_at_ms < ?1",
        [now],
    );

    let mut stmt = conn
        .prepare(
            "SELECT id, tx_base64, created_at_ms, expires_at_ms, tx_summary_hash, source_tool, summary_json
             FROM solana_pending_confirmations
             WHERE status='pending'
             ORDER BY created_at_ms DESC",
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to prepare list_pending: {}", e)),
            data: None,
        })?;

    let rows = stmt
        .query_map([], |row| {
            let summary_json: Option<String> = row.get(6)?;
            let summary = summary_json
                .as_deref()
                .and_then(|s| serde_json::from_str::<Value>(s).ok());
            Ok(PendingSolanaConfirmation {
                id: row.get(0)?,
                tx_base64: row.get(1)?,
                created_ms: row.get::<_, i64>(2)? as u64,
                expires_ms: row.get::<_, i64>(3)? as u64,
                tx_summary_hash: row.get(4)?,
                source_tool: row.get(5)?,
                summary,
            })
        })
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to query list_pending: {}", e)),
            data: None,
        })?;

    let mut out: Vec<PendingSolanaConfirmation> = Vec::new();
    for v in rows.flatten() {
        out.push(v);
    }
    Ok(out)
}

pub fn cleanup(
    delete_older_than_ms: Option<u64>,
    now: u64,
) -> Result<serde_json::Value, ErrorData> {
    let conn = connect()?;

    let before: i64 = conn
        .query_row(
            "SELECT COUNT(1) FROM solana_pending_confirmations WHERE status='pending'",
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);

    // Always remove expired
    let _ = conn.execute(
        "DELETE FROM solana_pending_confirmations WHERE expires_at_ms < ?1",
        [now as i64],
    );

    // Optionally remove old entries by created_at_ms
    if let Some(age) = delete_older_than_ms {
        let cutoff = now.saturating_sub(age);
        let _ = conn.execute(
            "DELETE FROM solana_pending_confirmations WHERE created_at_ms < ?1",
            [cutoff as i64],
        );
    }

    let after: i64 = conn
        .query_row(
            "SELECT COUNT(1) FROM solana_pending_confirmations WHERE status='pending'",
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);

    let removed = (before - after).max(0);

    Ok(serde_json::json!({
        "before": before,
        "after": after,
        "removed": removed
    }))
}

pub fn cleanup_expired() -> Result<usize, ErrorData> {
    let conn = connect()?;
    let now = now_ms() as i64;
    let before: i64 = conn
        .query_row(
            "SELECT COUNT(1) FROM solana_pending_confirmations WHERE status='pending'",
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);

    let _ = conn.execute(
        "DELETE FROM solana_pending_confirmations WHERE expires_at_ms < ?1",
        [now],
    );

    let after: i64 = conn
        .query_row(
            "SELECT COUNT(1) FROM solana_pending_confirmations WHERE status='pending'",
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);

    Ok((before - after).max(0) as usize)
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
    let conn = connect()?;

    let summary_json = summary
        .as_ref()
        .map(|v| serde_json::to_string(v).unwrap_or_else(|_| "{}".to_string()));

    conn.execute(
        "INSERT OR REPLACE INTO solana_pending_confirmations
         (id, tx_base64, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, signature, last_error, source_tool, summary_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', NULL, NULL, ?7, ?8)",
        rusqlite::params![
            id,
            tx_base64,
            created_ms as i64,
            now_ms() as i64,
            expires_ms as i64,
            tx_summary_hash,
            source_tool,
            summary_json,
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to insert pending solana confirmation: {}", e)),
        data: None,
    })?;

    Ok(())
}

pub fn get_pending(id: &str) -> Result<PendingSolanaConfirmation, ErrorData> {
    let conn = connect()?;
    let mut stmt = conn
        .prepare(
            "SELECT id, tx_base64, created_at_ms, expires_at_ms, tx_summary_hash, source_tool, summary_json
             FROM solana_pending_confirmations
             WHERE id=?1 AND status='pending'",
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to prepare get_pending: {}", e)),
            data: None,
        })?;

    let row_opt = stmt
        .query_row([id], |row| {
            let summary_json: Option<String> = row.get(6)?;
            let summary = summary_json
                .as_deref()
                .and_then(|s| serde_json::from_str::<Value>(s).ok());
            Ok(PendingSolanaConfirmation {
                id: row.get(0)?,
                tx_base64: row.get(1)?,
                created_ms: row.get::<_, i64>(2)? as u64,
                expires_ms: row.get::<_, i64>(3)? as u64,
                tx_summary_hash: row.get(4)?,
                source_tool: row.get(5)?,
                summary,
            })
        })
        .optional()
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to query get_pending: {}", e)),
            data: None,
        })?;

    row_opt.ok_or_else(|| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from("Unknown confirmation id"),
        data: Some(serde_json::json!({"id": id})),
    })
}

pub fn remove_pending(id: &str) -> Result<(), ErrorData> {
    let conn = connect()?;
    conn.execute("DELETE FROM solana_pending_confirmations WHERE id=?1", [id])
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!(
                "Failed to remove pending solana confirmation: {}",
                e
            )),
            data: None,
        })?;
    Ok(())
}
