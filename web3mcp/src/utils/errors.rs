use crate::Web3McpServer;
use rmcp::model::*;
use std::borrow::Cow;

impl Web3McpServer {
    pub fn clamp_limit(limit: Option<usize>, default: usize, max: usize) -> usize {
        limit.unwrap_or(default).min(max)
    }

    pub fn sdk_error(context: &str, error: impl std::fmt::Display) -> ErrorData {
        let error_string = error.to_string();
        let mut message = format!("{} failed: {}", context, error_string);
        if let Some(hint) = Self::error_hint(&error_string) {
            message = format!("{} (hint: {})", message, hint);
        }
        ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(message),
            data: None,
        }
    }

    pub fn error_hint(error: &str) -> Option<&'static str> {
        let lower = error.to_lowercase();
        if lower.contains("insufficient gas") || lower.contains("insufficientgas") {
            return Some("Increase gas_budget or ensure your gas coin has enough balance");
        }
        if lower.contains("insufficient funds") || lower.contains("insufficientbalance") {
            return Some("Check sender balance or select different input coins");
        }
        if lower.contains("objectnotfound") || lower.contains("object not found") {
            return Some("Verify the object id and ownership, and ensure it still exists");
        }
        if lower.contains("locked") || lower.contains("sequencenumber") || lower.contains("version")
        {
            return Some(
                "The object may be locked or outdated; retry later or fetch the latest version",
            );
        }
        if lower.contains("signature") && lower.contains("invalid") {
            return Some(
                "Ensure the signer matches the transaction sender and the signature is correct",
            );
        }
        if lower.contains("gas budget")
            || lower.contains("gasbudget")
            || lower.contains("gas too low")
        {
            return Some("Increase gas_budget or rerun with gas estimation enabled");
        }
        if lower.contains("object locked") || lower.contains("objectlocked") {
            return Some("Object is locked by another transaction; retry after it completes");
        }
        if lower.contains("version") && lower.contains("mismatch") {
            return Some("Object version mismatch; refetch object and rebuild the transaction");
        }
        None
    }
}
