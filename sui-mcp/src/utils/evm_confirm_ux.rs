use serde_json::{json, Value};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AllowanceConfirmAction {
    ConfirmApproveFirst,
    WaitForApproveMined,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AllowanceInsufficientDecision {
    pub action: AllowanceConfirmAction,
    pub message: String,
    pub note: String,
}

/// Pure UX decision helper: chooses the right error message/note when allowance is insufficient.
///
/// If approve_status == "sent", we prefer telling user to wait for mining instead of re-confirm.
pub fn allowance_insufficient_decision(
    allowance_raw: &str,
    required_raw: &str,
    approve_status: Option<&str>,
) -> AllowanceInsufficientDecision {
    let (action, message, note) = if approve_status == Some("sent") {
        (
            AllowanceConfirmAction::WaitForApproveMined,
            format!(
                "Allowance insufficient ({} < {}). Approve tx already sent—wait 1-2 blocks, then confirm swap again.",
                allowance_raw, required_raw
            ),
            "Approve tx already sent; wait 1-2 blocks for it to mine, then confirm swap again"
                .to_string(),
        )
    } else {
        (
            AllowanceConfirmAction::ConfirmApproveFirst,
            format!(
                "Allowance insufficient ({} < {}). Please confirm the approve tx first.",
                allowance_raw, required_raw
            ),
            "Run/confirm approve, wait for it to mine, then confirm swap again".to_string(),
        )
    };

    AllowanceInsufficientDecision {
        action,
        message,
        note,
    }
}

/// Attach web3mcp debug info to a response payload.
pub fn attach_web3mcp_debug(target: &mut Value, debug: Value) {
    if let Value::Object(ref mut m) = target {
        m.insert("web3mcp".to_string(), json!({"debug": debug}));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allowance_decision_sent_prefers_wait() {
        let d = allowance_insufficient_decision("1", "2", Some("sent"));
        assert_eq!(d.action, AllowanceConfirmAction::WaitForApproveMined);
        assert!(d.message.contains("already sent"));
    }

    #[test]
    fn allowance_decision_pending_prefers_confirm() {
        let d = allowance_insufficient_decision("1", "2", Some("pending"));
        assert_eq!(d.action, AllowanceConfirmAction::ConfirmApproveFirst);
        assert!(d.message.contains("confirm the approve"));
    }
}
