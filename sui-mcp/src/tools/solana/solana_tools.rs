    fn solana_rpc_url() -> String {
        // Priority:
        // 1) SOLANA_RPC_URL
        // 2) default to mainnet-beta public endpoint (safe, but rate-limited)
        std::env::var("SOLANA_RPC_URL")
            .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string())
    }

    fn solana_keypair_path() -> Result<String, ErrorData> {
        std::env::var("SOLANA_KEYPAIR_PATH").map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(
                "Missing SOLANA_KEYPAIR_PATH env var (path to Solana JSON keypair file)",
            ),
            data: None,
        })
    }

    fn solana_read_keypair_from_json_file(
        path: &str,
    ) -> Result<solana_sdk::signature::Keypair, ErrorData> {
        let data = std::fs::read_to_string(path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read keypair file: {}", e)),
            data: None,
        })?;
        let arr: Vec<u8> = serde_json::from_str(&data).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid Solana keypair JSON: {}", e)),
            data: None,
        })?;
        solana_sdk::signature::Keypair::try_from(arr.as_slice()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid Solana keypair bytes: {}", e)),
            data: None,
        })
    }

    fn solana_parse_pubkey(value: &str, label: &str) -> Result<solana_sdk::pubkey::Pubkey, ErrorData> {
        solana_sdk::pubkey::Pubkey::from_str(value).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid {}: {}", label, e)),
            data: None,
        })
    }

    fn solana_parse_program_id(program_id: &str) -> Result<solana_sdk::pubkey::Pubkey, ErrorData> {
        Self::solana_parse_pubkey(program_id, "program_id")
    }

    fn solana_commitment_from_str(
        s: Option<&str>,
    ) -> Result<solana_commitment_config::CommitmentConfig, ErrorData> {
        let v = s.unwrap_or("confirmed").trim().to_lowercase();
        let c = match v.as_str() {
            "processed" => solana_commitment_config::CommitmentConfig::processed(),
            "confirmed" => solana_commitment_config::CommitmentConfig::confirmed(),
            "finalized" => solana_commitment_config::CommitmentConfig::finalized(),
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("commitment must be one of: processed|confirmed|finalized"),
                    data: Some(json!({ "provided": v })),
                })
            }
        };
        Ok(c)
    }

    fn solana_rpc() -> solana_client::nonblocking::rpc_client::RpcClient {
        solana_client::nonblocking::rpc_client::RpcClient::new(Self::solana_rpc_url())
    }

    #[tool(description = "Solana: get wallet address from SOLANA_KEYPAIR_PATH JSON")]
    async fn solana_get_wallet_address(&self) -> Result<CallToolResult, ErrorData> {
        let kp_path = Self::solana_keypair_path()?;
        let kp = Self::solana_read_keypair_from_json_file(&kp_path)?;
        let addr = solana_sdk::signature::Signer::pubkey(&kp).to_string();
        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "keypair_path": kp_path,
            "address": addr
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // ---------------- Solana common RPC tools ----------------

    #[tool(description = "Solana: get balance (lamports) for an address")]
    async fn solana_get_balance(
        &self,
        Parameters(request): Parameters<SolanaGetBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let addr = Self::solana_parse_pubkey(request.address.trim(), "address")?;
        let client = Self::solana_rpc();
        let lamports = client
            .get_balance(&addr)
            .await
            .map_err(|e| Self::sdk_error("solana_get_balance", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "address": addr.to_string(),
            "lamports": lamports
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get account info (optionally with encoding)")]
    async fn solana_get_account_info(
        &self,
        Parameters(request): Parameters<SolanaGetAccountInfoRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let addr = Self::solana_parse_pubkey(request.address.trim(), "address")?;
        let client = Self::solana_rpc();

        let encoding = request.encoding.as_deref().unwrap_or("base64").to_lowercase();
        let enc = match encoding.as_str() {
            "base64" => solana_rpc_client_api::response::UiAccountEncoding::Base64,
            "base64+zstd" | "base64zstd" => solana_rpc_client_api::response::UiAccountEncoding::Base64Zstd,
            "jsonparsed" | "json_parsed" => solana_rpc_client_api::response::UiAccountEncoding::JsonParsed,
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("encoding must be one of: base64|base64+zstd|jsonParsed"),
                    data: Some(json!({ "provided": encoding })),
                })
            }
        };

        let cfg = solana_client::rpc_config::RpcAccountInfoConfig {
            encoding: Some(enc),
            commitment: Some(solana_commitment_config::CommitmentConfig::confirmed()),
            ..Default::default()
        };

        let res = client
            .get_ui_account_with_config(&addr, cfg)
            .await
            .map_err(|e| Self::sdk_error("solana_get_account_info", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "address": addr.to_string(),
            "context": res.context,
            "value": res.value
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get latest blockhash")]
    async fn solana_get_latest_blockhash(
        &self,
        Parameters(request): Parameters<SolanaGetLatestBlockhashRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc();
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;

        let res = client
            .get_latest_blockhash_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_latest_blockhash", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "commitment": request.commitment.unwrap_or("confirmed".to_string()),
            "blockhash": res.0.to_string(),
            "last_valid_block_height": res.1
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get signature status")]
    async fn solana_get_signature_status(
        &self,
        Parameters(request): Parameters<SolanaGetSignatureStatusRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc();
        let sig = solana_sdk::signature::Signature::from_str(request.signature.trim()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid signature: {}", e)),
            data: None,
        })?;

        let search_history = request.search_transaction_history.unwrap_or(false);
        let res = if search_history {
            client
                .get_signature_statuses_with_history(&[sig])
                .await
                .map_err(|e| Self::sdk_error("solana_get_signature_status", e))?
        } else {
            client
                .get_signature_statuses(&[sig])
                .await
                .map_err(|e| Self::sdk_error("solana_get_signature_status", e))?
        };

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "signature": sig.to_string(),
            "search_transaction_history": search_history,
            "context": res.context,
            "value": res.value.get(0).cloned().unwrap_or(None)
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get transaction by signature")]
    async fn solana_get_transaction(
        &self,
        Parameters(request): Parameters<SolanaGetTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc();
        let sig = solana_sdk::signature::Signature::from_str(request.signature.trim()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid signature: {}", e)),
            data: None,
        })?;

        let encoding = request.encoding.as_deref().unwrap_or("json").to_lowercase();
        let enc = match encoding.as_str() {
            "json" => solana_transaction_status::UiTransactionEncoding::Json,
            "jsonparsed" | "json_parsed" => solana_transaction_status::UiTransactionEncoding::JsonParsed,
            "base64" => solana_transaction_status::UiTransactionEncoding::Base64,
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("encoding must be one of: json|jsonParsed|base64"),
                    data: Some(json!({ "provided": encoding })),
                })
            }
        };

        let cfg = solana_client::rpc_config::RpcTransactionConfig {
            encoding: Some(enc),
            commitment: Some(solana_commitment_config::CommitmentConfig::confirmed()),
            max_supported_transaction_version: Some(request.max_supported_transaction_version.unwrap_or(0)),
        };

        let tx = client
            .get_transaction_with_config(&sig, cfg)
            .await
            .map_err(|e| Self::sdk_error("solana_get_transaction", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "signature": sig.to_string(),
            "transaction": tx
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // ---------------- Solana IDL Registry ----------------

    #[tool(description = "Solana IDL Registry: register an IDL JSON under abi_registry/solana/<program_id>/<name>.json")]
    async fn solana_idl_register(
        &self,
        Parameters(request): Parameters<SolanaIdlRegisterRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // validate program id
        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();

        let idl: Value = serde_json::from_str(&request.idl_json).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid IDL JSON: {}", e)),
            data: None,
        })?;

        let inferred = crate::utils::solana_idl_registry::infer_name_from_idl_json(&idl)
            .unwrap_or_else(|| "default".to_string());
        let name_raw = request.name.unwrap_or(inferred);
        let name = crate::utils::solana_idl_registry::sanitize_name(&name_raw);
        if name.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("IDL name is empty after sanitization"),
                data: Some(json!({ "provided": name_raw })),
            });
        }

        let overwrite = request.overwrite.unwrap_or(false);
        let path = crate::utils::solana_idl_registry::write_idl(&program_id, &name, &idl, overwrite)?;

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "program_id": program_id,
            "name": name,
            "path": path.to_string_lossy(),
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana IDL Registry: register an IDL JSON from a local file path")]
    async fn solana_idl_register_file(
        &self,
        Parameters(request): Parameters<SolanaIdlRegisterFileRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();

        let data = std::fs::read_to_string(&request.path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read file: {}", e)),
            data: Some(json!({ "path": request.path })),
        })?;
        let idl: Value = serde_json::from_str(&data).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid IDL JSON: {}", e)),
            data: Some(json!({ "path": request.path })),
        })?;

        let inferred = crate::utils::solana_idl_registry::infer_name_from_idl_json(&idl).or_else(|| {
            std::path::Path::new(&request.path)
                .file_stem()
                .and_then(|s| s.to_str())
                .map(|s| s.to_string())
        }).unwrap_or_else(|| "default".to_string());

        let name_raw = request.name.unwrap_or(inferred);
        let name = crate::utils::solana_idl_registry::sanitize_name(&name_raw);
        let overwrite = request.overwrite.unwrap_or(false);
        let path = crate::utils::solana_idl_registry::write_idl(&program_id, &name, &idl, overwrite)?;

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "program_id": program_id,
            "name": name,
            "path": path.to_string_lossy(),
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana IDL Registry: list registered programs and names")]
    async fn solana_idl_list(
        &self,
        Parameters(request): Parameters<SolanaIdlListRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let items = crate::utils::solana_idl_registry::list_programs()?;

        let filter = request
            .program_id
            .as_deref()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let mut out: Vec<Value> = Vec::new();
        for (pid, names) in items {
            if let Some(ref f) = filter {
                if pid != *f {
                    continue;
                }
            }
            out.push(json!({
                "program_id": pid,
                "names": names
            }));
        }

        let response = Self::pretty_json(&json!({
            "root": crate::utils::solana_idl_registry::registry_root().to_string_lossy(),
            "count": out.len(),
            "items": out
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana IDL Registry: get a registered IDL")]
    async fn solana_idl_get(
        &self,
        Parameters(request): Parameters<SolanaIdlGetRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();
        let name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        if name.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("IDL name is empty after sanitization"),
                data: None,
            });
        }

        let idl = crate::utils::solana_idl_registry::read_idl(&program_id, &name)?;
        let response = Self::pretty_json(&json!({
            "program_id": program_id,
            "name": name,
            "idl": idl
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana IDL Registry: search registered IDLs by program_id or name")]
    async fn solana_idl_search(
        &self,
        Parameters(request): Parameters<SolanaIdlSearchRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let q = request.query.trim().to_lowercase();
        if q.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("query is required"),
                data: None,
            });
        }

        let limit = request.limit.unwrap_or(50).min(500) as usize;
        let items = crate::utils::solana_idl_registry::list_programs()?;
        let mut out: Vec<Value> = Vec::new();

        for (pid, names) in items {
            let pid_l = pid.to_lowercase();
            let pid_hit = pid_l.contains(&q);
            for n in names {
                let nl = n.to_lowercase();
                if pid_hit || nl.contains(&q) {
                    out.push(json!({
                        "program_id": pid,
                        "name": n,
                        "path": crate::utils::solana_idl_registry::idl_path(&pid, &n).to_string_lossy()
                    }));
                    if out.len() >= limit {
                        break;
                    }
                }
            }
            if out.len() >= limit {
                break;
            }
        }

        let response = Self::pretty_json(&json!({
            "query": q,
            "count": out.len(),
            "items": out
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
