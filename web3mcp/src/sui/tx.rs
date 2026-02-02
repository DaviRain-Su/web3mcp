use crate::{ObjectOptionsRequest, TransactionResponseOptionsRequest, Web3McpServer};
// rmcp::model::* not needed here (kept functions pure)
use serde_json::{json, Value};
use sui_json_rpc_types::{
    SuiObjectDataOptions, SuiTransactionBlockEffectsAPI, SuiTransactionBlockResponse,
    SuiTransactionBlockResponseOptions,
};

impl Web3McpServer {
    pub fn summarize_transaction(response: &SuiTransactionBlockResponse) -> Value {
        let (status, error) = response
            .effects
            .as_ref()
            .map(|effects| match effects.status() {
                sui_json_rpc_types::SuiExecutionStatus::Success => ("success".to_string(), None),
                sui_json_rpc_types::SuiExecutionStatus::Failure { error } => {
                    ("failure".to_string(), Some(error.clone()))
                }
            })
            .unwrap_or_else(|| ("unknown".to_string(), None));
        let gas_used = response.effects.as_ref().map(|effects| {
            let summary = effects.gas_cost_summary();
            json!({
                "computation_cost": summary.computation_cost,
                "storage_cost": summary.storage_cost,
                "storage_rebate": summary.storage_rebate,
                "non_refundable_storage_fee": summary.non_refundable_storage_fee,
                "total_gas_used": summary.gas_used(),
            })
        });

        let created = response
            .effects
            .as_ref()
            .map(|effects| effects.created().len())
            .unwrap_or(0);
        let mutated = response
            .effects
            .as_ref()
            .map(|effects| effects.mutated().len())
            .unwrap_or(0);
        let deleted = response
            .effects
            .as_ref()
            .map(|effects| effects.deleted().len())
            .unwrap_or(0);

        json!({
            "digest": response.digest,
            "status": status,
            "success": response.status_ok(),
            "error": error,
            "checkpoint": response.checkpoint,
            "timestamp_ms": response.timestamp_ms,
            "gas_used": gas_used,
            "created": created,
            "mutated": mutated,
            "deleted": deleted,
            "events": response.events.as_ref().map(|events| events.data.len()),
            "balance_changes": response.balance_changes.as_ref().map(|changes| changes.len()),
        })
    }

    pub fn tx_options_from_request(
        request: Option<TransactionResponseOptionsRequest>,
    ) -> SuiTransactionBlockResponseOptions {
        if let Some(options) = request {
            let mut response = SuiTransactionBlockResponseOptions::new();
            if options.show_input.unwrap_or(false) {
                response = response.with_input();
            }
            if options.show_raw_input.unwrap_or(false) {
                response = response.with_raw_input();
            }
            if options.show_effects.unwrap_or(false) {
                response = response.with_effects();
            }
            if options.show_events.unwrap_or(false) {
                response = response.with_events();
            }
            if options.show_object_changes.unwrap_or(false) {
                response = response.with_object_changes();
            }
            if options.show_balance_changes.unwrap_or(false) {
                response = response.with_balance_changes();
            }
            if options.show_raw_effects.unwrap_or(false) {
                response = response.with_raw_effects();
            }
            response
        } else {
            SuiTransactionBlockResponseOptions::full_content()
        }
    }

    pub fn object_options_from_request(
        request: Option<ObjectOptionsRequest>,
    ) -> SuiObjectDataOptions {
        let mut options = SuiObjectDataOptions::new();
        if let Some(request) = request {
            if request.show_type.unwrap_or(false) {
                options.show_type = true;
            }
            if request.show_owner.unwrap_or(false) {
                options.show_owner = true;
            }
            if request.show_previous_transaction.unwrap_or(false) {
                options.show_previous_transaction = true;
            }
            if request.show_display.unwrap_or(false) {
                options.show_display = true;
            }
            if request.show_content.unwrap_or(false) {
                options.show_content = true;
            }
            if request.show_bcs.unwrap_or(false) {
                options.show_bcs = true;
            }
            if request.show_storage_rebate.unwrap_or(false) {
                options.show_storage_rebate = true;
            }
        }
        options
    }
}
