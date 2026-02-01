    fn solana_rpc_url_for_network(network: Option<&str>) -> Result<String, ErrorData> {
        // Priority:
        // 1) SOLANA_RPC_URL (explicit override)
        // 2) SOLANA_RPC_URL_MAINNET / _DEVNET / _TESTNET
        // 3) well-known public endpoints
        if let Ok(url) = std::env::var("SOLANA_RPC_URL") {
            return Ok(url);
        }

        let net = network.unwrap_or("mainnet").trim().to_lowercase();
        let (env_key, default_url) = match net.as_str() {
            "mainnet" | "mainnet-beta" | "mainnet_beta" => (
                "SOLANA_RPC_URL_MAINNET",
                "https://api.mainnet-beta.solana.com",
            ),
            "devnet" => ("SOLANA_RPC_URL_DEVNET", "https://api.devnet.solana.com"),
            "testnet" => ("SOLANA_RPC_URL_TESTNET", "https://api.testnet.solana.com"),
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("network must be one of: mainnet|devnet|testnet"),
                    data: Some(json!({"provided": net})),
                })
            }
        };

        Ok(std::env::var(env_key).unwrap_or_else(|_| default_url.to_string()))
    }

    fn solana_rpc_url_default() -> String {
        Self::solana_rpc_url_for_network(None)
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

    fn solana_rpc(
        network: Option<&str>,
    ) -> Result<solana_client::nonblocking::rpc_client::RpcClient, ErrorData> {
        let url = Self::solana_rpc_url_for_network(network)?;
        Ok(solana_client::nonblocking::rpc_client::RpcClient::new(url))
    }

    #[tool(description = "Solana: get wallet address from SOLANA_KEYPAIR_PATH JSON")]
    async fn solana_get_wallet_address(&self) -> Result<CallToolResult, ErrorData> {
        let kp_path = Self::solana_keypair_path()?;
        let kp = Self::solana_read_keypair_from_json_file(&kp_path)?;
        let addr = solana_sdk::signature::Signer::pubkey(&kp).to_string();
        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_default(),
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
        let client = Self::solana_rpc(request.network.as_deref())?;
        let lamports = client
            .get_balance(&addr)
            .await
            .map_err(|e| Self::sdk_error("solana_get_balance", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
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
        let client = Self::solana_rpc(request.network.as_deref())?;

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
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
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
        let client = Self::solana_rpc(request.network.as_deref())?;
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;

        let res = client
            .get_latest_blockhash_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_latest_blockhash", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
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
        let client = Self::solana_rpc(request.network.as_deref())?;
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
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
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
        let client = Self::solana_rpc(request.network.as_deref())?;
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
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "signature": sig.to_string(),
            "transaction": tx
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get current slot")]
    async fn solana_get_slot(
        &self,
        Parameters(request): Parameters<SolanaGetSlotRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;
        let slot = client
            .get_slot_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_slot", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "commitment": request.commitment.unwrap_or("confirmed".to_string()),
            "slot": slot
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get current block height")]
    async fn solana_get_block_height(
        &self,
        Parameters(request): Parameters<SolanaGetBlockHeightRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;
        let height = client
            .get_block_height_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_block_height", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "commitment": request.commitment.unwrap_or("confirmed".to_string()),
            "block_height": height
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: request airdrop (devnet/testnet only)")]
    async fn solana_request_airdrop(
        &self,
        Parameters(request): Parameters<SolanaRequestAirdropRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let net = request.network.as_deref().unwrap_or("devnet").trim().to_lowercase();
        if net == "mainnet" || net == "mainnet-beta" || net == "mainnet_beta" {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("airdrop is only supported on devnet/testnet"),
                data: Some(json!({"network": net})),
            });
        }

        let client = Self::solana_rpc(Some(&net))?;
        let addr = Self::solana_parse_pubkey(request.address.trim(), "address")?;
        let sig = client
            .request_airdrop(&addr, request.lamports)
            .await
            .map_err(|e| Self::sdk_error("solana_request_airdrop", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(Some(&net))?,
            "network": net,
            "address": addr.to_string(),
            "lamports": request.lamports,
            "signature": sig.to_string(),
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: list SPL token accounts for an owner (optionally filter by mint)")]
    async fn solana_get_token_accounts(
        &self,
        Parameters(request): Parameters<SolanaGetTokenAccountsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;

        // Note: solana-client currently fixes encoding=jsonParsed for get_token_accounts_by_owner_with_commitment.
        // We accept encoding param for API compatibility, but only support jsonParsed here.
        let encoding = request.encoding.as_deref().unwrap_or("jsonParsed").to_lowercase();
        if !(encoding == "jsonparsed" || encoding == "json_parsed") {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("encoding must be jsonParsed for this tool"),
                data: Some(json!({ "provided": encoding })),
            });
        }

        let filter = if let Some(m) = request.mint.as_deref() {
            let mint = Self::solana_parse_pubkey(m.trim(), "mint")?;
            solana_client::rpc_request::TokenAccountsFilter::Mint(mint)
        } else {
            solana_client::rpc_request::TokenAccountsFilter::ProgramId(
                solana_sdk::pubkey::Pubkey::from_str("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap(),
            )
        };

        let commitment = solana_commitment_config::CommitmentConfig::confirmed();
        let res = client
            .get_token_accounts_by_owner_with_commitment(&owner, filter, commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_token_accounts", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "owner": owner.to_string(),
            "mint": request.mint,
            "encoding": "jsonParsed",
            "context": res.context,
            "value": res.value
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get SPL token balance for owner+mint (aggregates all token accounts)")]
    async fn solana_get_token_balance(
        &self,
        Parameters(request): Parameters<SolanaGetTokenBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;

        let commitment = solana_commitment_config::CommitmentConfig::confirmed();
        let res = client
            .get_token_accounts_by_owner_with_commitment(
                &owner,
                solana_client::rpc_request::TokenAccountsFilter::Mint(mint),
                commitment,
            )
            .await
            .map_err(|e| Self::sdk_error("solana_get_token_balance", e))?;

        // Best-effort parse jsonParsed layout: value[i].account.data.parsed.info.tokenAmount
        let mut total_raw: u128 = 0;
        let mut decimals: Option<u8> = None;
        let mut accounts: Vec<Value> = Vec::new();

        for keyed in &res.value {
            let v = serde_json::to_value(keyed).unwrap_or(Value::Null);
            // Extract tokenAmount fields
            let ta = v
                .pointer("/account/data/parsed/info/tokenAmount")
                .cloned()
                .unwrap_or(Value::Null);
            let amount_raw = ta
                .get("amount")
                .and_then(|x| x.as_str())
                .and_then(|s| s.parse::<u128>().ok())
                .unwrap_or(0);
            let dec = ta.get("decimals").and_then(|x| x.as_u64()).map(|d| d as u8);
            if decimals.is_none() {
                decimals = dec;
            }
            total_raw = total_raw.saturating_add(amount_raw);
            accounts.push(v);
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "owner": owner.to_string(),
            "mint": mint.to_string(),
            "encoding": "jsonParsed",
            "decimals": decimals,
            "total_amount_raw": total_raw.to_string(),
            "token_accounts_count": accounts.len(),
            "token_accounts": accounts
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    async fn solana_wait_for_signature(
        client: &solana_client::nonblocking::rpc_client::RpcClient,
        sig: &solana_sdk::signature::Signature,
        commitment: &str,
        timeout_ms: u64,
    ) -> Result<serde_json::Value, ErrorData> {
        use solana_transaction_status::TransactionConfirmationStatus as Tcs;

        let want = commitment.trim().to_lowercase();
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_ms);

        loop {
            let res = client
                .get_signature_statuses(&[*sig])
                .await
                .map_err(|e| Self::sdk_error("solana_wait_for_signature", e))?;

            let st = res.value.get(0).cloned().unwrap_or(None);
            if let Some(s) = st {
                if let Some(err) = s.err {
                    return Err(ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("Transaction failed"),
                        data: Some(json!({"signature": sig.to_string(), "err": err})),
                    });
                }

                let level_ok = match want.as_str() {
                    "processed" => true,
                    "confirmed" => matches!(s.confirmation_status, Some(Tcs::Confirmed | Tcs::Finalized)),
                    "finalized" => matches!(s.confirmation_status, Some(Tcs::Finalized)),
                    _ => true,
                };

                if level_ok {
                    return Ok(json!({
                        "signature": sig.to_string(),
                        "confirmation_status": s.confirmation_status,
                        "confirmations": s.confirmations,
                        "slot": s.slot,
                        "status": "ok"
                    }));
                }
            }

            if std::time::Instant::now() >= deadline {
                return Ok(json!({
                    "signature": sig.to_string(),
                    "status": "timeout"
                }));
            }

            tokio::time::sleep(std::time::Duration::from_millis(800)).await;
        }
    }

    fn solana_try_sign_if_needed(
        tx: &mut solana_sdk::transaction::Transaction,
        kp: Option<&solana_sdk::signature::Keypair>,
    ) {
        if let Some(k) = kp {
            // If signatures are missing or default, attempt to sign.
            let all_default = tx.signatures.iter().all(|s| *s == solana_sdk::signature::Signature::default());
            if tx.signatures.is_empty() || all_default {
                let bh = tx.message.recent_blockhash;
                tx.sign(&[k], bh);
            }
        }
    }

    #[tool(description = "Solana: build a (optionally signed) transaction from one or more instructions")]
    async fn solana_tx_build(
        &self,
        Parameters(request): Parameters<SolanaTxBuildRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let rpc_url = Self::solana_rpc_url_for_network(network)?;
        let client = Self::solana_rpc(network)?;

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set"),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_tx_build", e))?
        };

        if request.instructions.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("instructions is required"),
                data: None,
            });
        }

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();
        let mut ix_summaries: Vec<Value> = Vec::new();

        for (idx, ix) in request.instructions.iter().enumerate() {
            let program_id = Self::solana_parse_program_id(ix.program_id.trim())?;
            let data = base64::engine::general_purpose::STANDARD
                .decode(ix.data_base64.trim())
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid data_base64 for instruction {}: {}", idx, e)),
                    data: None,
                })?;

            let mut metas: Vec<solana_sdk::instruction::AccountMeta> = Vec::new();
            for m in &ix.accounts {
                let pk = Self::solana_parse_pubkey(m.pubkey.trim(), "account pubkey")?;
                metas.push(if m.is_writable {
                    solana_sdk::instruction::AccountMeta::new(pk, m.is_signer)
                } else {
                    solana_sdk::instruction::AccountMeta::new_readonly(pk, m.is_signer)
                });
            }

            ixs.push(solana_sdk::instruction::Instruction {
                program_id,
                accounts: metas,
                data,
            });

            ix_summaries.push(json!({
                "index": idx,
                "program_id": ix.program_id,
                "accounts_count": ix.accounts.len(),
                "data_base64_len": ix.data_base64.len()
            }));
        }

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));

        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;

        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "fee_payer": fee_payer.to_string(),
            "recent_blockhash": recent_blockhash.to_string(),
            "signed": sign,
            "keypair_path": kp_path,
            "instructions": ix_summaries,
            "transaction_base64": tx_base64,
            "transaction_bytes_len": tx_bytes.len(),
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: send a transaction (safe default: creates pending confirmation unless confirm=true)")]
    async fn solana_send_transaction(
        &self,
        Parameters(request): Parameters<SolanaSendTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let rpc_url = Self::solana_rpc_url_for_network(network)?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(request.transaction_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {}", e)),
                data: None,
            })?;

        let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

        if !request.confirm.unwrap_or(false) {
            // Safe default: do not broadcast.
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": request.network.clone().unwrap_or("mainnet".to_string()),
                "rpc_url": rpc_url,
                "tx_bytes_len": tx_bytes.len(),
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                request.transaction_base64.trim(),
                created,
                expires,
                &hash,
                "solana_send_transaction",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call solana_confirm_transaction to broadcast and wait.",
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let client = Self::solana_rpc(network)?;

        let mut tx: solana_sdk::transaction::Transaction =
            bincode::deserialize(&tx_bytes).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction bytes: {}", e)),
                data: None,
            })?;

        // Try to sign if needed and keypair is available.
        let kp = Self::solana_keypair_path()
            .ok()
            .and_then(|p| Self::solana_read_keypair_from_json_file(&p).ok());
        Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let sig = client
            .send_transaction_with_config(
                &tx,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(request.commitment.as_deref())?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_send_transaction", e))?;

        let timeout_ms = request.timeout_ms.unwrap_or(60_000);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "signature": sig.to_string(),
            "tx_summary_hash": hash,
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: confirm and broadcast a pending transaction created by solana_send_transaction")]
    async fn solana_confirm_transaction(
        &self,
        Parameters(request): Parameters<SolanaConfirmTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // Best-effort cleanup
        let _ = crate::utils::solana_confirm_store::cleanup_expired();

        let pending = crate::utils::solana_confirm_store::get_pending(&request.id)?;
        if pending.tx_summary_hash != request.hash {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Hash mismatch for confirmation id"),
                data: Some(json!({
                    "id": request.id,
                    "expected": pending.tx_summary_hash,
                    "provided": request.hash
                })),
            });
        }

        let network = request
            .network
            .clone()
            .or_else(|| pending.summary.as_ref().and_then(|v| v.get("network").and_then(|x| x.as_str()).map(|s| s.to_string())))
            .unwrap_or("mainnet".to_string());

        let rpc_url = Self::solana_rpc_url_for_network(Some(&network))?;
        let client = Self::solana_rpc(Some(&network))?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(pending.tx_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid stored tx_base64: {}", e)),
                data: None,
            })?;

        let mut tx: solana_sdk::transaction::Transaction =
            bincode::deserialize(&tx_bytes).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid stored transaction bytes: {}", e)),
                data: None,
            })?;

        // Sign if needed.
        let kp_path = Self::solana_keypair_path().ok();
        let kp = kp_path
            .as_deref()
            .and_then(|p| Self::solana_read_keypair_from_json_file(p).ok());
        Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let sig = client
            .send_transaction_with_config(
                &tx,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(request.commitment.as_deref())?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_confirm_transaction", e))?;

        let timeout_ms = request.timeout_ms.unwrap_or(60_000);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        // If we got ok, remove pending; if timeout, keep it for retry.
        if waited.get("status").and_then(|v| v.as_str()) == Some("ok") {
            let _ = crate::utils::solana_confirm_store::remove_pending(&request.id);
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network,
            "confirmation_id": request.id,
            "tx_summary_hash": request.hash,
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "note": "If wait.status==timeout you can call solana_confirm_transaction again with same id/hash."
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

    #[tool(description = "Solana IDL: plan an instruction from registered IDL (offline; optional on-chain validation)")]
    async fn solana_idl_plan_instruction(
        &self,
        Parameters(request): Parameters<SolanaIdlPlanInstructionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref().unwrap_or("mainnet");
        let rpc_url = Self::solana_rpc_url_for_network(Some(network))?;

        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();
        let name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction = request.instruction.trim().to_string();

        let idl = crate::utils::solana_idl_registry::read_idl(&program_id, &name)?;
        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction)?;

        let args_obj = request.args.unwrap_or_else(|| json!({}));
        let accounts_obj = request.accounts.unwrap_or_else(|| json!({}));

        let mut missing_args: Vec<String> = Vec::new();
        let mut args_schema: Vec<Value> = Vec::new();
        for a in &ix.args {
            args_schema.push(json!({"name": a.name, "type": a.ty}));
            if args_obj.get(&a.name).is_none() {
                missing_args.push(a.name.clone());
            }
        }

        let mut missing_accounts: Vec<String> = Vec::new();
        let mut accounts_needed: Vec<Value> = Vec::new();
        for a in &ix.accounts {
            let has = accounts_obj.get(&a.name).and_then(|v| v.as_str()).is_some();
            if !has {
                missing_accounts.push(a.name.clone());
            }
            accounts_needed.push(json!({
                "name": a.name,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut,
                "provided": accounts_obj.get(&a.name)
            }));
        }

        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(network))?;
            let mut checks: Vec<Value> = Vec::new();

            // Validate any provided accounts (do not error if missing; just report missing).
            for a in &ix.accounts {
                if let Some(pk_str) = accounts_obj.get(&a.name).and_then(|v| v.as_str()) {
                    let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", a.name))?;
                    let acc = client
                        .get_account(&pk)
                        .await
                        .ok();
                    checks.push(json!({
                        "name": a.name,
                        "pubkey": pk.to_string(),
                        "exists": acc.is_some(),
                        "owner": acc.as_ref().map(|x| x.owner.to_string()),
                        "lamports": acc.as_ref().map(|x| x.lamports),
                        "data_len": acc.as_ref().map(|x| x.data.len()),
                        "executable": acc.as_ref().map(|x| x.executable),
                    }));
                } else {
                    checks.push(json!({
                        "name": a.name,
                        "pubkey": null,
                        "exists": null,
                        "note": "not provided"
                    }));
                }
            }

            onchain = Some(json!({
                "checks": checks
            }));
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network,
            "program_id": program_id,
            "idl_name": name,
            "instruction": ix.name,
            "args_schema": args_schema,
            "accounts_needed": accounts_needed,
            "missing": {
                "args": missing_args,
                "accounts": missing_accounts
            },
            "validate_on_chain": validate,
            "onchain": onchain,
            "tool_context": json!({
                "tool": "solana_idl_plan_instruction"
            }),
            "summary": json!({
                "program_id": program_id,
                "idl_name": name,
                "instruction": instruction,
                "missing_args": missing_args,
                "missing_accounts": missing_accounts
            })
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn solana_json_metas_to_account_metas(
        metas: &[Value],
    ) -> Result<Vec<solana_sdk::instruction::AccountMeta>, ErrorData> {
        let mut out: Vec<solana_sdk::instruction::AccountMeta> = Vec::new();
        for m in metas {
            let pk_str = m
                .get("pubkey")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("account meta missing pubkey"),
                    data: Some(json!({"meta": m})),
                })?;
            let is_signer = m
                .get("is_signer")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let is_writable = m
                .get("is_writable")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let pk = Self::solana_parse_pubkey(pk_str, "account pubkey")?;
            out.push(if is_writable {
                solana_sdk::instruction::AccountMeta::new(pk, is_signer)
            } else {
                solana_sdk::instruction::AccountMeta::new_readonly(pk, is_signer)
            });
        }
        Ok(out)
    }

    #[tool(description = "Solana IDL: build an instruction (program_id + accounts metas + data_base64) from registered IDL")]
    async fn solana_idl_build_instruction(
        &self,
        Parameters(request): Parameters<SolanaIdlBuildInstructionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref().unwrap_or("mainnet");
        let rpc_url = Self::solana_rpc_url_for_network(Some(network))?;

        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();
        let name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction = request.instruction.trim().to_string();

        let idl = crate::utils::solana_idl_registry::read_idl(&program_id, &name)?;
        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction)?;

        let args_obj = request.args;
        let accounts_obj = request.accounts;

        // args in order
        let mut args_pairs: Vec<(crate::utils::solana_idl::IdlArg, Value)> = Vec::new();
        let mut missing_args: Vec<String> = Vec::new();
        for a in &ix.args {
            let v = args_obj.get(&a.name).cloned();
            if v.is_none() {
                missing_args.push(a.name.clone());
                continue;
            }
            args_pairs.push((a.clone(), v.unwrap()));
        }
        if !missing_args.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required args"),
                data: Some(json!({"missing_args": missing_args})),
            });
        }

        let mut metas: Vec<Value> = Vec::new();
        let mut missing_accounts: Vec<String> = Vec::new();
        for a in &ix.accounts {
            let pk = accounts_obj.get(&a.name).and_then(|v| v.as_str()).map(|s| s.to_string());
            if pk.is_none() {
                missing_accounts.push(a.name.clone());
                continue;
            }
            // Validate pubkey format now
            let _ = Self::solana_parse_pubkey(pk.as_ref().unwrap(), &format!("account:{}", a.name))?;
            metas.push(json!({
                "name": a.name,
                "pubkey": pk,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut
            }));
        }
        if !missing_accounts.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required accounts"),
                data: Some(json!({"missing_accounts": missing_accounts})),
            });
        }

        let data = crate::utils::solana_idl::encode_anchor_ix_data(&idl, &ix.name, &args_pairs)?;
        let data_b64 = base64::engine::general_purpose::STANDARD.encode(&data);

        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(network))?;
            let mut checks: Vec<Value> = Vec::new();

            for m in &metas {
                let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let pk_str = m.get("pubkey").and_then(|v| v.as_str()).unwrap_or("");
                let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", name))?;

                let acc = client.get_account(&pk).await.ok();
                checks.push(json!({
                    "name": name,
                    "pubkey": pk.to_string(),
                    "exists": acc.is_some(),
                    "owner": acc.as_ref().map(|x| x.owner.to_string()),
                    "lamports": acc.as_ref().map(|x| x.lamports),
                    "data_len": acc.as_ref().map(|x| x.data.len()),
                    "executable": acc.as_ref().map(|x| x.executable),
                }));
            }

            onchain = Some(json!({
                "checks": checks
            }));
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network,
            "program_id": program_id,
            "idl_name": name,
            "instruction": ix.name,
            "accounts": metas,
            "data_base64": data_b64,
            "validate_on_chain": validate,
            "onchain": onchain,
            "tool_context": json!({
                "tool": "solana_idl_build_instruction"
            }),
            "summary": json!({
                "program_id": program_id,
                "idl_name": name,
                "instruction": instruction,
                "accounts_count": ix.accounts.len(),
                "args_count": ix.args.len(),
                "data_len": data.len()
            })
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana IDL: build tx and (optionally) send it. Safe default: creates pending confirmation unless confirm=true")]
    async fn solana_idl_execute(
        &self,
        Parameters(request): Parameters<SolanaIdlExecuteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;

        let program_id_pk = Self::solana_parse_program_id(request.program_id.trim())?;
        let program_id = program_id_pk.to_string();
        let idl_name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction_name = request.instruction.trim().to_string();

        // 1) Build instruction (IDL)
        let idl = crate::utils::solana_idl_registry::read_idl(&program_id, &idl_name)?;
        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction_name)?;

        // args in order
        let mut args_pairs: Vec<(crate::utils::solana_idl::IdlArg, Value)> = Vec::new();
        let mut missing_args: Vec<String> = Vec::new();
        for a in &ix.args {
            let v = request.args.get(&a.name).cloned();
            if v.is_none() {
                missing_args.push(a.name.clone());
                continue;
            }
            args_pairs.push((a.clone(), v.unwrap()));
        }
        if !missing_args.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required args"),
                data: Some(json!({"missing_args": missing_args})),
            });
        }

        let mut metas_json: Vec<Value> = Vec::new();
        let mut missing_accounts: Vec<String> = Vec::new();
        for a in &ix.accounts {
            let pk = request
                .accounts
                .get(&a.name)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            if pk.is_none() {
                missing_accounts.push(a.name.clone());
                continue;
            }
            let _ = Self::solana_parse_pubkey(pk.as_ref().unwrap(), &format!("account:{}", a.name))?;
            metas_json.push(json!({
                "name": a.name,
                "pubkey": pk,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut
            }));
        }
        if !missing_accounts.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required accounts"),
                data: Some(json!({"missing_accounts": missing_accounts})),
            });
        }

        let data = crate::utils::solana_idl::encode_anchor_ix_data(&idl, &ix.name, &args_pairs)?;
        let data_b64 = base64::engine::general_purpose::STANDARD.encode(&data);

        // Optional on-chain checks
        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(&network_str))?;
            let mut checks: Vec<Value> = Vec::new();
            for m in &metas_json {
                let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let pk_str = m.get("pubkey").and_then(|v| v.as_str()).unwrap_or("");
                let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", name))?;
                let acc = client.get_account(&pk).await.ok();
                checks.push(json!({
                    "name": name,
                    "pubkey": pk.to_string(),
                    "exists": acc.is_some(),
                    "owner": acc.as_ref().map(|x| x.owner.to_string()),
                    "lamports": acc.as_ref().map(|x| x.lamports),
                    "data_len": acc.as_ref().map(|x| x.data.len()),
                    "executable": acc.as_ref().map(|x| x.executable),
                }));
            }
            onchain = Some(json!({"checks": checks}));
        }

        // 2) Build transaction
        let client = Self::solana_rpc(Some(&network_str))?;

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set"),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_idl_execute", e))?
        };

        let account_metas = Self::solana_json_metas_to_account_metas(&metas_json)?;
        let ixn = solana_sdk::instruction::Instruction {
            program_id: program_id_pk,
            accounts: account_metas,
            data: data.clone(),
        };

        let message = solana_sdk::message::Message::new(&[ixn], Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;
        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        // 3) Send (or create pending)
        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "program_id": program_id,
                "idl_name": idl_name,
                "instruction": instruction_name,
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_idl_execute",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "rpc_url": rpc_url,
                "network": summary.get("network").unwrap(),
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "instruction": {
                    "program_id": program_id,
                    "accounts": metas_json,
                    "data_base64": data_b64,
                    "validate_on_chain": validate,
                    "onchain": onchain
                },
                "transaction": {
                    "fee_payer": fee_payer.to_string(),
                    "recent_blockhash": recent_blockhash.to_string(),
                    "signed": sign,
                    "keypair_path": kp_path,
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len()
                },
                "expires_in_ms": ttl,
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        // confirm=true: broadcast now
        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        // If tx isn't signed, attempt to sign if SOLANA_KEYPAIR_PATH exists.
        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());

        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_idl_execute", e))?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "commitment": commitment,
            "wait": waited,
            "instruction": {
                "program_id": program_id,
                "accounts": metas_json,
                "data_base64": data_b64,
                "validate_on_chain": validate,
                "onchain": onchain
            },
            "transaction": {
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": true,
                "keypair_path": kp_path,
                "transaction_base64": tx_base64,
                "transaction_bytes_len": tx_bytes.len()
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
