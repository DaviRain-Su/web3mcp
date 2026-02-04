    /// W3RT: run a deterministic workflow skeleton (v0).
    /// Stages: analysis → simulate → approval → execute
    #[tool(description = "W3RT: request a short-lived override token to bypass approval_required (power users / agents).")]
    async fn w3rt_request_override(
        &self,
        Parameters(request): Parameters<W3rtRequestOverrideRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let store = crate::utils::run_store::RunStore::new();
        let run_id = request.run_id.trim().to_string();
        if run_id.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("run_id is required"),
                data: None,
            });
        }

        let reason = request.reason.trim().to_string();
        if reason.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("reason is required"),
                data: None,
            });
        }

        // Load approval artifact if present.
        let run_dir = store.root().join(&run_id);
        let approval_path = run_dir.join("stage_approval.json");
        let approval: Value = if approval_path.exists() {
            let bytes = std::fs::read(&approval_path).unwrap_or_default();
            serde_json::from_slice::<Value>(&bytes).unwrap_or(Value::Null)
        } else {
            Value::Null
        };

        // Only allow override if approval says needs_review (or otherwise not ok).
        let status = approval.get("status").and_then(Value::as_str).unwrap_or("unknown");
        if status == "ok" {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("override not needed: approval.status is ok"),
                data: Some(json!({"run_id": run_id, "approval_status": status})),
            });
        }

        let rec = crate::utils::override_store::create_override(
            &run_id,
            &reason,
            request.ttl_ms,
            Some(approval.clone()),
        )?;

        let response = Self::pretty_json(&json!({
            "ok": true,
            "run_id": run_id,
            "override_token": rec.token,
            "expires_ms": rec.expires_ms,
            "note": "Use override_token in w3rt_run_workflow_v0 to bypass approval_required and continue to pending confirmation.",
            "next": {
                "tool": "w3rt_run_workflow_v0",
                "args": {
                    "intent": Value::Null,
                    "intent_text": Value::Null,
                    "override_token": "<paste override_token>",
                    "sender": "<sender>",
                    "network": "mainnet"
                }
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "W3RT: get a workflow run by run_id (reads stage artifacts from disk).")]
    async fn w3rt_get_run(
        &self,
        Parameters(request): Parameters<W3rtGetRunRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let store = crate::utils::run_store::RunStore::new();
        let run_id = request.run_id.trim().to_string();
        if run_id.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("run_id is required"),
                data: None,
            });
        }

        let run_dir = store.root().join(&run_id);
        let analysis_path = run_dir.join("stage_analysis.json");
        let simulate_path = run_dir.join("stage_simulate.json");
        let approval_path = run_dir.join("stage_approval.json");
        let execute_path = run_dir.join("stage_execute.json");

        let include = request.include_artifacts.unwrap_or(true);

        fn read_json(path: &std::path::Path) -> Value {
            let bytes = std::fs::read(path).unwrap_or_default();
            serde_json::from_slice::<Value>(&bytes).unwrap_or(Value::Null)
        }

        let response = if include {
            json!({
                "ok": true,
                "run_id": run_id,
                "runs_dir": store.root(),
                "paths": {
                    "analysis": analysis_path,
                    "simulate": simulate_path,
                    "approval": approval_path,
                    "execute": execute_path
                },
                "artifacts": {
                    "analysis": if analysis_path.exists() { read_json(&analysis_path) } else { Value::Null },
                    "simulate": if simulate_path.exists() { read_json(&simulate_path) } else { Value::Null },
                    "approval": if approval_path.exists() { read_json(&approval_path) } else { Value::Null },
                    "execute": if execute_path.exists() { read_json(&execute_path) } else { Value::Null }
                }
            })
        } else {
            json!({
                "ok": true,
                "run_id": run_id,
                "runs_dir": store.root(),
                "paths": {
                    "analysis": analysis_path,
                    "simulate": simulate_path,
                    "approval": approval_path,
                    "execute": execute_path
                }
            })
        };

        let out = Self::pretty_json(&response)?;
        Ok(CallToolResult::success(vec![Content::text(out)]))
    }

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
                let sender = request
                    .sender
                    .clone()
                    .unwrap_or_else(|| "<sender>".to_string());

                let (_intent, parsed, _confidence) =
                    Self::w3rt_parse_intent_plan(&text, sender.clone(), request.network.clone());

                intent_value = parsed;
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

        fn jup_tokens_cache_path() -> std::path::PathBuf {
            std::env::current_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from("."))
                .join(".cache")
                .join("web3mcp")
                .join("jup_tokens_verified.json")
        }

        async fn solana_fetch_jupiter_tokens_verified() -> Result<Value, ErrorData> {
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

            Ok(parsed)
        }

        async fn solana_jupiter_tokens_verified() -> Result<Value, ErrorData> {
            // Best-effort on-disk cache (reduces repeated downloads during development).
            // TTL is short: 10 minutes.
            let cache_path = jup_tokens_cache_path();
            let ttl = std::time::Duration::from_secs(600);

            if let Ok(meta) = std::fs::metadata(&cache_path) {
                if let Ok(mtime) = meta.modified() {
                    if mtime.elapsed().unwrap_or(ttl + std::time::Duration::from_secs(1)) <= ttl {
                        if let Ok(text) = std::fs::read_to_string(&cache_path) {
                            if let Ok(v) = serde_json::from_str::<Value>(&text) {
                                return Ok(v);
                            }
                        }
                    }
                }
            }

            let v = solana_fetch_jupiter_tokens_verified().await?;

            if let Some(parent) = cache_path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            if let Ok(s) = serde_json::to_string(&v) {
                let _ = std::fs::write(&cache_path, s);
            }

            Ok(v)
        }

        async fn solana_resolve_symbol_via_jupiter_tokens(symbol: &str) -> Result<Option<Value>, ErrorData> {
            let parsed = solana_jupiter_tokens_verified().await?;

            let want = symbol.trim().to_lowercase();
            let arr = parsed.as_array().ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("unexpected Jupiter tokens response (expected array)"),
                data: Some(json!({"body": parsed})),
            })?;

            let mut matches: Vec<Value> = Vec::new();
            for t in arr {
                let sym = t.get("symbol").and_then(Value::as_str).unwrap_or("").to_lowercase();
                if sym == want {
                    matches.push(t.clone());
                }
            }

            if matches.is_empty() {
                return Ok(None);
            }
            if matches.len() > 1 {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("ambiguous SPL token symbol; please provide mint address"),
                    data: Some(json!({
                        "symbol": symbol,
                        "matches": matches
                            .iter()
                            .take(5)
                            .map(|m| json!({"symbol": m.get("symbol"), "name": m.get("name"), "address": m.get("address"), "decimals": m.get("decimals")}))
                            .collect::<Vec<_>>()
                    })),
                });
            }

            Ok(Some(matches.remove(0)))
        }

        async fn solana_get_mint_decimals(
            rpc: &solana_client::nonblocking::rpc_client::RpcClient,
            mint: &str,
        ) -> Result<u8, ErrorData> {
            // Token Mint layout (SPL Token + Token-2022 share the base layout):
            // mint_authority (COption<Pubkey>) = 36 bytes
            // supply (u64)                    = 8 bytes
            // decimals (u8)                   = 1 byte  <-- offset 44
            // is_initialized (u8)             = 1 byte
            // freeze_authority (COption<Pubkey>) = 36 bytes
            // Total base = 82 bytes, extensions may follow (token-2022).
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

            // Base mint size should be at least 82 bytes.
            if acct.data.len() < 82 {
                return Err(ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("mint account data too short (expected >=82 bytes)"),
                    data: Some(json!({"mint": mint, "len": acct.data.len()})),
                });
            }

            Ok(acct.data[44])
        }

        async fn solana_get_token_program_for_mint(
            rpc: &solana_client::nonblocking::rpc_client::RpcClient,
            mint: &str,
        ) -> Result<String, ErrorData> {
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

            Ok(acct.owner.to_string())
        }

        fn solana_build_token_transfer_checked_ix(
            program_id: solana_sdk::pubkey::Pubkey,
            source: solana_sdk::pubkey::Pubkey,
            mint: solana_sdk::pubkey::Pubkey,
            destination: solana_sdk::pubkey::Pubkey,
            authority: solana_sdk::pubkey::Pubkey,
            amount: u64,
            decimals: u8,
        ) -> solana_sdk::instruction::Instruction {
            let mut data = Vec::with_capacity(1 + 8 + 1);
            data.push(12u8); // TransferChecked
            data.extend_from_slice(&amount.to_le_bytes());
            data.push(decimals);

            let accounts = vec![
                solana_sdk::instruction::AccountMeta::new(source, false),
                solana_sdk::instruction::AccountMeta::new_readonly(mint, false),
                solana_sdk::instruction::AccountMeta::new(destination, false),
                solana_sdk::instruction::AccountMeta::new_readonly(authority, true),
            ];

            solana_sdk::instruction::Instruction {
                program_id,
                accounts,
                data,
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

        // Solana transfer_native (SOL): build a system transfer tx and simulate.
        if intent_value["chain"] == "solana" && intent_value["action"] == "transfer_native" {
            // (handled below)
        }

        // Solana transfer_spl (USDC-first): build an SPL token transfer tx and simulate.
        if intent_value["chain"] == "solana" && intent_value["action"] == "transfer_spl" {
            use std::str::FromStr;
            use solana_sdk::signer::Signer;

            let from = intent_value.get("from").and_then(Value::as_str).unwrap_or("<sender>");
            let to = intent_value.get("to").and_then(Value::as_str).unwrap_or("<recipient>");
            let amount_s = intent_value.get("amount").and_then(Value::as_str).unwrap_or("<amount>");
            let asset = intent_value.get("asset").and_then(Value::as_str).unwrap_or("usdc").to_lowercase();

            if from.starts_with('<') {
                return Err(ErrorData { code: ErrorCode(-32602), message: Cow::from("from (sender) is required"), data: None });
            }
            if to.starts_with('<') {
                return Err(ErrorData { code: ErrorCode(-32602), message: Cow::from("to (recipient) is required"), data: None });
            }

            // Resolve mint + decimals.
            // - If `asset` is a pubkey: treat it as mint address.
            // - Else: support USDC/USDT fast-path, and fall back to Jupiter tokens list.
            let network = solana_network_from_intent(&intent_value);
            let rpc = Self::solana_rpc(network.as_deref())?;

            let (mint, decimals, token_info): (String, u8, Option<Value>) = if solana_is_pubkey(&asset) {
                let mint = asset.clone();
                let decimals = solana_get_mint_decimals(&rpc, &mint).await?;
                (mint, decimals, Some(json!({"source": "mint_address"})))
            } else if asset == "usdc" {
                (
                    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(),
                    6,
                    Some(json!({"source": "builtin", "symbol": "USDC"})),
                )
            } else if asset == "usdt" {
                (
                    "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(),
                    6,
                    Some(json!({"source": "builtin", "symbol": "USDT"})),
                )
            } else {
                let found = solana_resolve_symbol_via_jupiter_tokens(&asset)
                    .await?
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("unsupported SPL asset (provide mint address or known symbol)"),
                        data: Some(json!({"asset": asset})),
                    })?;
                let mint = found
                    .get("address")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("Jupiter token entry missing address"),
                        data: Some(found.clone()),
                    })?
                    .to_string();

                let decimals = found
                    .get("decimals")
                    .and_then(Value::as_u64)
                    .map(|d| d as u8)
                    .unwrap_or(0);

                let decimals = if decimals == 0 {
                    solana_get_mint_decimals(&rpc, &mint).await?
                } else {
                    decimals
                };

                (
                    mint,
                    decimals,
                    Some(json!({
                        "source": "jupiter_tokens",
                        "symbol": found.get("symbol"),
                        "name": found.get("name"),
                        "address": found.get("address"),
                        "decimals": decimals
                    })),
                )
            };

            let amount_base = parse_amount_to_base_units(amount_s, decimals as u32)?;

            let from_pk = solana_sdk::pubkey::Pubkey::from_str(from).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("invalid from pubkey: {e}")),
                data: Some(json!({"from": from})),
            })?;
            let to_pk = solana_sdk::pubkey::Pubkey::from_str(to).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("invalid to pubkey: {e}")),
                data: Some(json!({"to": to})),
            })?;
            let mint_pk = solana_sdk::pubkey::Pubkey::from_str(mint.as_str()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("invalid mint pubkey: {e}")),
                data: Some(json!({"mint": mint})),
            })?;

            // Detect token program (spl-token vs token-2022) from mint owner.
            let token_program = solana_get_token_program_for_mint(&rpc, &mint).await?;
            // Avoid type/version mismatches by treating program ids as strings and parsing into solana_sdk Pubkey.
            let token_program_legacy = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
            let token_program_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";

            let token_program_id = if token_program == token_program_2022 {
                solana_sdk::pubkey::Pubkey::from_str(token_program_2022).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("invalid token-2022 program id: {e}")),
                    data: None,
                })?
            } else if token_program == token_program_legacy {
                solana_sdk::pubkey::Pubkey::from_str(token_program_legacy).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("invalid token program id: {e}")),
                    data: None,
                })?
            } else {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("mint is not owned by spl-token or token-2022"),
                    data: Some(json!({"mint": mint, "owner": token_program})),
                });
            };

            let from_ata = spl_associated_token_account::get_associated_token_address_with_program_id(
                &from_pk,
                &mint_pk,
                &token_program_id,
            );
            let to_ata = spl_associated_token_account::get_associated_token_address_with_program_id(
                &to_pk,
                &mint_pk,
                &token_program_id,
            );

            let bh = rpc.get_latest_blockhash().await.map_err(|e| Self::sdk_error("solana_spl_transfer:get_latest_blockhash", e))?;

            // Ensure sender ATA exists.
            let _ = rpc.get_account(&from_ata).await.map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("sender token account (ATA) not found"),
                data: Some(json!({"from_ata": from_ata.to_string(), "mint": mint})),
            })?;

            // Create recipient ATA if needed.
            let to_ata_exists = rpc.get_account(&to_ata).await.is_ok();

            let mut ixs: Vec<solana_sdk::instruction::Instruction> = vec![];
            if !to_ata_exists {
                // payer = from
                ixs.push(spl_associated_token_account::instruction::create_associated_token_account(
                    &from_pk,
                    &to_pk,
                    &mint_pk,
                    &token_program_id,
                ));
            }

            let transfer_ix = solana_build_token_transfer_checked_ix(
                token_program_id,
                from_ata,
                mint_pk,
                to_ata,
                from_pk,
                amount_base,
                decimals,
            );

            ixs.push(transfer_ix);

            let msg = solana_sdk::message::Message::new(&ixs, Some(&from_pk));
            let mut tx = solana_sdk::transaction::Transaction::new_unsigned(msg);
            tx.message.recent_blockhash = bh;

            let cfg = solana_client::rpc_config::RpcSimulateTransactionConfig {
                sig_verify: false,
                replace_recent_blockhash: true,
                commitment: Some(solana_commitment_config::CommitmentConfig::processed()),
                encoding: Some(solana_transaction_status::UiTransactionEncoding::Base64),
                accounts: None,
                min_context_slot: None,
                inner_instructions: false,
            };

            let sim = rpc.simulate_transaction_with_config(&tx, cfg).await
                .map_err(|e| Self::sdk_error("solana_spl_transfer:simulate", e))?;

            let ok = sim.value.err.is_none();

            let tx_bytes = bincode::serialize(&tx)
                .map_err(|e| Self::sdk_error("solana_spl_transfer:serialize_tx", e))?;
            let tx_b64 = base64::engine::general_purpose::STANDARD.encode(tx_bytes);

            simulate = json!({
                "stage": "simulate",
                "status": if ok { "ok" } else { "failed" },
                "simulation_performed": true,
                "adapter": "solana_spl_transfer",
                "network": network,
                "asset": asset,
                "mint": mint,
                "decimals": decimals,
                "token_info": token_info,
                "token_program": token_program,
                "from": from,
                "to": to,
                "from_ata": from_ata.to_string(),
                "to_ata": to_ata.to_string(),
                "amount_ui": amount_s,
                "amount_base": amount_base.to_string(),
                "tx": { "tx_base64": tx_b64 },
                "simulation": { "err": sim.value.err, "logs": sim.value.logs, "units_consumed": sim.value.units_consumed }
            });
        }

        // Solana transfer_native (SOL): build a system transfer tx and simulate.
        if intent_value["chain"] == "solana" && intent_value["action"] == "transfer_native" {
            use std::str::FromStr;

            let from = intent_value.get("from").and_then(Value::as_str).unwrap_or("<sender>");
            let to = intent_value.get("to").and_then(Value::as_str).unwrap_or("<recipient>");
            let amount_s = intent_value.get("amount").and_then(Value::as_str).unwrap_or("<amount>");
            let asset = intent_value.get("asset").and_then(Value::as_str).unwrap_or("sol");

            if from.starts_with('<') {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("from (sender) is required for transfer"),
                    data: None,
                });
            }
            if to.starts_with('<') {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("to (recipient) is required for transfer"),
                    data: None,
                });
            }
            if asset.to_lowercase() != "sol" {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("transfer_native currently supports SOL only"),
                    data: Some(json!({"asset": asset})),
                });
            }

            let from_pk = solana_sdk::pubkey::Pubkey::from_str(from).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("invalid from pubkey: {e}")),
                data: Some(json!({"from": from})),
            })?;
            let to_pk = solana_sdk::pubkey::Pubkey::from_str(to).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("invalid to pubkey: {e}")),
                data: Some(json!({"to": to})),
            })?;

            // Amount is UI SOL string.
            let lamports = parse_amount_to_base_units(amount_s, 9)?;

            let network = solana_network_from_intent(&intent_value);
            let rpc = Self::solana_rpc(network.as_deref())?;
            let bh = rpc
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_transfer:get_latest_blockhash", e))?;

            let ix = solana_system_interface::instruction::transfer(&from_pk, &to_pk, lamports);
            let msg = solana_sdk::message::Message::new(&[ix], Some(&from_pk));
            let mut tx = solana_sdk::transaction::Transaction::new_unsigned(msg);
            tx.message.recent_blockhash = bh;

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
                .simulate_transaction_with_config(&tx, cfg)
                .await
                .map_err(|e| Self::sdk_error("solana_transfer:simulate", e))?;

            let ok = sim.value.err.is_none();

            let tx_bytes = bincode::serialize(&tx)
                .map_err(|e| Self::sdk_error("solana_transfer:serialize_tx", e))?;
            let tx_b64 = base64::engine::general_purpose::STANDARD.encode(tx_bytes);

            simulate = json!({
                "stage": "simulate",
                "status": if ok { "ok" } else { "failed" },
                "simulation_performed": true,
                "adapter": "solana_system_transfer",
                "network": network,
                "from": from,
                "to": to,
                "lamports": lamports.to_string(),
                "amount_ui": amount_s,
                "tx": { "tx_base64": tx_b64 },
                "simulation": {
                    "err": sim.value.err,
                    "logs": sim.value.logs,
                    "units_consumed": sim.value.units_consumed
                }
            });
        }

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
        } else if simulate.get("adapter").and_then(Value::as_str) == Some("solana_system_transfer")
            && simulate.get("status").and_then(Value::as_str) == Some("ok")
        {
            // Basic transfer policy: flag large transfers.
            let amount_ui = simulate.get("amount_ui").and_then(Value::as_str).unwrap_or("0");
            let mut warnings: Vec<Value> = vec![];

            // Threshold: 1 SOL default (heuristic; can be moved to env/policy runtime later)
            if let Ok(v) = amount_ui.parse::<f64>() {
                if v >= 1.0 {
                    warnings.push(json!({
                        "kind": "large_transfer",
                        "amount_ui": amount_ui,
                        "threshold_ui": "1.0",
                        "note": "transfer amount >= 1 SOL"
                    }));
                }
            }

            let from = simulate.get("from").and_then(Value::as_str).unwrap_or("");
            let to = simulate.get("to").and_then(Value::as_str).unwrap_or("");
            if !from.is_empty() && from == to {
                warnings.push(json!({
                    "kind": "self_transfer",
                    "note": "from == to"
                }));
            }

            json!({
                "stage": "approval",
                "status": if warnings.is_empty() { "ok" } else { "needs_review" },
                "warnings": warnings,
                "summary": {
                    "from": from,
                    "to": to,
                    "amount_ui": amount_ui,
                    "lamports": simulate.get("lamports")
                }
            })
        } else if simulate.get("adapter").and_then(Value::as_str) == Some("solana_spl_transfer")
            && simulate.get("status").and_then(Value::as_str) == Some("ok")
        {
            // Basic SPL transfer policy: flag large transfers.
            let amount_ui = simulate.get("amount_ui").and_then(Value::as_str).unwrap_or("0");
            let asset = simulate.get("asset").and_then(Value::as_str).unwrap_or("spl");
            let mut warnings: Vec<Value> = vec![];

            // Threshold: 1000 USDC/USDT default.
            if let Ok(v) = amount_ui.parse::<f64>() {
                if v >= 1000.0 {
                    warnings.push(json!({
                        "kind": "large_transfer",
                        "asset": asset,
                        "amount_ui": amount_ui,
                        "threshold_ui": "1000.0",
                        "note": "transfer amount >= 1000"
                    }));
                }
            }

            let from = simulate.get("from").and_then(Value::as_str).unwrap_or("");
            let to = simulate.get("to").and_then(Value::as_str).unwrap_or("");
            if !from.is_empty() && from == to {
                warnings.push(json!({ "kind": "self_transfer", "note": "from == to" }));
            }

            json!({
                "stage": "approval",
                "status": if warnings.is_empty() { "ok" } else { "needs_review" },
                "warnings": warnings,
                "summary": {
                    "asset": asset,
                    "mint": simulate.get("mint"),
                    "from": from,
                    "to": to,
                    "amount_ui": amount_ui,
                    "amount_base": simulate.get("amount_base"),
                    "from_ata": simulate.get("from_ata"),
                    "to_ata": simulate.get("to_ata")
                }
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

        // Stage 4: execute (guards)
        let simulation_ok = simulate
            .get("simulation_performed")
            .and_then(Value::as_bool)
            .unwrap_or(false)
            && simulate.get("status").and_then(Value::as_str) == Some("ok");

        let approval_ok = approval.get("status").and_then(Value::as_str) == Some("ok");

        // Optional approval override.
        let provided_override = request.override_token.clone().unwrap_or_default();
        let (override_ok, override_diag) = if provided_override.is_empty() {
            (false, None)
        } else {
            crate::utils::override_store::validate_override(&run_id, &provided_override)
                .unwrap_or((false, None))
        };

        let approval_gate_passed = approval_ok || override_ok;

        let execute = if !simulation_ok {
            // Guard 1: no-sim-no-send
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
        } else if !approval_gate_passed {
            // Guard 2: approval policy says review is needed.
            json!({
                "stage": "execute",
                "status": "blocked",
                "guard": {
                    "guard_class": "approval_required",
                    "next": {
                        "mode": "review",
                        "how_to": "Review approval warnings (price impact / slippage / route). Adjust slippage/amount or pick a different pair and re-run.",
                        "request_override": {
                            "tool": "w3rt_request_override",
                            "args": {
                                "run_id": run_id,
                                "reason": "<why you accept the risk>",
                                "ttl_ms": 300000
                            }
                        }
                    }
                },
                "approval": approval,
                "override": {
                    "provided": if provided_override.is_empty() { Value::Null } else { json!("<redacted>") },
                    "validation": override_diag
                },
                "note": "Execution blocked: approval.status != ok (policy)."
            })
        } else if intent_value["chain"] == "solana" && intent_value["action"] == "transfer_native" {

            // Sign locally (requires SOLANA_KEYPAIR_PATH) and create pending confirmation.
            let tx_b64 = simulate
                .get("tx")
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
                // Load keypair and sign.
                let kp_path = std::env::var("SOLANA_KEYPAIR_PATH").ok().filter(|s| !s.trim().is_empty())
                    .unwrap_or_else(|| {
                        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                        format!("{}/.config/solana/id.json", home)
                    });

                use solana_sdk::signer::Signer;
                let kp = solana_sdk::signature::read_keypair_file(&kp_path).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Failed to read keypair file {}: {}", kp_path, e)),
                    data: None,
                })?;

                let from = simulate.get("from").and_then(Value::as_str).unwrap_or("");
                if !from.is_empty() {
                    let from_pk = solana_sdk::pubkey::Pubkey::from_str(from).map_err(|e| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!("invalid from pubkey: {e}")),
                        data: Some(json!({"from": from})),
                    })?;
                    if kp.pubkey() != from_pk {
                        return Err(ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("SOLANA_KEYPAIR_PATH pubkey does not match sender"),
                            data: Some(json!({"sender": from_pk.to_string(), "keypair_pubkey": kp.pubkey().to_string()})),
                        });
                    }
                }

                let network = simulate.get("network").and_then(|v| v.as_str()).map(|s| s.to_string());
                let rpc = Self::solana_rpc(network.as_deref())?;
                let bh = rpc.get_latest_blockhash().await.map_err(|e| Self::sdk_error("solana_transfer:get_latest_blockhash", e))?;

                let raw = base64::engine::general_purpose::STANDARD
                    .decode(tx_b64.trim())
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!("invalid tx_base64: {e}")),
                        data: None,
                    })?;

                let mut tx = bincode::deserialize::<solana_sdk::transaction::Transaction>(&raw)
                    .map_err(|e| Self::sdk_error("solana_transfer:deserialize_tx", e))?;
                tx.message.recent_blockhash = bh;

                tx.try_sign(&[&kp], bh).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to sign tx: {}", e)),
                    data: None,
                })?;

                let bytes = bincode::serialize(&tx).map_err(|e| Self::sdk_error("solana_transfer:serialize_tx", e))?;
                let signed_b64 = base64::engine::general_purpose::STANDARD.encode(bytes);

                let summary = Some(json!({
                    "tool": "w3rt_run_workflow_v0",
                    "run_id": run_id,
                    "adapter": simulate.get("adapter"),
                    "approval": approval
                }));

                let parsed = Self::solana_create_pending_confirmation(
                    network.as_deref(),
                    &signed_b64,
                    "w3rt_run_workflow_v0",
                    summary,
                )?;

                json!({
                    "stage": "execute",
                    "status": "pending_confirmation_created",
                    "network": network,
                    "approval": approval,
                    "result": parsed,
                    "next": parsed.get("next").cloned().unwrap_or(json!({})),
                    "note": "Pending confirmation created (safe default). On mainnet you must call solana_confirm_transaction with confirm_token to broadcast."
                })
            }
        } else if intent_value["chain"] == "solana" && intent_value["action"] == "transfer_spl" {
            // Sign locally (requires SOLANA_KEYPAIR_PATH) and create pending confirmation.
            let tx_b64 = simulate
                .get("tx")
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
                let kp_path = std::env::var("SOLANA_KEYPAIR_PATH")
                    .ok()
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or_else(|| {
                        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                        format!("{}/.config/solana/id.json", home)
                    });

                use solana_sdk::signer::Signer;
                let kp = solana_sdk::signature::read_keypair_file(&kp_path).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Failed to read keypair file {}: {}", kp_path, e)),
                    data: None,
                })?;

                let from = simulate.get("from").and_then(Value::as_str).unwrap_or("");
                if !from.is_empty() {
                    let from_pk = solana_sdk::pubkey::Pubkey::from_str(from).map_err(|e| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!("invalid from pubkey: {e}")),
                        data: Some(json!({"from": from})),
                    })?;
                    if kp.pubkey() != from_pk {
                        return Err(ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("SOLANA_KEYPAIR_PATH pubkey does not match sender"),
                            data: Some(json!({"sender": from_pk.to_string(), "keypair_pubkey": kp.pubkey().to_string()})),
                        });
                    }
                }

                let network = simulate.get("network").and_then(|v| v.as_str()).map(|s| s.to_string());
                let rpc = Self::solana_rpc(network.as_deref())?;
                let bh = rpc.get_latest_blockhash().await.map_err(|e| Self::sdk_error("solana_spl_transfer:get_latest_blockhash", e))?;

                let raw = base64::engine::general_purpose::STANDARD
                    .decode(tx_b64.trim())
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!("invalid tx_base64: {e}")),
                        data: None,
                    })?;

                let mut tx = bincode::deserialize::<solana_sdk::transaction::Transaction>(&raw)
                    .map_err(|e| Self::sdk_error("solana_spl_transfer:deserialize_tx", e))?;
                tx.message.recent_blockhash = bh;

                tx.try_sign(&[&kp], bh).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to sign tx: {}", e)),
                    data: None,
                })?;

                let bytes = bincode::serialize(&tx).map_err(|e| Self::sdk_error("solana_spl_transfer:serialize_tx", e))?;
                let signed_b64 = base64::engine::general_purpose::STANDARD.encode(bytes);

                let summary = Some(json!({
                    "tool": "w3rt_run_workflow_v0",
                    "run_id": run_id,
                    "adapter": simulate.get("adapter"),
                    "approval": approval
                }));

                let parsed = Self::solana_create_pending_confirmation(
                    network.as_deref(),
                    &signed_b64,
                    "w3rt_run_workflow_v0",
                    summary,
                )?;

                json!({
                    "stage": "execute",
                    "status": "pending_confirmation_created",
                    "network": network,
                    "approval": approval,
                    "result": parsed,
                    "next": parsed.get("next").cloned().unwrap_or(json!({})),
                    "note": "Pending confirmation created (safe default). On mainnet you must call solana_confirm_transaction with confirm_token to broadcast."
                })
            }
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

                // Minimal surface: create a pending confirmation directly (do not expose solana_send_transaction).
                let summary = Some(json!({
                    "tool": "w3rt_run_workflow_v0",
                    "run_id": run_id,
                    "adapter": simulate.get("adapter"),
                    "approval": approval
                }));

                let parsed = Self::solana_create_pending_confirmation(
                    network.as_deref(),
                    tx_b64,
                    "w3rt_run_workflow_v0",
                    summary,
                )?;

                let pending_id = parsed.get("pending_confirmation_id").and_then(Value::as_str);
                let tx_hash = parsed.get("tx_summary_hash").and_then(Value::as_str);
                let confirm_token = parsed.get("confirm_token").and_then(Value::as_str);

                let mut next: Value = json!({});
                if let (Some(id), Some(h)) = (pending_id, tx_hash) {
                    // Provide a copy/paste next step.
                    let args = if confirm_token.is_some() {
                        json!({
                            "id": id,
                            "hash": h,
                            "confirm_token": confirm_token,
                            "commitment": "confirmed"
                        })
                    } else {
                        json!({
                            "id": id,
                            "hash": h,
                            "commitment": "confirmed"
                        })
                    };

                    next = json!({
                        "confirm": {
                            "tool": "solana_confirm_transaction",
                            "args": args
                        }
                    });
                }

                json!({
                    "stage": "execute",
                    "status": "pending_confirmation_created",
                    "network": network,
                    "approval": approval,
                    "result": parsed,
                    "next": next,
                    "note": "Pending confirmation created (safe default). On mainnet you must call solana_confirm_transaction with confirm_token to broadcast."
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

