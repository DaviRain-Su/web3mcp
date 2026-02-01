use crate::types::EvmTxRequest;
use rmcp::model::{ErrorCode, ErrorData};
use serde_json::Value;
use std::borrow::Cow;

#[derive(Clone, Debug)]
pub struct PendingRow {
    pub id: String,
    pub chain_id: u64,
    pub tx: EvmTxRequest,
    pub created_at_ms: u128,
    pub updated_at_ms: u128,
    pub expires_at_ms: u128,
    pub tx_summary_hash: String,
    pub status: String,
    pub tx_hash: Option<String>,
    pub last_error: Option<String>,
    pub raw_tx_prefix: Option<String>,
    pub signed_at_ms: Option<u128>,
    pub second_confirm_token: Option<String>,
    pub second_confirmed: bool,
    // Optional metadata for approve safety checks
    pub expected_spender: Option<String>,
    pub required_allowance_raw: Option<String>,
    pub expected_token: Option<String>,
    pub approve_confirmation_id: Option<String>,
    pub swap_confirmation_id: Option<String>,
}

pub fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_else(|_| std::time::Duration::from_millis(0))
        .as_millis()
}

pub fn default_ttl_ms() -> u128 {
    10 * 60 * 1000
}

pub fn pending_db_path_from_cwd() -> Result<std::path::PathBuf, ErrorData> {
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

    // Base table (older versions).
    conn.execute_batch(
        "BEGIN;
         CREATE TABLE IF NOT EXISTS evm_pending_confirmations (
           id TEXT PRIMARY KEY,
           chain_id INTEGER NOT NULL,
           tx_json TEXT NOT NULL,
           created_at_ms INTEGER NOT NULL,
           expires_at_ms INTEGER NOT NULL,
           tx_summary_hash TEXT NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_evm_pending_expires ON evm_pending_confirmations(expires_at_ms);
         COMMIT;",
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to init sqlite schema: {}", e)),
        data: None,
    })?;

    // Migrations: add new columns if missing.
    // Use PRAGMA table_info to avoid depending on sqlite error strings.
    let mut existing_cols = std::collections::HashSet::<String>::new();
    {
        let mut stmt = conn
            .prepare("PRAGMA table_info(evm_pending_confirmations)")
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

    let migrations: [(&str, &str); 13] = [
        (
            "updated_at_ms",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN updated_at_ms INTEGER",
        ),
        (
            "status",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN status TEXT",
        ),
        (
            "tx_hash",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN tx_hash TEXT",
        ),
        (
            "last_error",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN last_error TEXT",
        ),
        (
            "raw_tx_prefix",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN raw_tx_prefix TEXT",
        ),
        (
            "signed_at_ms",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN signed_at_ms INTEGER",
        ),
        (
            "second_confirm_token",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN second_confirm_token TEXT",
        ),
        (
            "second_confirmed",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN second_confirmed INTEGER",
        ),
        (
            "expected_spender",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN expected_spender TEXT",
        ),
        (
            "required_allowance_raw",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN required_allowance_raw TEXT",
        ),
        (
            "expected_token",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN expected_token TEXT",
        ),
        (
            "approve_confirmation_id",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN approve_confirmation_id TEXT",
        ),
        (
            "swap_confirmation_id",
            "ALTER TABLE evm_pending_confirmations ADD COLUMN swap_confirmation_id TEXT",
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

    // Backfill defaults if needed.
    let _ = conn.execute(
        "UPDATE evm_pending_confirmations
         SET updated_at_ms = COALESCE(updated_at_ms, created_at_ms),
             status = COALESCE(status, 'pending'),
             second_confirmed = COALESCE(second_confirmed, 0)
         WHERE updated_at_ms IS NULL OR status IS NULL OR second_confirmed IS NULL",
        [],
    );

    Ok(conn)
}

pub fn cleanup_expired(conn: &rusqlite::Connection, now_ms: u128) -> Result<(), ErrorData> {
    conn.execute(
        "DELETE FROM evm_pending_confirmations WHERE expires_at_ms < ?1",
        [now_ms as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to cleanup expired confirmations: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn insert_pending(
    id: &str,
    tx: &EvmTxRequest,
    created_at_ms: u128,
    expires_at_ms: u128,
    tx_summary_hash: &str,
) -> Result<(), ErrorData> {
    let conn = connect()?;
    cleanup_expired(&conn, now_ms())?;

    let tx_json = serde_json::to_string(tx).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to serialize tx: {}", e)),
        data: None,
    })?;

    conn.execute(
        "INSERT OR REPLACE INTO evm_pending_confirmations
         (id, chain_id, tx_json, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, tx_hash, last_error)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'pending', NULL, NULL)",
        rusqlite::params![
            id,
            tx.chain_id as i64,
            tx_json,
            created_at_ms as i64,
            created_at_ms as i64,
            expires_at_ms as i64,
            tx_summary_hash
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to insert pending confirmation: {}", e)),
        data: None,
    })?;

    Ok(())
}

pub fn get_row(conn: &rusqlite::Connection, id: &str) -> Result<Option<PendingRow>, ErrorData> {
    cleanup_expired(conn, now_ms())?;

    let mut stmt = conn
        .prepare(
            "SELECT id, chain_id, tx_json, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, tx_hash, last_error,
                    raw_tx_prefix, signed_at_ms, second_confirm_token, second_confirmed,
                    expected_spender, required_allowance_raw, expected_token, approve_confirmation_id, swap_confirmation_id
             FROM evm_pending_confirmations
             WHERE id = ?1",
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to prepare select: {}", e)),
            data: None,
        })?;

    let row = match stmt.query_row([id], |row| {
        let id: String = row.get(0)?;
        let chain_id: i64 = row.get(1)?;
        let tx_json: String = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let updated_at_ms: i64 = row.get(4)?;
        let expires_at_ms: i64 = row.get(5)?;
        let tx_summary_hash: String = row.get(6)?;
        let status: String = row.get(7)?;
        let tx_hash: Option<String> = row.get(8)?;
        let last_error: Option<String> = row.get(9)?;
        let raw_tx_prefix: Option<String> = row.get(10)?;
        let signed_at_ms: Option<i64> = row.get(11)?;
        let second_confirm_token: Option<String> = row.get(12)?;
        let second_confirmed: Option<i64> = row.get(13)?;
        let expected_spender: Option<String> = row.get(14)?;
        let required_allowance_raw: Option<String> = row.get(15)?;
        let expected_token: Option<String> = row.get(16)?;
        let approve_confirmation_id: Option<String> = row.get(17)?;
        let swap_confirmation_id: Option<String> = row.get(18)?;
        Ok((
            id,
            chain_id,
            tx_json,
            created_at_ms,
            updated_at_ms,
            expires_at_ms,
            tx_summary_hash,
            status,
            tx_hash,
            last_error,
            raw_tx_prefix,
            signed_at_ms,
            second_confirm_token,
            second_confirmed.unwrap_or(0),
            expected_spender,
            required_allowance_raw,
            expected_token,
            approve_confirmation_id,
            swap_confirmation_id,
        ))
    }) {
        Ok(v) => Some(v),
        Err(rusqlite::Error::QueryReturnedNoRows) => None,
        Err(e) => {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to query row: {}", e)),
                data: None,
            })
        }
    };

    let Some((
        id,
        chain_id,
        tx_json,
        created_at_ms,
        updated_at_ms,
        expires_at_ms,
        tx_summary_hash,
        status,
        tx_hash,
        last_error,
        raw_tx_prefix,
        signed_at_ms,
        second_confirm_token,
        second_confirmed,
        expected_spender,
        required_allowance_raw,
        expected_token,
        approve_confirmation_id,
        swap_confirmation_id,
    )) = row
    else {
        return Ok(None);
    };

    let tx: EvmTxRequest = serde_json::from_str(&tx_json).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to parse tx_json: {}", e)),
        data: None,
    })?;

    Ok(Some(PendingRow {
        id,
        chain_id: chain_id as u64,
        tx,
        created_at_ms: created_at_ms as u128,
        updated_at_ms: updated_at_ms as u128,
        expires_at_ms: expires_at_ms as u128,
        tx_summary_hash,
        status,
        tx_hash,
        last_error,
        raw_tx_prefix,
        signed_at_ms: signed_at_ms.map(|v| v.max(0) as u128),
        second_confirm_token,
        second_confirmed: second_confirmed == 1,
        expected_spender,
        required_allowance_raw,
        expected_token,
        approve_confirmation_id,
        swap_confirmation_id,
    }))
}

