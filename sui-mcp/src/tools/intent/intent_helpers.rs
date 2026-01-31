// Helper methods for intent tools.
//
// This file is stitched into `router_impl.rs` by build.rs in a plain `impl SuiMcpServer { ... }`
// block (NOT the #[tool_router] impl), so it can freely define helper methods.

    fn wrap_resolved_network_result(
        resolved_network: &Value,
        result: &CallToolResult,
    ) -> Result<CallToolResult, ErrorData> {
        let payload = Self::extract_first_json(result).unwrap_or(json!({
            "raw": Self::extract_text(result)
        }));

        let response = Self::pretty_json(&json!({
            "resolved_network": resolved_network,
            "result": payload
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn ensure_sui_intent_family(resolved_network: &Value, intent: &str) -> Result<(), ErrorData> {
        let family = resolved_network
            .get("family")
            .and_then(Value::as_str)
            .unwrap_or("sui");

        if family == "evm" {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("{} is only supported for Sui", intent)),
                data: None,
            });
        }

        Ok(())
    }

    async fn execute_zklogin_intent_tx(
        &self,
        tx_bytes: String,
        zk_login_inputs_json: Option<String>,
        address_seed: Option<String>,
        max_epoch: Option<u64>,
        user_signature: Option<String>,
    ) -> Result<CallToolResult, ErrorData> {
        self.execute_zklogin_transaction(Parameters(ZkLoginExecuteTransactionRequest {
            tx_bytes,
            zk_login_inputs_json: zk_login_inputs_json.ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("zk_login_inputs_json required"),
                data: None,
            })?,
            address_seed: address_seed.ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("address_seed required"),
                data: None,
            })?,
            max_epoch: max_epoch.ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("max_epoch required"),
                data: None,
            })?,
            user_signature: user_signature.ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("user_signature required"),
                data: None,
            })?,
        }))
        .await
    }
