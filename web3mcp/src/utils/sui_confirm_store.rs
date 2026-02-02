#![allow(dead_code)]

use rmcp::model::{ErrorCode, ErrorData};
use serde_json::Value;
use std::borrow::Cow;

#[derive(Clone, Debug)]
pub struct SuiPendingRow {
    pub id: String,
    pub tx_bytes_b64: String,
    pub created_at_ms: u128,
    pub updated_at_ms: u128,
    pub expires_at_ms: u128,
    pub tx_summary_hash: String,
    pub status: String,
    pub digest: Option<String>,
    pub last_error: Option<String>,

    // Human-friendly summary fields
    pub tool_context: Option<String>,
    pub summary_json: Option<String>,

    // Optional confirm-time dry-run capture
    pub last_dry_run_json: Option<String>,
    pub last_dry_run_error: Option<String>,
}

fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_else(|_| std::time::Duration::from_millis(0))
        .as_millis()
}

pub fn default_ttl_ms() -> u128 {
    10 * 60 * 1000
}

fn pending_db_path_from_cwd() -> Result<std::path::PathBuf, ErrorData> {
    let cwd = std::env::current_dir().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to get current_dir: {}", e)),
        data: None,
    })?;
    Ok(cwd.join(".data").join("pending.sqlite"))
}

pub fn connect() -> Result<rusqlite::Connection, ErrorData> {
    let path = pending_db_path_from_cwd()?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to create data dir: {}", e)),
            data: None,
        })?;
    }

    let conn = rusqlite::Connection::open(path).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to open sqlite db: {}", e)),
        data: None,
    })?;

    conn.execute_batch(
        "BEGIN;
         CREATE TABLE IF NOT EXISTS sui_pending_confirmations (
           id TEXT PRIMARY KEY,
           tx_bytes_b64 TEXT NOT NULL,
           created_at_ms INTEGER NOT NULL,
           expires_at_ms INTEGER NOT NULL,
           tx_summary_hash TEXT NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_sui_pending_expires ON sui_pending_confirmations(expires_at_ms);
         COMMIT;",
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to init sqlite schema: {}", e)),
        data: None,
    })?;

    // Migrations via PRAGMA
    let mut existing_cols = std::collections::HashSet::<String>::new();
    {
        let mut stmt = conn
            .prepare("PRAGMA table_info(sui_pending_confirmations)")
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
        for name in rows.flatten() {
            existing_cols.insert(name);
        }
    }

    let migrations: [(&str, &str); 8] = [
        (
            "updated_at_ms",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN updated_at_ms INTEGER",
        ),
        (
            "status",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN status TEXT",
        ),
        (
            "digest",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN digest TEXT",
        ),
        (
            "last_error",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN last_error TEXT",
        ),
        (
            "tool_context",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN tool_context TEXT",
        ),
        (
            "summary_json",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN summary_json TEXT",
        ),
        (
            "last_dry_run_json",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN last_dry_run_json TEXT",
        ),
        (
            "last_dry_run_error",
            "ALTER TABLE sui_pending_confirmations ADD COLUMN last_dry_run_error TEXT",
        ),
    ];
    for (col, stmt) in migrations {
        if !existing_cols.contains(col) {
            conn.execute(stmt, []).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("SQLite migration failed: {} ({})", stmt, e)),
                data: None,
            })?;
        }
    }

    let _ = conn.execute(
        "UPDATE sui_pending_confirmations
         SET updated_at_ms = COALESCE(updated_at_ms, created_at_ms),
             status = COALESCE(status, 'pending')
         WHERE updated_at_ms IS NULL OR status IS NULL",
        [],
    );

    Ok(conn)
}

pub fn tx_summary_hash(tx_bytes: &[u8]) -> String {
    let h = ethers::utils::keccak256(tx_bytes);
    format!("0x{}", hex::encode(h))
}