pub fn ensure_second_confirmation(
    conn: &rusqlite::Connection,
    id: &str,
    tx_summary_hash: &str,
    user_text: &str,
    tx: &EvmTxRequest,
) -> Result<Option<(String, String)>, ErrorData> {
    // If not a large value tx, no second confirm needed.
    if !is_large_value(tx) {
        return Ok(None);
    }

    // Get current state.
    let mut stmt = conn
        .prepare(
            "SELECT second_confirm_token, second_confirmed FROM evm_pending_confirmations WHERE id = ?1",
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to prepare select: {}", e)),
            data: None,
        })?;

    let row = match stmt.query_row([id], |row| {
        let token: Option<String> = row.get(0)?;
        let confirmed: Option<i64> = row.get(1)?;
        Ok((token, confirmed.unwrap_or(0)))
    }) {
        Ok(v) => Some(v),
        Err(rusqlite::Error::QueryReturnedNoRows) => None,
        Err(e) => {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to query row: {}", e)),
                data: None,
            })
        }
    };

    let Some((token, confirmed)) = row else {
        return Ok(None);
    };

    if confirmed == 1 {
        return Ok(None);
    }

    // Ensure token exists.
    let token = token.unwrap_or_else(|| make_confirm_token(id, tx_summary_hash));

    // If user provided token, validate.
    let provided = extract_confirm_token(user_text);
    if let Some(p) = provided {
        if p == token {
            conn.execute(
                "UPDATE evm_pending_confirmations
                 SET second_confirm_token=?2, second_confirmed=1, updated_at_ms=?3
                 WHERE id=?1",
                rusqlite::params![id, token, now_ms() as i64],
            )
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to set second_confirmed: {}", e)),
                data: None,
            })?;
            return Ok(None);
        }
    }

    // Persist token (if not already).
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET second_confirm_token=?2, second_confirmed=0, updated_at_ms=?3
         WHERE id=?1",
        rusqlite::params![id, token, now_ms() as i64],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to store second_confirm_token: {}", e)),
        data: None,
    })?;

    // Return (token, message) to prompt user.
    let msg = format!(
        "Large value tx detected. Re-confirm with: confirm {} hash:{} token:{}",
        id, tx_summary_hash, token
    );
    Ok(Some((token, msg)))
}

