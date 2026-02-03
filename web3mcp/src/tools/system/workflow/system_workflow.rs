    /// W3RT: run a deterministic workflow skeleton (v0).
    /// Stages: analysis → simulate → approval → execute
    #[tool(description = "W3RT: run a deterministic workflow skeleton (v0) and write stage artifacts (run_id).")]
    async fn w3rt_run_workflow_v0(
        &self,
        Parameters(request): Parameters<SystemRunWorkflowV0Request>,
    ) -> Result<CallToolResult, ErrorData> {
        let store = crate::utils::run_store::RunStore::new();
        let run_id = store.new_run_id();

        // Stage 1: analysis (accept/echo intent)
        // Allow either a validated intent object OR intent_text (NL) to be provided.
        let mut intent_value = request.intent.clone().unwrap_or(Value::Null);

        if intent_value.is_null() {
            if let Some(text) = request.intent_text.clone() {
                let lower = text.to_lowercase();
                let sender = request
                    .sender
                    .clone()
                    .unwrap_or_else(|| "<sender>".to_string());
                let (intent, _action, entities, confidence, _plan) =
                    Self::parse_intent_plan(&text, &lower, sender.clone(), request.network.clone());

                // Minimal Solana swap intent schema (same as M1 intent output).
                if intent == "swap" && entities["network"]["family"] == "solana" {
                    let sell = entities
                        .get("from_coin")
                        .and_then(Value::as_str)
                        .unwrap_or("<sell_token>")
                        .to_lowercase();
                    let buy = entities
                        .get("to_coin")
                        .and_then(Value::as_str)
                        .unwrap_or("<buy_token>")
                        .to_lowercase();
                    let amount_in = entities
                        .get("amount")
                        .and_then(Value::as_str)
                        .unwrap_or("<amount>")
                        .to_string();

                    intent_value = json!({
                        "chain": "solana",
                        "action": "swap_exact_in",
                        "input_token": sell,
                        "output_token": buy,
                        "amount_in": amount_in,
                        "slippage_bps": 100,
                        "user_pubkey": sender,
                        "resolved_network": entities["network"],
                        "confidence": confidence
                    });
                } else {
                    // Generic: store parsing result (still useful for artifacts).
                    intent_value = json!({
                        "intent": intent,
                        "confidence": confidence,
                        "entities": entities,
                        "raw": text
                    });
                }
            }
        }

        let analysis = json!({
            "stage": "analysis",
            "label": request.label,
            "intent": intent_value,
        });
        let analysis_path = store.write_stage_artifact(&run_id, "analysis", &analysis).map_err(|e| {
            ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to write analysis artifact: {e}")),
                data: None,
            }
        })?;

        // Stage 2: simulate (structured placeholder)
        let simulate_status = if intent_value["chain"] == "solana" && intent_value["action"] == "swap_exact_in" {
            "ready_for_jupiter"
        } else {
            "todo"
        };

        let simulate = json!({
            "stage": "simulate",
            "status": simulate_status,
            "intent": intent_value,
            "note": "M2 workflow skeleton: simulation stage will be implemented in M4/M5 (Jupiter adapter).",
            "next": if simulate_status == "ready_for_jupiter" {
                json!({
                    "mode": "simulate",
                    "adapter": "jupiter",
                    "how_to": "M4: use Jupiter quote+build+simulate to populate this stage artifact"
                })
            } else {
                json!({"mode": "todo"})
            }
        });
        let simulate_path = store.write_stage_artifact(&run_id, "simulate", &simulate).map_err(|e| {
            ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to write simulate artifact: {e}")),
                data: None,
            }
        })?;

        // Stage 3: approval (placeholder)
        let approval = json!({
            "stage": "approval",
            "status": "todo",
            "note": "M2 workflow skeleton: approval/guard will be enforced in M3.",
        });
        let approval_path = store.write_stage_artifact(&run_id, "approval", &approval).map_err(|e| {
            ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to write approval artifact: {e}")),
                data: None,
            }
        })?;

        // Stage 4: execute (placeholder)
        let execute = json!({
            "stage": "execute",
            "status": "todo",
            "note": "M2 workflow skeleton: execution will be implemented in M5 (pending confirmation / confirm_token flow).",
        });
        let execute_path = store.write_stage_artifact(&run_id, "execute", &execute).map_err(|e| {
            ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to write execute artifact: {e}")),
                data: None,
            }
        })?;

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "run_id": run_id,
            "runs_dir": store.root(),
            "artifacts": {
                "analysis": analysis_path,
                "simulate": simulate_path,
                "approval": approval_path,
                "execute": execute_path
            },
            "next": {
                "note": "M2 complete: workflow skeleton + artifacts written. Next: implement M3 guard/policy and M4/M5 Jupiter swap stages.",
                "how_to": "Use w3rt_run_workflow_v0 with an intent JSON (e.g. from interpret_intent/execute_intent)"
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
