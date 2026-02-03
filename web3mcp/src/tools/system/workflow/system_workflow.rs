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
        let analysis = json!({
            "stage": "analysis",
            "label": request.label,
            "intent": request.intent,
        });
        let analysis_path = store.write_stage_artifact(&run_id, "analysis", &analysis).map_err(|e| {
            ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to write analysis artifact: {e}")),
                data: None,
            }
        })?;

        // Stage 2: simulate (placeholder until Jupiter adapter lands)
        let simulate = json!({
            "stage": "simulate",
            "status": "todo",
            "note": "M2 workflow skeleton: simulation stage will be implemented in M4/M5 (Jupiter adapter).",
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