pub fn update_pending(
    conn: &rusqlite::Connection,
    id: &str,
    tx: &EvmTxRequest,
    expires_at_ms: u128,
    tx_summary_hash: &str,
) -> Result<(), ErrorData> {
    cleanup_expired(conn, now_ms())?;

    let tx_json = serde_json::to_string(tx).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to serialize tx: {}", e)),
        data: None,
    })?;

    let updated_at_ms = now_ms() as i64;

    conn.execute(
        "UPDATE evm_pending_confirmations
         SET tx_json = ?2,
             updated_at_ms = ?3,
             expires_at_ms = ?4,
             tx_summary_hash = ?5,
             status = 'pending',
             tx_hash = NULL,
             last_error = NULL
         WHERE id = ?1",
        rusqlite::params![
            id,
            tx_json,
            updated_at_ms,
            expires_at_ms as i64,
            tx_summary_hash
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to update pending confirmation: {}", e)),
        data: None,
    })?;

    Ok(())
}

pub fn mark_consumed(conn: &rusqlite::Connection, id: &str) -> Result<(), ErrorData> {
    let updated_at_ms = now_ms() as i64;
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET status='consumed', updated_at_ms=?2
         WHERE id=?1",
        rusqlite::params![id, updated_at_ms],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark consumed: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_sent(conn: &rusqlite::Connection, id: &str, tx_hash: &str) -> Result<(), ErrorData> {
    let updated_at_ms = now_ms() as i64;
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET status='sent', tx_hash=?2, updated_at_ms=?3
         WHERE id=?1",
        rusqlite::params![id, tx_hash, updated_at_ms],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark sent: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_signed(conn: &rusqlite::Connection, id: &str, raw_tx: &str) -> Result<(), ErrorData> {
    let updated_at_ms = now_ms() as i64;
    let signed_at_ms = updated_at_ms;
    let prefix = raw_tx.chars().take(18).collect::<String>();
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET raw_tx_prefix=?2, signed_at_ms=?3, updated_at_ms=?4
         WHERE id=?1",
        rusqlite::params![id, prefix, signed_at_ms, updated_at_ms],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark signed: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_failed(conn: &rusqlite::Connection, id: &str, err: &str) -> Result<(), ErrorData> {
    let updated_at_ms = now_ms() as i64;
    conn.execute(
        "UPDATE evm_pending_confirmations SET status='failed', last_error=?2, updated_at_ms=?3 WHERE id=?1",
        rusqlite::params![id, err, updated_at_ms],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark failed: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn mark_skipped(conn: &rusqlite::Connection, id: &str, reason: &str) -> Result<(), ErrorData> {
    let updated_at_ms = now_ms() as i64;
    conn.execute(
        "UPDATE evm_pending_confirmations SET status='skipped', last_error=?2, updated_at_ms=?3 WHERE id=?1",
        rusqlite::params![id, reason, updated_at_ms],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to mark skipped: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn set_expected_allowance(
    id: &str,
    expected_token: &str,
    expected_spender: &str,
    required_allowance_raw: &str,
) -> Result<(), ErrorData> {
    let conn = connect()?;
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET expected_token=?2, expected_spender=?3, required_allowance_raw=?4, updated_at_ms=?5
         WHERE id=?1",
        rusqlite::params![
            id,
            expected_token,
            expected_spender,
            required_allowance_raw,
            now_ms() as i64
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to set expected allowance metadata: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn set_approve_link(
    swap_confirmation_id: &str,
    approve_confirmation_id: &str,
) -> Result<(), ErrorData> {
    let conn = connect()?;
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET approve_confirmation_id=?2, updated_at_ms=?3
         WHERE id=?1",
        rusqlite::params![
            swap_confirmation_id,
            approve_confirmation_id,
            now_ms() as i64
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to link approve confirmation: {}", e)),
        data: None,
    })?;
    Ok(())
}

pub fn set_swap_link(
    approve_confirmation_id: &str,
    swap_confirmation_id: &str,
) -> Result<(), ErrorData> {
    let conn = connect()?;
    conn.execute(
        "UPDATE evm_pending_confirmations
         SET swap_confirmation_id=?2, updated_at_ms=?3
         WHERE id=?1",
        rusqlite::params![
            approve_confirmation_id,
            swap_confirmation_id,
            now_ms() as i64
        ],
    )
    .map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to link swap confirmation: {}", e)),
        data: None,
    })?;
    Ok(())
}

#[allow(dead_code)]
pub fn delete_row(conn: &rusqlite::Connection, id: &str) -> Result<(), ErrorData> {
    conn.execute("DELETE FROM evm_pending_confirmations WHERE id = ?1", [id])
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to delete row: {}", e)),
            data: None,
        })?;
    Ok(())
}

pub fn tx_summary_hash(tx: &EvmTxRequest) -> String {
    let s = format!(
        "chain_id={}|from={}|to={}|value_wei={}|nonce={:?}|gas_limit={:?}|max_fee_per_gas_wei={:?}|max_priority_fee_per_gas_wei={:?}|data_hex={:?}",
        tx.chain_id,
        tx.from.to_lowercase(),
        tx.to.to_lowercase(),
        tx.value_wei,
        tx.nonce,
        tx.gas_limit,
        tx.max_fee_per_gas_wei,
        tx.max_priority_fee_per_gas_wei,
        tx.data_hex.as_ref().map(|d| d.to_lowercase())
    );
    let h = ethers::utils::keccak256(s.as_bytes());
    format!("0x{}", hex::encode(h))
}

pub fn extract_tx_summary_hash(text: &str) -> Option<String> {
    for raw in text.split_whitespace() {
        let t = raw.trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c));
        let t = t.strip_prefix("hash:").unwrap_or(t);
        let t = t.strip_prefix("summary:").unwrap_or(t);
        if t.starts_with("0x") && t.len() == 66 {
            return Some(t.to_lowercase());
        }
    }
    None
}

pub fn extract_confirmation_id(text: &str) -> Option<String> {
    for raw in text.split_whitespace() {
        let t = raw.trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c));
        if t.starts_with("evm_dryrun_") {
            return Some(t.to_string());
        }
        if t.starts_with("confirm_") {
            return Some(t.to_string());
        }
    }
    None
}

