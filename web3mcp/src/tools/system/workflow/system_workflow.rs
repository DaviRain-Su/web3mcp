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
            // Fast-path mapping for common tokens.
            // NOTE: This is only a fallback; for general symbols we resolve via Jupiter token list.
            match token.trim().to_lowercase().as_str() {
                "sol" | "wsol" | "wrapped sol" => Some("So11111111111111111111111111111111111111112"),
                "usdc" => Some("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
                "usdt" => Some("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
                "jup" => Some("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"),
                "bonk" => Some("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"),
                _ => None,
            }
        }

        fn solana_is_pubkey(s: &str) -> bool {
            use std::str::FromStr;
            let t = s.trim();
            if t.len() < 32 || t.len() > 64 {
                return false;
            }
            solana_sdk::pubkey::Pubkey::from_str(t).is_ok()
        }

        async fn solana_resolve_symbol_via_jupiter_tokens(symbol: &str) -> Result<Option<Value>, ErrorData> {
            // Jupiter token list (large). We only do a best-effort single fetch per run.
            // Env override for mirrors/self-hosted lists.
            let url = std::env::var("SOLANA_JUPITER_TOKENS_URL")
                .unwrap_or_else(|_| "https://tokens.jup.ag/tokens?tags=verified".to_string());

            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_millis(15_000))
                .build()
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("jup_tokens: failed to build client: {e}")),
                    data: None,
                })?;

            let resp = client.get(&url).send().await.map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("jup_tokens: request failed: {e}")),
                data: Some(json!({"url": url})),
            })?;

            let status = resp.status();
            let text = resp.text().await.map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("jup_tokens: failed to read body: {e}")),
                data: None,
            })?;

            let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({"raw": text}));
            if !status.is_success() {
                return Err(ErrorData {
                    code: ErrorCode(i32::from(status.as_u16())),
                    message: Cow::from("HTTP error from Jupiter tokens API"),
                    data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
                });
            }

            let want = symbol.trim().to_lowercase();
            let arr = parsed.as_array().ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("unexpected Jupiter tokens response (expected array)"),
                data: Some(json!({"url": url, "body": parsed})),
            })?;

            for t in arr {
                let sym = t.get("symbol").and_then(Value::as_str).unwrap_or("").to_lowercase();
                if sym == want {
                    return Ok(Some(t.clone()));
                }
            }

            Ok(None)
        }

        async fn solana_get_mint_decimals(
            rpc: &solana_client::nonblocking::rpc_client::RpcClient,
            mint: &str,
        ) -> Result<u8, ErrorData> {
            use std::str::FromStr;
            let pk = solana_sdk::pubkey::Pubkey::from_str(mint).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("invalid mint pubkey: {e}")),
                data: Some(json!({"mint": mint})),
            })?;

            let acct = rpc.get_account(&pk).await.map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("failed to fetch mint account: {e}")),
                data: Some(json!({"mint": mint})),
            })?;

            // Detect which token program owns the mint.
            // NOTE: spl-token(-2022) may compile against different solana pubkey types,
            // so we compare by string to avoid type mismatches.
            use solana_program_pack::Pack;

            let owner = acct.owner.to_string();
            let spl_token_owner = spl_token::id().to_string();
            let spl_token_2022_owner = spl_token_2022::id().to_string();

            if owner == spl_token_owner {
                let m = spl_token::state::Mint::unpack(&acct.data).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("failed to decode spl-token Mint: {e}")),
                    data: Some(json!({"mint": mint, "program": "spl-token"})),
                })?;
                Ok(m.decimals)
            } else if owner == spl_token_2022_owner {
                Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token-2022 mint decimals lookup not supported yet in workflow (provide amount as base units or use spl-token mint)"),
                    data: Some(json!({"mint": mint, "owner": owner})),
                })
            } else {
                Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("mint account is not owned by spl-token"),
                    data: Some(json!({"mint": mint, "owner": owner})),
                })
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

            let network = solana_network_from_intent(&intent_value);
            let rpc = Self::solana_rpc(network.as_deref())?;

            // Resolve input/output tokens to mints.
            let mut input_token_info: Option<Value> = None;
            let input_mint: String = if solana_is_pubkey(input_token) {
                input_token.trim().to_string()
            } else if let Some(m) = solana_token_to_mint(input_token) {
                input_token_info = Some(json!({"symbol": input_token, "address": m, "source": "builtin"}));
                m.to_string()
            } else {
                let found = solana_resolve_symbol_via_jupiter_tokens(input_token)
                    .await?
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("unsupported input_token symbol (provide SPL mint address or known symbol)"),
                        data: Some(json!({"input_token": input_token})),
                    })?;
                input_token_info = Some(json!({
                    "symbol": found.get("symbol"),
                    "name": found.get("name"),
                    "address": found.get("address"),
                    "decimals": found.get("decimals"),
                    "source": "jupiter_tokens"
                }));
                found
                    .get("address")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("Jupiter tokens entry missing address"),
                        data: Some(found.clone()),
                    })?
                    .to_string()
            };

            let mut output_token_info: Option<Value> = None;
            let output_mint: String = if solana_is_pubkey(output_token) {
                output_token.trim().to_string()
            } else if let Some(m) = solana_token_to_mint(output_token) {
                output_token_info = Some(json!({"symbol": output_token, "address": m, "source": "builtin"}));
                m.to_string()
            } else {
                let found = solana_resolve_symbol_via_jupiter_tokens(output_token)
                    .await?
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("unsupported output_token symbol (provide SPL mint address or known symbol)"),
                        data: Some(json!({"output_token": output_token})),
                    })?;
                output_token_info = Some(json!({
                    "symbol": found.get("symbol"),
                    "name": found.get("name"),
                    "address": found.get("address"),
                    "decimals": found.get("decimals"),
                    "source": "jupiter_tokens"
                }));
                found
                    .get("address")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("Jupiter tokens entry missing address"),
                        data: Some(found.clone()),
                    })?
                    .to_string()
            };

            // Resolve input decimals (for UI amount parsing).
            let decimals: u8 = if input_mint == "So11111111111111111111111111111111111111112" {
                9
            } else if input_mint == "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" {
                6
            } else if let Some(d) = input_token_info
                .as_ref()
                .and_then(|v| v.get("decimals"))
                .and_then(Value::as_u64)
            {
                d as u8
            } else {
                solana_get_mint_decimals(&rpc, &input_mint).await?
            };

            let amount_in = parse_amount_to_base_units(amount_in_s, decimals as u32)?;

            let quote = jup_quote(&input_mint, &output_mint, amount_in, slippage_bps).await?;
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
                "input_token": input_token,
                "output_token": output_token,
                "input_token_info": input_token_info,
                "output_token_info": output_token_info,
                "input_mint": input_mint,
                "output_mint": output_mint,
                "input_decimals": decimals,
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

        // Stage 3: approval (policy)
        fn format_base_units_ui(amount: &str, decimals: u8) -> String {
            let s = amount.trim();
            if decimals == 0 {
                return s.to_string();
            }
            // Normalize: ensure only digits.
            if s.is_empty() || !s.chars().all(|c| c.is_ascii_digit()) {
                return s.to_string();
            }
            let d = decimals as usize;
            if s.len() <= d {
                let mut out = String::from("0.");
                out.push_str(&"0".repeat(d - s.len()));
                out.push_str(s);
                out
            } else {
                let (a, b) = s.split_at(s.len() - d);
                format!("{}.{}", a, b)
            }
        }

        let approval = if simulate.get("adapter").and_then(Value::as_str) == Some("jupiter_v6")
            && simulate.get("status").and_then(Value::as_str) == Some("ok")
        {
            let network = simulate.get("network").and_then(|v| v.as_str()).map(|s| s.to_string());
            let input_decimals = simulate.get("input_decimals").and_then(Value::as_u64).unwrap_or(0) as u8;

            let output_mint = simulate.get("output_mint").and_then(Value::as_str).unwrap_or("").to_string();
            let output_decimals: u8 = if output_mint == "So11111111111111111111111111111111111111112" {
                9
            } else if output_mint == "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" {
                6
            } else {
                match Self::solana_rpc(network.as_deref()) {
                    Ok(rpc) => solana_get_mint_decimals(&rpc, &output_mint).await.unwrap_or(0),
                    Err(_) => 0,
                }
            };

            let quote = simulate.get("quote").cloned().unwrap_or(Value::Null);
            let in_amount = quote.get("inAmount").and_then(Value::as_str).unwrap_or("");
            let out_amount = quote.get("outAmount").and_then(Value::as_str).unwrap_or("");
            let price_impact_pct = quote.get("priceImpactPct").and_then(Value::as_str);

            let mut warnings: Vec<Value> = vec![];

            if let Some(p) = price_impact_pct {
                // Example strings: "0.0012" (=0.12%)
                if let Ok(v) = p.parse::<f64>() {
                    if v >= 0.01 {
                        warnings.push(json!({
                            "kind": "high_price_impact",
                            "price_impact_pct": p,
                            "threshold": "0.01",
                            "note": "priceImpactPct >= 1%"
                        }));
                    }
                }
            }

            let slippage_bps = simulate.get("slippage_bps").and_then(Value::as_u64).unwrap_or(100);
            if slippage_bps >= 300 {
                warnings.push(json!({
                    "kind": "high_slippage",
                    "slippage_bps": slippage_bps,
                    "threshold": 300,
                    "note": "slippage_bps >= 300 (3%)"
                }));
            }

            json!({
                "stage": "approval",
                "status": if warnings.is_empty() { "ok" } else { "needs_review" },
                "network": network,
                "summary": {
                    "in_amount_base": in_amount,
                    "in_amount_ui": format_base_units_ui(in_amount, input_decimals),
                    "out_amount_base": out_amount,
                    "out_amount_ui": format_base_units_ui(out_amount, output_decimals),
                    "input_decimals": input_decimals,
                    "output_decimals": output_decimals,
                    "price_impact_pct": price_impact_pct,
                    "route_plan_steps": quote.get("routePlan").and_then(Value::as_array).map(|a| a.len()),
                },
                "warnings": warnings,
                "note": "This stage is informational today. Execution still uses safe default (pending confirmation)."
            })
        } else {
            json!({
                "stage": "approval",
                "status": "todo",
                "note": "Approval not implemented for this intent yet."
            })
        };

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
