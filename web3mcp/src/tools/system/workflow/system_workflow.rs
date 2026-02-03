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

        // ---------------- helpers ----------------

        fn solana_network_from_intent(intent: &Value) -> Option<String> {
            // Best-effort: extract network name; default is mainnet.
            let mut net = intent
                .get("resolved_network")
                .and_then(|v| v.get("network_name"))
                .and_then(Value::as_str)
                .map(|s| s.to_string());

            if net.is_none() {
                net = intent
                    .get("resolved_network")
                    .and_then(|v| v.get("network"))
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
            }

            let n = net.unwrap_or_else(|| "mainnet".to_string());
            let lower = n.to_lowercase();
            if lower.contains("devnet") {
                Some("devnet".to_string())
            } else if lower.contains("testnet") {
                Some("testnet".to_string())
            } else if lower.contains("main") {
                Some("mainnet".to_string())
            } else if lower.contains("local") || lower.contains("localhost") {
                Some("localhost".to_string())
            } else {
                // If it's something unrecognized, keep it (solana_tools has mapping logic).
                Some(n)
            }
        }

        fn jup_base_url() -> String {
            std::env::var("SOLANA_JUPITER_QUOTE_BASE_URL")
                .unwrap_or_else(|_| "https://quote-api.jup.ag".to_string())
        }

        fn solana_token_to_mint(token: &str) -> Option<&'static str> {
            // MVP mapping (extend as needed)
            match token.trim().to_lowercase().as_str() {
                "sol" | "wsol" | "wrapped sol" => Some("So11111111111111111111111111111111111111112"),
                "usdc" => Some("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
                _ => None,
            }
        }

        fn parse_amount_to_base_units(amount: &str, decimals: u32) -> Result<u64, ErrorData> {
            let s = amount.trim();
            if s.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount_in is required"),
                    data: None,
                });
            }

            if !s.contains('.') {
                return s.parse::<u64>().map_err(|_| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount_in must be an integer base-unit string (or a decimal UI amount for SOL/USDC)"),
                    data: Some(json!({"provided": s})),
                });
            }

            // Decimal UI amount.
            let parts: Vec<&str> = s.split('.').collect();
            if parts.len() != 2 {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("invalid decimal amount"),
                    data: Some(json!({"provided": s})),
                });
            }
            let whole = parts[0];
            let frac = parts[1];
            if frac.len() > decimals as usize {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("too many decimal places for token"),
                    data: Some(json!({"provided": s, "decimals": decimals})),
                });
            }
            let whole_u: u64 = whole.parse().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("invalid decimal amount (whole part)"),
                data: Some(json!({"provided": s})),
            })?;
            let mut frac_s = frac.to_string();
            while frac_s.len() < decimals as usize {
                frac_s.push('0');
            }
            let frac_u: u64 = if frac_s.is_empty() {
                0
            } else {
                frac_s.parse().map_err(|_| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("invalid decimal amount (fractional part)"),
                    data: Some(json!({"provided": s})),
                })?
            };

            let mul = 10u64
                .checked_pow(decimals)
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("decimal conversion overflow"),
                    data: Some(json!({"decimals": decimals})),
                })?;

            whole_u
                .checked_mul(mul)
                .and_then(|x| x.checked_add(frac_u))
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("decimal conversion overflow"),
                    data: Some(json!({"provided": s, "decimals": decimals})),
                })
        }

        async fn jup_quote(
            input_mint: &str,
            output_mint: &str,
            amount: u64,
            slippage_bps: u64,
        ) -> Result<Value, ErrorData> {
            let base = jup_base_url();
            let url = format!(
                "{}/v6/quote?inputMint={}&outputMint={}&amount={}&slippageBps={}",
                base.trim_end_matches('/'),
                urlencoding::encode(input_mint),
                urlencoding::encode(output_mint),
                amount,
                slippage_bps
            );

            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_millis(15_000))
                .build()
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_quote: failed to build client: {e}")),
                    data: None,
                })?;

            let resp = client
                .get(&url)
                .send()
                .await
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_quote: request failed: {e}")),
                    data: Some(json!({"url": url})),
                })?;

            let status = resp.status();
            let text = resp
                .text()
                .await
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_quote: failed to read body: {e}")),
                    data: None,
                })?;
            let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({ "raw": text }));

            if !status.is_success() {
                return Err(ErrorData {
                    code: ErrorCode(i32::from(status.as_u16())),
                    message: Cow::from("HTTP error from Jupiter quote API"),
                    data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
                });
            }

            Ok(parsed)
        }

        async fn jup_swap(quote: &Value, user_pubkey: &str) -> Result<Value, ErrorData> {
            let base = jup_base_url();
            let url = format!("{}/v6/swap", base.trim_end_matches('/'));

            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_millis(20_000))
                .build()
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_swap: failed to build client: {e}")),
                    data: None,
                })?;

            // Minimal swap request (Jupiter v6).
            let body = json!({
                "quoteResponse": quote,
                "userPublicKey": user_pubkey,
                "wrapAndUnwrapSol": true,
                "dynamicComputeUnitLimit": true
            });

            let resp = client
                .post(&url)
                .json(&body)
                .send()
                .await
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_swap: request failed: {e}")),
                    data: Some(json!({"url": url})),
                })?;

            let status = resp.status();
            let text = resp
                .text()
                .await
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_swap: failed to read body: {e}")),
                    data: None,
                })?;

            let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({ "raw": text }));

            if !status.is_success() {
                return Err(ErrorData {
                    code: ErrorCode(i32::from(status.as_u16())),
                    message: Cow::from("HTTP error from Jupiter swap API"),
                    data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
                });
            }

            Ok(parsed)
        }

        // ---------------- Stage 2: simulate ----------------

        let mut simulate = json!({
            "stage": "simulate",
            "status": "todo",
            "simulation_performed": false,
            "intent": intent_value,
        });

        // Currently: implement Solana swap_exact_in via Jupiter quote+swap + RPC simulate.
        if intent_value["chain"] == "solana" && intent_value["action"] == "swap_exact_in" {
            let user = intent_value
                .get("user_pubkey")
                .and_then(Value::as_str)
                .unwrap_or("<sender>");
            if user.starts_with('<') {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("user_pubkey (sender) is required for Solana swap workflow"),
                    data: None,
                });
            }

            let input_token = intent_value
                .get("input_token")
                .and_then(Value::as_str)
                .unwrap_or("<sell_token>");
            let output_token = intent_value
                .get("output_token")
                .and_then(Value::as_str)
                .unwrap_or("<buy_token>");
            let amount_in_s = intent_value
                .get("amount_in")
                .and_then(Value::as_str)
                .unwrap_or("<amount>");
            let slippage_bps = intent_value
                .get("slippage_bps")
                .and_then(Value::as_u64)
                .unwrap_or(100);

            // Support either direct mint strings OR common symbols.
            let input_mint = if input_token.len() >= 32 && input_token.chars().all(|c| c.is_ascii_alphanumeric()) {
                input_token
            } else {
                solana_token_to_mint(input_token).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("unsupported input_token symbol (provide SPL mint address for now)"),
                    data: Some(json!({"input_token": input_token})),
                })?
            };
            let output_mint = if output_token.len() >= 32 && output_token.chars().all(|c| c.is_ascii_alphanumeric()) {
                output_token
            } else {
                solana_token_to_mint(output_token).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("unsupported output_token symbol (provide SPL mint address for now)"),
                    data: Some(json!({"output_token": output_token})),
                })?
            };

            // Amount: accept base units (u64 string); additionally accept decimals for SOL/USDC.
            let decimals = if input_mint == "So11111111111111111111111111111111111111112" {
                9
            } else if input_mint == "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" {
                6
            } else {
                // MVP: require integer base units for other tokens.
                0
            };

            let amount_in = if decimals == 0 {
                amount_in_s.parse::<u64>().map_err(|_| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount_in must be base units integer for this token (provide lamports/token base units)"),
                    data: Some(json!({"amount_in": amount_in_s, "input_mint": input_mint})),
                })?
            } else {
                parse_amount_to_base_units(amount_in_s, decimals)?
            };

            let quote = jup_quote(input_mint, output_mint, amount_in, slippage_bps).await?;
            let swap = jup_swap(&quote, user).await?;
            let tx_b64 = swap
                .get("swapTransaction")
                .and_then(Value::as_str)
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Jupiter swap response missing swapTransaction"),
                    data: Some(json!({"swap": swap})),
                })?;

            let network = solana_network_from_intent(&intent_value);
            let rpc = Self::solana_rpc(network.as_deref())?;

            let raw = Self::decode_base64("swapTransaction", tx_b64)?;

            let vtx: solana_sdk::transaction::VersionedTransaction =
                bincode::deserialize(&raw).map_err(|e| Self::sdk_error("solana_swap:deserialize_tx", e))?;

            let cfg = solana_client::rpc_config::RpcSimulateTransactionConfig {
                sig_verify: false,
                replace_recent_blockhash: true,
                commitment: Some(solana_commitment_config::CommitmentConfig::processed()),
                encoding: Some(solana_transaction_status::UiTransactionEncoding::Base64),
                accounts: None,
                min_context_slot: None,
                inner_instructions: false,
            };

            let sim = rpc
                .simulate_transaction_with_config(&vtx, cfg)
                .await
                .map_err(|e| Self::sdk_error("solana_swap:simulate", e))?;

            let ok = sim.value.err.is_none();

            simulate = json!({
                "stage": "simulate",
                "status": if ok { "ok" } else { "failed" },
                "simulation_performed": true,
                "adapter": "jupiter_v6",
                "network": network,
                "input_mint": input_mint,
                "output_mint": output_mint,
                "amount_in": amount_in.to_string(),
                "slippage_bps": slippage_bps,
                "quote": quote,
                "swap": {
                    "lastValidBlockHeight": swap.get("lastValidBlockHeight"),
                    "prioritizationFeeLamports": swap.get("prioritizationFeeLamports"),
                    "computeUnitLimit": swap.get("computeUnitLimit"),
                    "tx_base64": tx_b64
                },
                "simulation": {
                    "err": sim.value.err,
                    "logs": sim.value.logs,
                    "units_consumed": sim.value.units_consumed
                },
                "note": if ok {
                    "Simulation succeeded. Next step: create a pending confirmation and require explicit confirm_token on mainnet."
                } else {
                    "Simulation failed. Do not send; inspect logs/err and adjust params."
                }
            });
        }

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
            "note": "M3+: approval/policy can be applied here (amount thresholds, allowlists, etc).",
        });
        let approval_path = store.write_stage_artifact(&run_id, "approval", &approval).map_err(|e| {
            ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to write approval artifact: {e}")),
                data: None,
            }
        })?;

        // Stage 4: execute (guard: no-sim-no-send)
        let simulation_ok = simulate
            .get("simulation_performed")
            .and_then(Value::as_bool)
            .unwrap_or(false)
            && simulate.get("status").and_then(Value::as_str) == Some("ok");

        let execute = if !simulation_ok {
            json!({
                "stage": "execute",
                "status": "blocked",
                "guard": {
                    "guard_class": "no_sim_no_send",
                    "next": {
                        "mode": "simulate",
                        "how_to": "Run (and pass) simulation first. See simulate artifact for logs/errors."
                    }
                },
                "note": "Execution blocked: simulation not OK (safety)."
            })
        } else if intent_value["chain"] == "solana" && intent_value["action"] == "swap_exact_in" {
            // Safe default: create a pending confirmation (confirm=false). Broadcast requires confirm_token on mainnet.
            let tx_b64 = simulate
                .get("swap")
                .and_then(|v| v.get("tx_base64"))
                .and_then(Value::as_str)
                .unwrap_or("");
            if tx_b64.is_empty() {
                json!({
                    "stage": "execute",
                    "status": "error",
                    "note": "missing tx_base64 from simulate stage"
                })
            } else {
                let network = simulate.get("network").and_then(|v| {
                    if v.is_string() { v.as_str().map(|s| s.to_string()) } else { None }
                });

                let send_req = SolanaSendTransactionRequest {
                    network: network.clone(),
                    transaction_base64: tx_b64.to_string(),
                    commitment: Some("confirmed".to_string()),
                    confirm: Some(false),
                    allow_direct_send: None,
                    skip_preflight: None,
                    timeout_ms: None,
                };

                let call_res = self.solana_send_transaction(Parameters(send_req)).await?;

                let send_res = call_res
                    .content
                    .get(0)
                    .and_then(|c| match &c.raw {
                        rmcp::model::RawContent::Text(t) => Some(t.text.clone()),
                        _ => None,
                    })
                    .unwrap_or_else(|| "{}".to_string());

                // Best-effort parse the JSON payload returned by tool.
                let parsed: Value = serde_json::from_str(&send_res).unwrap_or_else(|_| json!({ "raw": send_res }));

                json!({
                    "stage": "execute",
                    "status": "pending_confirmation_created",
                    "network": network,
                    "result": parsed,
                    "note": "Pending confirmation created (safe default). Use solana_confirm_transaction to broadcast (mainnet requires confirm_token)."
                })
            }
        } else {
            json!({
                "stage": "execute",
                "status": "todo",
                "note": "Execution not implemented for this intent yet."
            })
        };

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
                "note": "Solana swap_exact_in: simulation + pending-confirmation creation implemented. Next: approval policy + richer token/amount handling.",
                "how_to": "Provide intent_text like: 'swap 0.01 sol to usdc on solana mainnet' with sender=YOUR_PUBKEY; then use solana_confirm_transaction with confirm_token if on mainnet."
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