pub fn large_value_threshold_wei() -> ethers::types::U256 {
    // default: 0.01 ETH
    let default = ethers::types::U256::from_dec_str("10000000000000000").unwrap();
    let Ok(v) = std::env::var("EVM_CONFIRM_LARGE_VALUE_THRESHOLD_WEI") else {
        return default;
    };
    if let Ok(u) = ethers::types::U256::from_dec_str(v.trim()) {
        return u;
    }
    default
}

pub fn is_large_value(tx: &EvmTxRequest) -> bool {
    match ethers::types::U256::from_dec_str(tx.value_wei.trim()) {
        Ok(v) => v > large_value_threshold_wei(),
        Err(_) => false,
    }
}

pub fn extract_confirm_token(text: &str) -> Option<String> {
    for raw in text.split_whitespace() {
        let t = raw.trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c));
        if let Some(rest) = t.strip_prefix("token:") {
            if !rest.trim().is_empty() {
                return Some(rest.trim().to_string());
            }
        }
    }
    None
}

pub fn make_confirm_token(id: &str, tx_summary_hash: &str) -> String {
    let s = format!("{}:{}:{}", id, tx_summary_hash, now_ms());
    let h = ethers::utils::keccak256(s.as_bytes());
    // short token for human typing
    hex::encode(h)[0..10].to_string()
}