pub fn insert_pending(
    id: &str,
    tx_bytes_b64: &str,
    created_at_ms: u128,
    expires_at_ms: u128,
    tx_summary_hash: &str,
    tool_context: &str,
    summary: Option<Value>,
) -> Result<(), ErrorData> {
    let conn = connect()?;
    let summary_json =
        summary.map(|v| serde_json::to_string(&v).unwrap_or_else(|_| "{}".to_string()));

    conn.execute(
        "INSERT OR REPLACE INTO sui_pending_confirmations
         (id, tx_bytes_b64, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, tool_context, summary_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', ?7, ?8)",
        rusqlite::params![
            id,
            tx_bytes_b64,
            created_at_ms as i64,
            now_ms() as i64,
            expires_at_ms as i64,
            tx_summary_hash,
            tool_context,
            summary_json,
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to insert pending sui confirmation: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn get_row(conn: &rusqlite::Connection, id: &str) -> Result<Option<SuiPendingRow>, ErrorData> {
    let mut stmt = conn
        .prepare(
            "SELECT id, tx_bytes_b64, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash,
                    status, digest, last_error, tool_context, summary_json, last_dry_run_json, last_dry_run_error
             FROM sui_pending_confirmations
             WHERE id=?1",
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to prepare get_row: {}", e)),
            data: None,
        })?;

    let mut rows = stmt.query([id]).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to query row: {}", e)),
        data: None,
    })?;

    if let Some(r) = rows.next().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to read row: {}", e)),
        data: None,
    })? {
        let id: String = r.get(0).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 0: {}", e)),
            data: None,
        })?;
        let tx_bytes_b64: String = r.get(1).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 1: {}", e)),
            data: None,
        })?;
        let created_at_ms: i64 = r.get(2).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 2: {}", e)),
            data: None,
        })?;
        let updated_at_ms: i64 = r.get(3).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 3: {}", e)),
            data: None,
        })?;
        let expires_at_ms: i64 = r.get(4).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 4: {}", e)),
            data: None,
        })?;
        let tx_summary_hash: String = r.get(5).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 5: {}", e)),
            data: None,
        })?;
        let status: Option<String> = r.get(6).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 6: {}", e)),
            data: None,
        })?;
        let digest: Option<String> = r.get(7).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 7: {}", e)),
            data: None,
        })?;
        let last_error: Option<String> = r.get(8).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 8: {}", e)),
            data: None,
        })?;
        let tool_context: Option<String> = r.get(9).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 9: {}", e)),
            data: None,
        })?;
        let summary_json: Option<String> = r.get(10).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 10: {}", e)),
            data: None,
        })?;
        let last_dry_run_json: Option<String> = r.get(11).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 11: {}", e)),
            data: None,
        })?;
        let last_dry_run_error: Option<String> = r.get(12).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode row field 12: {}", e)),
            data: None,
        })?;

        return Ok(Some(SuiPendingRow {
            id,
            tx_bytes_b64,
            created_at_ms: created_at_ms.max(0) as u128,
            updated_at_ms: updated_at_ms.max(0) as u128,
            expires_at_ms: expires_at_ms.max(0) as u128,
            tx_summary_hash,
            status: status.unwrap_or_else(|| "pending".to_string()),
            digest,
            last_error,
            tool_context,
            summary_json,
            last_dry_run_json,
            last_dry_run_error,
        }));
    }

    Ok(None)
}

pub fn mark_consumed(conn: &rusqlite::Connection, id: &str) -> Result<(), ErrorData> {
    conn.execute(
        "UPDATE sui_pending_confirmations SET status='consumed', updated_at_ms=?2 WHERE id=?1",
        rusqlite::params![id, now_ms() as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark consumed: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_pending(conn: &rusqlite::Connection, id: &str) -> Result<(), ErrorData> {
    conn.execute(
        "UPDATE sui_pending_confirmations
         SET status='pending', last_error=NULL, updated_at_ms=?2
         WHERE id=?1",
        rusqlite::params![id, now_ms() as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark pending: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_sent(conn: &rusqlite::Connection, id: &str, digest: &str) -> Result<(), ErrorData> {
    conn.execute(
        "UPDATE sui_pending_confirmations
         SET status='sent', digest=?2, updated_at_ms=?3
         WHERE id=?1",
        rusqlite::params![id, digest, now_ms() as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark sent: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_failed(conn: &rusqlite::Connection, id: &str, err: &str) -> Result<(), ErrorData> {
    conn.execute(
        "UPDATE sui_pending_confirmations
         SET status='failed', last_error=?2, updated_at_ms=?3
         WHERE id=?1",
        rusqlite::params![id, err, now_ms() as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark failed: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn set_last_dry_run(
    conn: &rusqlite::Connection,
    id: &str,
    dry_run: &Value,
    err: Option<&str>,
) -> Result<(), ErrorData> {
    let dry_run_json = serde_json::to_string(dry_run).unwrap_or_else(|_| "{}".to_string());
    conn.execute(
        "UPDATE sui_pending_confirmations
         SET last_dry_run_json=?2, last_dry_run_error=?3, updated_at_ms=?4
         WHERE id=?1",
        rusqlite::params![id, dry_run_json, err, now_ms() as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to set last dry-run: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn cleanup_expired(conn: &rusqlite::Connection, now_ms: u128) -> Result<(), ErrorData> {
    conn.execute(
        "DELETE FROM sui_pending_confirmations WHERE expires_at_ms < ?1",
        [now_ms as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to cleanup expired: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn extract_confirmation_id(text: &str) -> Option<String> {
    for raw in text.split_whitespace() {
        let t = raw.trim_matches(|c: char| c == ',' || c == ')' || c == '(');
        if t.starts_with("sui_confirm_") {
            return Some(t.to_string());
        }
    }
    None
}

pub fn extract_tx_summary_hash(text: &str) -> Option<String> {
    for raw in text.split_whitespace() {
        if let Some(rest) = raw.strip_prefix("hash:") {
            return Some(rest.to_string());
        }
        if raw.starts_with("0x") && raw.len() == 66 {
            return Some(raw.to_string());
        }
    }
    None
}

pub fn pretty_json(v: &Value) -> Result<String, ErrorData> {
    serde_json::to_string_pretty(v).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to render JSON: {}", e)),
        data: None,
    })
}
