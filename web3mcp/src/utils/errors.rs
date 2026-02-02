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

    pub fn structured_error(
        message: &str,
        context: &str,
        error_class: &str,
        retryable: bool,
        suggest_fix: Option<&str>,
        raw_error: Option<&str>,
        extra: Option<serde_json::Value>,
    ) -> ErrorData {
        let mut data = Self::classify_error(context, raw_error.unwrap_or(""));
        if let serde_json::Value::Object(ref mut m) = data {
            m.insert(
                "error_class".to_string(),
                serde_json::Value::String(error_class.to_string()),
            );
            m.insert("retryable".to_string(), serde_json::Value::Bool(retryable));
            m.insert(
                "suggest_fix".to_string(),
                match suggest_fix {
                    Some(s) => serde_json::Value::String(s.to_string()),
                    None => serde_json::Value::Null,
                },
            );
            if let Some(e) = extra {
                m.insert("extra".to_string(), e);
            }
        }

        ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(message.to_string()),
            data: Some(data),
        }
    }

    pub fn guard_result(
        context: &str,
        guard_class: &str,
        reason: &str,
        retryable: bool,
        suggest_fix: Option<&str>,
        next: Option<serde_json::Value>,
        extra: Option<serde_json::Value>,
    ) -> Result<CallToolResult, ErrorData> {
        let mut data = Self::classify_error(context, "");
        if let serde_json::Value::Object(ref mut m) = data {
            m.insert(
                "guard_class".to_string(),
                serde_json::Value::String(guard_class.to_string()),
            );
            m.insert("retryable".to_string(), serde_json::Value::Bool(retryable));
            m.insert(
                "suggest_fix".to_string(),
                match suggest_fix {
                    Some(s) => serde_json::Value::String(s.to_string()),
                    None => serde_json::Value::Null,
                },
            );
            if let Some(n) = next {
                // Normalize next into an object for stable integrations.
                // - string -> {"how_to": "..."}
                // - {"next": "..."} -> {"how_to": "..."}
                // - object -> keep as-is
                let normalized = match n {
                    serde_json::Value::String(s) => serde_json::json!({"how_to": s}),
                    serde_json::Value::Object(mut o) => {
                        if let Some(v) = o.remove("next") {
                            if let serde_json::Value::String(s) = v {
                                serde_json::json!({"how_to": s})
                            } else {
                                // keep original object if it's not a string
                                let mut o2 = serde_json::Map::new();
                                o2.insert("next".to_string(), v);
                                serde_json::Value::Object(o2)
                            }
                        } else {
                            serde_json::Value::Object(o)
                        }
                    }
                    other => serde_json::json!({"how_to": format!("{}", other)}),
                };

                m.insert("next".to_string(), normalized);
            }
            if let Some(e) = extra {
                m.insert("extra".to_string(), e);
            }
        }

        let body = serde_json::json!({
            "status": "needs_confirmation",
            "context": context,
            "reason": reason,
            "guard": data
        });

        let text = serde_json::to_string_pretty(&body).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize guard result: {}", e)),
            data: None,
        })?;

        Ok(CallToolResult::success(vec![Content::text(text)]))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guard_result_has_stable_shape() {
        let res = Web3McpServer::guard_result(
            "test_context",
            "SAFETY_GUARD_BLOCKED",
            "blocked",
            false,
            Some("do x"),
            Some(serde_json::json!({"tool": "t", "args": {"a": 1}})),
            Some(serde_json::json!({"extra_k": "v"})),
        )
        .expect("guard_result should succeed");

        assert!(!res.content.is_empty());
        let text = res.content[0]
            .raw
            .as_text()
            .map(|t| t.text.clone())
            .unwrap_or_else(|| panic!("expected text content, got: {:?}", res.content[0]));

        let v: serde_json::Value = serde_json::from_str(&text).expect("valid json");
        assert_eq!(
            v.get("status").and_then(|x| x.as_str()),
            Some("needs_confirmation")
        );
        assert_eq!(
            v.get("context").and_then(|x| x.as_str()),
            Some("test_context")
        );

        let guard = v.get("guard").expect("guard object");
        assert_eq!(
            guard.get("guard_class").and_then(|x| x.as_str()),
            Some("SAFETY_GUARD_BLOCKED")
        );

        // `next` is included when provided.
        assert!(guard.get("next").is_some());
    }
}
