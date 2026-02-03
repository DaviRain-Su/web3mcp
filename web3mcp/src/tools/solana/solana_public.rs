    // ---------------- Solana minimal public surface (W3RT) ----------------

    fn solana_rpc_url_default() -> String {
        // Solana mainnet-beta
        "https://api.mainnet-beta.solana.com".to_string()
    }

    fn solana_is_mainnet_network(network: Option<&str>) -> bool {
        let n = network.unwrap_or("mainnet").trim().to_lowercase();
        n == "mainnet" || n == "mainnet-beta" || n.contains("mainnet")
    }

    fn solana_rpc_url_for_network(network: Option<&str>) -> Result<String, ErrorData> {
        let n = network.unwrap_or("mainnet").trim().to_lowercase();
        // Allow override
        if let Ok(url) = std::env::var("SOLANA_RPC_URL") {
            if !url.trim().is_empty() {
                return Ok(url);
            }
        }

        // Minimal mapping.
        let url = match n.as_str() {
            "mainnet" | "mainnet-beta" => Self::solana_rpc_url_default(),
            "devnet" => "https://api.devnet.solana.com".to_string(),
            "testnet" => "https://api.testnet.solana.com".to_string(),
            "localhost" | "local" => "http://127.0.0.1:8899".to_string(),
            other => {
                // If a URL is provided directly, accept it.
                if other.starts_with("http://") || other.starts_with("https://") {
                    other.to_string()
                } else {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("Unsupported Solana network (use mainnet|devnet|testnet|localhost or a full RPC URL)"),
                        data: Some(json!({"network": other})),
                    });
                }
            }
        };

        Ok(url)
    }

    fn solana_rpc(
        network: Option<&str>,
    ) -> Result<solana_client::nonblocking::rpc_client::RpcClient, ErrorData> {
        let url = Self::solana_rpc_url_for_network(network)?;
        Ok(solana_client::nonblocking::rpc_client::RpcClient::new(url))
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

    fn solana_create_pending_confirmation(
        network: Option<&str>,
        tx_base64: &str,
        source: &str,
        summary: Option<Value>,
    ) -> Result<Value, ErrorData> {
        let rpc_url = Self::solana_rpc_url_for_network(network)?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(tx_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {}", e)),
                data: None,
            })?;

        let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

        let created = crate::utils::solana_confirm_store::now_ms();
        let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
        let expires = created + ttl;

        let id_seed = format!("{}:{}", created, hash);
        let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
        let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

        crate::utils::solana_confirm_store::insert_pending(
            &confirmation_id,
            tx_base64.trim(),
            created,
            expires,
            &hash,
            source,
            summary,
        )?;

        // Mainnet safety: require confirm_token.
        let token = if Self::solana_is_mainnet_network(network) {
            Some(crate::utils::solana_confirm_store::make_confirm_token(
                &confirmation_id,
                &hash,
            ))
        } else {
            None
        };

        Ok(json!({
            "ok": true,
            "status": "pending",
            "rpc_url": rpc_url,
            "network": network.unwrap_or("mainnet").to_string(),
            "pending_confirmation_id": confirmation_id,
            "tx_summary_hash": hash,
            "confirm_token": token,
            "expires_in_ms": ttl
        }))
    }

    #[tool(description = "Solana: confirm and broadcast a pending transaction created by W3RT (mainnet requires confirm_token)")]
    async fn solana_confirm_transaction(
        &self,
        Parameters(request): Parameters<SolanaConfirmTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // Load pending confirmation details
        let pending = crate::utils::solana_confirm_store::get_pending(&request.id)?;

        let network = request
            .network
            .clone()
            .or_else(|| pending.summary.as_ref().and_then(|v| v.get("network")).and_then(Value::as_str).map(|s| s.to_string()))
            .unwrap_or("mainnet".to_string());

        // Validate hash matches
        if request.hash.trim() != pending.tx_summary_hash.as_str() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("hash mismatch for pending confirmation"),
                data: Some(json!({"id": request.id, "provided": request.hash, "expected": pending.tx_summary_hash})),
            });
        }

        // Mainnet safety: require confirm_token.
        if Self::solana_is_mainnet_network(Some(&network)) {
            let expected = crate::utils::solana_confirm_store::make_confirm_token(&request.id, &request.hash);
            if request.confirm_token.as_deref() != Some(expected.as_str()) {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Mainnet confirmation requires confirm_token"),
                    data: Some(json!({
                        "expected_confirm_token": expected,
                        "how_to": format!("solana_confirm_transaction id:{} hash:{} confirm_token:{}", request.id, request.hash, expected)
                    })),
                });
            }
        }

        let tx_base64 = pending.tx_base64.clone();

        if tx_base64.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("pending confirmation missing transaction_base64"),
                data: Some(json!({"id": request.id})),
            });
        }

        let rpc = Self::solana_rpc(Some(&network))?;
        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(tx_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {}", e)),
                data: None,
            })?;

        let vtx: solana_sdk::transaction::VersionedTransaction =
            bincode::deserialize(&tx_bytes).map_err(|e| Self::sdk_error("solana_confirm_transaction:deserialize_tx", e))?;

        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;

        // Broadcast
        let sig = rpc
            .send_transaction(&vtx)
            .await
            .map_err(|e| Self::sdk_error("solana_confirm_transaction:send", e))?;

        // Wait for confirmation
        let _ = rpc
            .confirm_transaction_with_commitment(&sig, commitment)
            .await;

        // Delete pending confirmation
        let _ = crate::utils::solana_confirm_store::remove_pending(&request.id);

        let response = Self::pretty_json(&json!({
            "ok": true,
            "status": "sent",
            "network": network,
            "signature": sig.to_string(),
            "tx_summary_hash": request.hash,
            "note": "Broadcast submitted. Verify in your wallet/explorer."
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
