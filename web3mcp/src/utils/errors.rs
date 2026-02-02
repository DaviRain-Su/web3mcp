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

        let info = Self::classify_error(context, &error_string);
        if let Some(hint) = Self::error_hint(&error_string) {
            message = format!("{} (hint: {})", message, hint);
        }

        ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(message),
            data: Some(info),
        }
    }

    pub fn classify_error(context: &str, error: &str) -> serde_json::Value {
        let lower = error.to_lowercase();
        let ctx = context.to_lowercase();

        let chain = if ctx.contains("solana") {
            "solana"
        } else if ctx.contains("sui") {
            "sui"
        } else if ctx.contains("evm") {
            "evm"
        } else {
            "system"
        };

        // Default
        let mut error_class = "UNKNOWN";
        let mut retryable = false;
        let mut suggest_fix: Option<&'static str> = None;

        // Transport / RPC
        if lower.contains("timed out")
            || lower.contains("timeout")
            || lower.contains("connection refused")
            || lower.contains("dns")
            || lower.contains("failed to connect")
            || lower.contains("connection reset")
            || lower.contains("429")
            || lower.contains("rate limit")
        {
            error_class = "RPC_UNAVAILABLE";
            retryable = true;
            suggest_fix = Some("Retry; if persistent, verify RPC URL / network selection and consider switching RPC endpoint");
        }

        // Funds
        if lower.contains("insufficient funds")
            || lower.contains("insufficientfunds")
            || lower.contains("insufficient balance")
            || lower.contains("insufficientbalance")
        {
            error_class = "INSUFFICIENT_FUNDS";
            retryable = false;
            suggest_fix =
                Some("Check sender balance and ensure the fee payer has enough funds for fees");
        }

        // Signer / signature
        if (lower.contains("signature") && lower.contains("invalid"))
            || lower.contains("signature verification")
            || lower.contains("signature verification failure")
        {
            error_class = "SIGNATURE_INVALID";
            retryable = false;
            suggest_fix = Some("Ensure the signer/keypair matches the transaction sender and re-sign the transaction");
        }

        // Solana-specific
        if chain == "solana" {
            if lower.contains("blockhash not found")
                || lower.contains("blockhash") && lower.contains("expired")
            {
                error_class = "BLOCKHASH_EXPIRED";
                retryable = true;
                suggest_fix =
                    Some("Fetch a fresh recent_blockhash, rebuild the transaction, then resend");
            }
            if lower.contains("account in use") {
                error_class = "ACCOUNT_IN_USE";
                retryable = true;
                suggest_fix = Some(
                    "Retry later; if it persists, wait for conflicting transaction to finalize",
                );
            }
        }

        // EVM-specific
        if chain == "evm" {
            if lower.contains("nonce too low") {
                error_class = "NONCE_TOO_LOW";
                retryable = true;
                suggest_fix =
                    Some("Refetch nonce (pending), rebuild the tx with updated nonce, then retry");
            }
            if lower.contains("replacement transaction underpriced") {
                error_class = "REPLACEMENT_UNDERPRICED";
                retryable = true;
                suggest_fix = Some("Increase maxFeePerGas/maxPriorityFeePerGas and retry");
            }
            if lower.contains("intrinsic gas too low")
                || lower.contains("gas required exceeds allowance")
                || lower.contains("out of gas")
            {
                error_class = "GAS_TOO_LOW";
                retryable = true;
                suggest_fix = Some("Increase gas limit or rerun preflight/estimation and retry");
            }
        }

        // Sui-specific
        if chain == "sui" {
            if lower.contains("gas budget")
                || lower.contains("gasbudget")
                || lower.contains("gas too low")
            {
                error_class = "GAS_TOO_LOW";
                retryable = true;
                suggest_fix =
                    Some("Increase gas_budget or rerun with preflight/estimation and retry");
            }
            if lower.contains("objectnotfound") || lower.contains("object not found") {
                error_class = "OBJECT_NOT_FOUND";
                retryable = false;
                suggest_fix =
                    Some("Verify the object id and ownership, and ensure it still exists");
            }
            if lower.contains("object locked") || lower.contains("objectlocked") {
                error_class = "OBJECT_LOCKED";
                retryable = true;
                suggest_fix =
                    Some("Object is locked by another transaction; retry after it completes");
            }
        }

        serde_json::json!({
            "chain": chain,
            "error_class": error_class,
            "retryable": retryable,
            "suggest_fix": suggest_fix,
            "links": [
                "web3mcp/docs/troubleshooting.md",
                "web3mcp/docs/prompts/troubleshooting.md"
            ],
            "raw": {
                "context": context,
                "error": error
            }
        })
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