pub fn tx_summary_for_response(tx: &EvmTxRequest) -> Value {
    serde_json::json!({
        "chain_id": tx.chain_id,
        "from": tx.from,
        "to": tx.to,
        "value_wei": tx.value_wei,
        "nonce": tx.nonce,
        "gas_limit": tx.gas_limit,
        "max_fee_per_gas_wei": tx.max_fee_per_gas_wei,
        "max_priority_fee_per_gas_wei": tx.max_priority_fee_per_gas_wei,
        "data_prefix": tx.data_hex.as_ref().map(|d| d.chars().take(18).collect::<String>()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_tx_summary_hash() {
        let t = "confirm evm_dryrun_1_2 hash:0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef on base";
        assert_eq!(
            extract_tx_summary_hash(t).unwrap(),
            "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        );
    }

    #[test]
    fn test_tx_summary_hash_stable() {
        let tx = EvmTxRequest {
            chain_id: 84532,
            from: "0x1111111111111111111111111111111111111111".to_string(),
            to: "0x2222222222222222222222222222222222222222".to_string(),
            value_wei: "0".to_string(),
            data_hex: Some("0x1234".to_string()),
            nonce: Some(1),
            gas_limit: Some(21000),
            max_fee_per_gas_wei: Some("1".to_string()),
            max_priority_fee_per_gas_wei: Some("0".to_string()),
        };
        let h1 = tx_summary_hash(&tx);
        let h2 = tx_summary_hash(&tx);
        assert_eq!(h1, h2);
        assert!(h1.starts_with("0x") && h1.len() == 66);
    }
}
