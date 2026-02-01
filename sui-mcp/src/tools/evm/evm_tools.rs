/// EVM tools (Base / EVM-compatible chains)
    ///
    /// NOTE: This server is currently named `sui-mcp`, but we're gradually expanding it into a
    /// multi-chain MCP server. These EVM tools are the first step.

    fn evm_default_chain_id() -> Result<u64, ErrorData> {
        if let Ok(v) = std::env::var("EVM_DEFAULT_CHAIN_ID") {
            return v.parse::<u64>().map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid EVM_DEFAULT_CHAIN_ID: {}", e)),
                data: None,
            });
        }
        Ok(84532) // Base Sepolia
    }

    fn evm_rpc_url(chain_id: u64) -> Result<String, ErrorData> {
        let key = format!("EVM_RPC_URL_{}", chain_id);
        if let Ok(url) = std::env::var(&key) {
            return Ok(url);
        }

        // Built-in defaults for common chains (can always be overridden via env).
        //
        // NOTE: Public RPCs vary in reliability and rate-limits. For production usage,
        // set EVM_RPC_URL_<chain_id> explicitly.
        match chain_id {
            // Ethereum
            1 => Ok("https://ethereum-rpc.publicnode.com".to_string()),
            // Sepolia
            11155111 => Ok("https://ethereum-sepolia-rpc.publicnode.com".to_string()),

            // Base
            8453 => Ok("https://mainnet.base.org".to_string()),
            84532 => Ok("https://sepolia.base.org".to_string()),

            // Arbitrum
            42161 => Ok("https://arbitrum-one-rpc.publicnode.com".to_string()),
            421614 => Ok("https://arbitrum-sepolia-rpc.publicnode.com".to_string()),

            // Optimism
            10 => Ok("https://optimism-rpc.publicnode.com".to_string()),
            11155420 => Ok("https://optimism-sepolia-rpc.publicnode.com".to_string()),

            // Polygon PoS
            137 => Ok("https://polygon-bor-rpc.publicnode.com".to_string()),
            80002 => Ok("https://polygon-amoy-bor-rpc.publicnode.com".to_string()),

            // Avalanche
            43114 => Ok("https://avalanche-c-chain-rpc.publicnode.com".to_string()),
            43113 => Ok("https://avalanche-fuji-c-chain-rpc.publicnode.com".to_string()),

            // Celo
            42220 => Ok("https://forno.celo.org".to_string()),
            44787 => Ok("https://alfajores-forno.celo-testnet.org".to_string()),

            // Kava
            2222 => Ok("https://evm.kava.io".to_string()),
            2221 => Ok("https://evm.testnet.kava.io".to_string()),

            // World Chain
            480 => Ok("https://worldchain-mainnet.g.alchemy.com/public".to_string()),
            4801 => Ok("https://worldchain-sepolia.g.alchemy.com/public".to_string()),

            // Monad
            143 => Ok("https://rpc.monad.xyz".to_string()),
            10143 => Ok("https://testnet-rpc.monad.xyz".to_string()),

            // Kaia
            8217 => Ok("https://public-en.node.kaia.io".to_string()),
            1001 => Ok("https://public-en-kairos.node.kaia.io".to_string()),

            // HyperEVM (Hyperliquid EVM Testnet)
            998 => Ok("https://api.hyperliquid-testnet.xyz/evm".to_string()),

            _ => Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Missing RPC URL for chain_id={}. Set {} env var.",
                    chain_id, key
                )),
                data: None,
            }),
        }
    }

    async fn evm_provider(
        &self,
        chain_id: u64,
    ) -> Result<ethers::providers::Provider<ethers::providers::Http>, ErrorData> {
        let url = Self::evm_rpc_url(chain_id)?;
        ethers::providers::Provider::<ethers::providers::Http>::try_from(url.as_str()).map_err(
            |e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to create EVM provider: {}", e)),
                data: None,
            },
        )
    }

    fn parse_evm_address(address: &str) -> Result<ethers::types::Address, ErrorData> {
        address
            .parse::<ethers::types::Address>()
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid EVM address: {}", e)),
                data: None,
            })
    }

    fn parse_evm_u256(label: &str, value: &str) -> Result<ethers::types::U256, ErrorData> {
        // Allow decimal strings or 0x-prefixed hex.
        if let Some(hex) = value.strip_prefix("0x") {
            return ethers::types::U256::from_str_radix(hex, 16).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid {} (hex): {}", label, e)),
                data: None,
            });
        }
        ethers::types::U256::from_dec_str(value).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid {} (decimal): {}", label, e)),
            data: None,
        })
    }

    fn parse_evm_h256(value: &str) -> Result<ethers::types::H256, ErrorData> {
        value.parse::<ethers::types::H256>().map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid tx hash: {}", e)),
            data: None,
        })
    }

    fn u256_from_u64(v: u64) -> ethers::types::U256 {
        ethers::types::U256::from(v)
    }

    fn encode_erc20_call(sig: &str, args: Vec<ethers::abi::Token>) -> ethers::types::Bytes {
        let selector = &ethers::utils::keccak256(sig)[0..4];
        let mut out = Vec::with_capacity(4 + 32 * args.len());
        out.extend_from_slice(selector);
        out.extend_from_slice(&ethers::abi::encode(&args));
        ethers::types::Bytes::from(out)
    }

    #[tool(description = "EVM: list pending intent confirmations (sqlite-backed)")]
    async fn evm_list_pending_confirmations(
        &self,
        Parameters(request): Parameters<EvmListPendingConfirmationsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::evm_confirm_store::connect()?;
        crate::utils::evm_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let now_ms = crate::utils::evm_confirm_store::now_ms() as i64;
        let limit = request.limit.unwrap_or(20).min(200) as i64;
        let include_tx_summary = request.include_tx_summary.unwrap_or(true);

        let status = request.status.as_deref().map(|s| s.trim().to_lowercase());
        if let Some(st) = status.as_deref() {
            let allowed = ["pending", "consumed", "sent", "failed", "skipped"];
            if !allowed.contains(&st) {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("status must be one of: pending|consumed|sent|failed|skipped"),
                    data: None,
                });
            }
        }

        let mut items: Vec<Value> = Vec::new();

        let mut sql = "SELECT id, chain_id, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, tx_hash, last_error, tx_json, raw_tx_prefix, signed_at_ms, second_confirm_token, second_confirmed, expected_spender, required_allowance_raw, expected_token, approve_confirmation_id, swap_confirmation_id FROM evm_pending_confirmations".to_string();
        let mut params: Vec<rusqlite::types::Value> = Vec::new();
        let mut where_clauses: Vec<String> = Vec::new();

        if let Some(chain_id) = request.chain_id {
            where_clauses.push(format!("chain_id = ?{}", params.len() + 1));
            params.push(rusqlite::types::Value::Integer(chain_id as i64));
        }
        if let Some(st) = status {
            where_clauses.push(format!("status = ?{}", params.len() + 1));
            params.push(rusqlite::types::Value::Text(st));
        }
        if !where_clauses.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&where_clauses.join(" AND "));
        }
        sql.push_str(" ORDER BY created_at_ms DESC");
        sql.push_str(&format!(" LIMIT ?{}", params.len() + 1));
        params.push(rusqlite::types::Value::Integer(limit));

        let mut stmt = conn.prepare(&sql).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to prepare select: {}", e)),
            data: None,
        })?;

        let rows = stmt
            .query_map(rusqlite::params_from_iter(params), |row| {
                let id: String = row.get(0)?;
                let chain_id: i64 = row.get(1)?;
                let created_at_ms: i64 = row.get(2)?;
                let updated_at_ms: i64 = row.get(3)?;
                let expires_at_ms: i64 = row.get(4)?;
                let tx_summary_hash: String = row.get(5)?;
                let status: String = row.get(6)?;
                let tx_hash: Option<String> = row.get(7)?;
                let last_error: Option<String> = row.get(8)?;
                let tx_json: String = row.get(9)?;
                let raw_tx_prefix: Option<String> = row.get(10)?;
                let signed_at_ms: Option<i64> = row.get(11)?;
                let second_confirm_token: Option<String> = row.get(12)?;
                let second_confirmed: Option<i64> = row.get(13)?;
                let expected_spender: Option<String> = row.get(14)?;
                let required_allowance_raw: Option<String> = row.get(15)?;
                let expected_token: Option<String> = row.get(16)?;
                let approve_confirmation_id: Option<String> = row.get(17)?;
                let swap_confirmation_id: Option<String> = row.get(18)?;
                Ok((
                    id,
                    chain_id,
                    created_at_ms,
                    updated_at_ms,
                    expires_at_ms,
                    tx_summary_hash,
                    status,
                    tx_hash,
                    last_error,
                    tx_json,
                    raw_tx_prefix,
                    signed_at_ms,
                    second_confirm_token,
                    second_confirmed,
                    expected_spender,
                    required_allowance_raw,
                    expected_token,
                    approve_confirmation_id,
                    swap_confirmation_id,
                ))
            })
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to query_map: {}", e)),
                data: None,
            })?;

        for r in rows.flatten() {
            let expires_in_ms = (r.4 - now_ms).max(0);
            let tx: Option<EvmTxRequest> = if include_tx_summary {
                serde_json::from_str::<EvmTxRequest>(&r.9).ok()
            } else {
                None
            };

            let calldata = tx
                .as_ref()
                .and_then(|t| t.data_hex.as_deref())
                .and_then(crate::utils::evm_selector::classify_calldata);

            let summary = tx
                .as_ref()
                .map(crate::utils::evm_confirm_store::tx_summary_for_response);

            items.push(json!({
                "id": r.0,
                "chain_id": r.1,
                "created_at_ms": r.2,
                "updated_at_ms": r.3,
                "expires_at_ms": r.4,
                "expires_in_ms": expires_in_ms,
                "status": r.6,
                "tx_hash": r.7,
                "last_error": r.8,
                "raw_tx_prefix": r.10,
                "signed_at_ms": r.11,
                "second_confirm_token": r.12,
                "second_confirmed": r.13.map(|v| v == 1).unwrap_or(false),
                "tx_summary_hash": r.5,
                "summary": summary,
                "tx_summary": summary,
                "tool_context": json!({
                    "expected_spender": r.14,
                    "required_allowance_raw": r.15,
                    "expected_token": r.16,
                    "approve_confirmation_id": r.17,
                    "swap_confirmation_id": r.18,
                }),
                "calldata": calldata
            }));
        }

        let response = Self::pretty_json(&json!({
            "db_path": crate::utils::evm_confirm_store::pending_db_path_from_cwd()?.to_string_lossy(),
            "count": items.len(),
            "items": items,
            "note": "Use evm_get_pending_confirmation for full record; use evm_retry_pending_confirmation to retry failed/consumed."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: get a pending intent confirmation by id (sqlite-backed)")]
    async fn evm_get_pending_confirmation(
        &self,
        Parameters(request): Parameters<EvmGetPendingConfirmationRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::evm_confirm_store::connect()?;
        crate::utils::evm_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let row = crate::utils::evm_confirm_store::get_row(&conn, request.id.trim())?;

        let response = Self::pretty_json(&json!({
            "db_path": crate::utils::evm_confirm_store::pending_db_path_from_cwd()?.to_string_lossy(),
            "item": row.map(|r| json!({
                "id": r.id,
                "chain_id": r.chain_id,
                "created_at_ms": r.created_at_ms,
                "updated_at_ms": r.updated_at_ms,
                "expires_at_ms": r.expires_at_ms,
                "expires_in_ms": (r.expires_at_ms as i128 - crate::utils::evm_confirm_store::now_ms() as i128).max(0),
                "status": r.status,
                "tx_hash": r.tx_hash,
                "last_error": r.last_error,
                "raw_tx_prefix": r.raw_tx_prefix,
                "signed_at_ms": r.signed_at_ms,
                "second_confirm_token": r.second_confirm_token,
                "second_confirmed": r.second_confirmed,
                "tx_summary_hash": r.tx_summary_hash,
                "tx": r.tx,
                "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&r.tx),
                "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&r.tx),
                "tool_context": json!({
                    "expected_spender": r.expected_spender,
                    "required_allowance_raw": r.required_allowance_raw,
                    "expected_token": r.expected_token,
                    "approve_confirmation_id": r.approve_confirmation_id,
                    "swap_confirmation_id": r.swap_confirmation_id,
                })
            }))
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: retry executing a pending/failed intent confirmation (sqlite-backed). Safe: requires matching tx_summary_hash; may request re-confirm if preflight changes tx.")]
    async fn evm_retry_pending_confirmation(
        &self,
        Parameters(request): Parameters<EvmRetryPendingConfirmationRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let id = request.id.trim();
        let provided_hash = request.tx_summary_hash.trim().to_lowercase();

        if !provided_hash.starts_with("0x") || provided_hash.len() != 66 {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("tx_summary_hash must be 0x + 64 hex chars"),
                data: None,
            });
        }

        let conn = crate::utils::evm_confirm_store::connect()?;
        crate::utils::evm_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let row = crate::utils::evm_confirm_store::get_row(&conn, id)?.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Pending confirmation not found (may have expired)."),
            data: None,
        })?;

        let tool_context = json!({
            "expected_spender": row.expected_spender,
            "required_allowance_raw": row.required_allowance_raw,
            "expected_token": row.expected_token,
            "approve_confirmation_id": row.approve_confirmation_id,
            "swap_confirmation_id": row.swap_confirmation_id,
        });

        if let Some(cid) = request.chain_id {
            if cid != row.chain_id {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "chain_id mismatch: request={} stored={}",
                        cid, row.chain_id
                    )),
                    data: None,
                });
            }
        }

        if row.status == "sent" {
            let response = Self::pretty_json(&json!({
                "status": "sent",
                "confirmation_id": row.id,
                "chain_id": row.chain_id,
                "tx_hash": row.tx_hash,
                "tx_summary_hash": row.tx_summary_hash,
                "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&row.tx),
                "tool_context": tool_context,
                "note": "Already broadcast"
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        if crate::utils::evm_confirm_store::now_ms() > row.expires_at_ms {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Pending confirmation expired; re-run dry-run."),
                data: Some(json!({
                    "confirmation_id": row.id,
                    "chain_id": row.chain_id,
                    "tx_summary_hash": row.tx_summary_hash,
                    "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&row.tx),
                    "tool_context": tool_context,
                    "status": row.status,
                })),
            });
        }

        if row.tx_summary_hash.to_lowercase() != provided_hash {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "tx_summary_hash mismatch: expected={} got={}",
                    row.tx_summary_hash, provided_hash
                )),
                data: Some(json!({
                    "confirmation_id": row.id,
                    "chain_id": row.chain_id,
                    "expected": row.tx_summary_hash,
                    "provided": provided_hash,
                    "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&row.tx),
                    "tool_context": tool_context,
                })),
            });
        }

        // Only allow retry when status is pending/failed/consumed.
        if !matches!(row.status.as_str(), "pending" | "failed" | "consumed") {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Unsupported status for retry: {}", row.status)),
                data: Some(json!({
                    "confirmation_id": row.id,
                    "chain_id": row.chain_id,
                    "status": row.status,
                    "tx_hash": row.tx_hash,
                    "last_error": row.last_error,
                    "tx_summary_hash": row.tx_summary_hash,
                    "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&row.tx),
                    "tool_context": tool_context,
                })),
            });
        }

        let mut tx = row.tx;

        // Confirm-time preflight.
        let preflight = self
            .evm_preflight(Parameters(EvmPreflightRequest { tx }))
            .await?;
        let preflight_json = Self::evm_extract_first_json(&preflight).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_preflight response during retry"),
            data: None,
        })?;
        tx = serde_json::from_value(preflight_json.get("tx").cloned().unwrap_or(Value::Null))
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode preflight tx during retry: {}", e)),
                data: None,
            })?;

        let new_hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx);
        if new_hash != provided_hash {
            let new_expires = crate::utils::evm_confirm_store::now_ms()
                + crate::utils::evm_confirm_store::default_ttl_ms();
            crate::utils::evm_confirm_store::update_pending(&conn, id, &tx, new_expires, &new_hash)?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": id,
                "chain_id": row.chain_id,
                "tx_summary_hash": new_hash,
                "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                "tool_context": tool_context,
                "note": "Tx changed during preflight (nonce/fees). Re-confirm/retry with new tx_summary_hash."
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        // Large-value double confirmation (requires token)
        if crate::utils::evm_confirm_store::is_large_value(&tx) {
            let token = crate::utils::evm_confirm_store::make_confirm_token(id, &provided_hash);
            let provided = request.confirm_token.clone();
            if provided.as_deref() != Some(&token) {
                let response = Self::pretty_json(&json!({
                    "status": "pending",
                    "confirmation_id": id,
                    "chain_id": row.chain_id,
                    "tx_summary_hash": provided_hash,
                    "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                    "tool_context": tool_context,
                    "note": "Second confirmation required for large-value tx",
                    "next": {
                        "how_to_retry": format!("Call evm_retry_pending_confirmation again with confirm_token='{}'", token)
                    }
                }))?;
                return Ok(CallToolResult::success(vec![Content::text(response)]));
            }
        }

        // Consume.
        crate::utils::evm_confirm_store::mark_consumed(&conn, id)?;

        // Sign.
        let signed = self
            .evm_sign_transaction_local(Parameters(EvmSignLocalRequest {
                tx: tx.clone(),
                allow_sender_mismatch: Some(false),
            }))
            .await?;
        let signed_json = Self::evm_extract_first_json(&signed).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse signed result"),
            data: None,
        })?;
        let raw_tx = signed_json
            .get("raw_tx")
            .and_then(Value::as_str)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Missing raw_tx"),
                data: None,
            })?
            .to_string();

        let _ = crate::utils::evm_confirm_store::mark_signed(&conn, id, &raw_tx);

        // Broadcast.
        let sent = self
            .evm_send_raw_transaction(Parameters(EvmSendRawTransactionRequest {
                chain_id: Some(row.chain_id),
                raw_tx,
            }))
            .await;

        match sent {
            Ok(ok) => {
                let mut tx_hash: Option<String> = None;
                let send_result = Self::evm_extract_first_json(&ok);
                if let Some(v) = send_result.as_ref() {
                    if let Some(h) = v.get("tx_hash").and_then(Value::as_str) {
                        tx_hash = Some(h.to_string());
                        let _ = crate::utils::evm_confirm_store::mark_sent(&conn, id, h);
                    }
                }

                let response = Self::pretty_json(&json!({
                    "status": "sent",
                    "confirmation_id": id,
                    "chain_id": row.chain_id,
                    "tx_hash": tx_hash,
                    "tx_summary_hash": provided_hash,
                    "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                    "tool_context": tool_context.clone(),
                    "send_result": send_result
                }))?;

                Ok(CallToolResult::success(vec![Content::text(response)]))
            }
            Err(e) => {
                let _ = crate::utils::evm_confirm_store::mark_failed(&conn, id, &e.message);
                Err(ErrorData {
                    code: e.code,
                    message: e.message,
                    data: Some(json!({
                        "confirmation_id": id,
                        "chain_id": row.chain_id,
                        "tx_summary_hash": provided_hash,
                        "summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                        "tool_context": tool_context,
                        "note": "Retry broadcast failed. You can inspect the pending record via evm_get_pending_confirmation or retry again."
                    })),
                })
            }
        }
    }

    #[tool(description = "EVM: cleanup pending confirmations (delete expired; optionally delete old failed entries)")]
    async fn evm_cleanup_pending_confirmations(
        &self,
        Parameters(request): Parameters<EvmCleanupPendingConfirmationsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::evm_confirm_store::connect()?;
        let now = crate::utils::evm_confirm_store::now_ms();

        // Always cleanup expired.
        crate::utils::evm_confirm_store::cleanup_expired(&conn, now)?;

        // Optional: delete failed older than threshold.
        let mut deleted_failed: i64 = 0;
        if let Some(age) = request.delete_failed_older_than_ms {
            let cutoff = (now as i128 - age as i128).max(0) as i64;
            if let Some(chain_id) = request.chain_id {
                deleted_failed = conn
                    .execute(
                        "DELETE FROM evm_pending_confirmations
                         WHERE status='failed' AND updated_at_ms < ?1 AND chain_id = ?2",
                        rusqlite::params![cutoff, chain_id as i64],
                    )
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to delete old failed: {}", e)),
                        data: None,
                    })? as i64;
            } else {
                deleted_failed = conn
                    .execute(
                        "DELETE FROM evm_pending_confirmations
                         WHERE status='failed' AND updated_at_ms < ?1",
                        rusqlite::params![cutoff],
                    )
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to delete old failed: {}", e)),
                        data: None,
                    })? as i64;
            }
        }

        // Report counts.
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM evm_pending_confirmations",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let response = Self::pretty_json(&json!({
            "db_path": crate::utils::evm_confirm_store::pending_db_path_from_cwd()?.to_string_lossy(),
            "remaining": count,
            "deleted_failed": deleted_failed
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn parse_decimal_to_u256(amount: &str, decimals: u8) -> Result<ethers::types::U256, ErrorData> {
        // Parse a decimal string like "1.23" into integer with `decimals` fractional digits.
        // No scientific notation.
        let s = amount.trim();
        if s.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("amount is required"),
                data: None,
            });
        }
        if let Some((whole, frac)) = s.split_once('.') {
            let whole = whole.trim();
            let frac = frac.trim();
            let mut frac_clean = frac.to_string();
            if frac_clean.len() > decimals as usize {
                // truncate extra precision (tolerant mode)
                frac_clean.truncate(decimals as usize);
            }
            while frac_clean.len() < decimals as usize {
                frac_clean.push('0');
            }
            let whole_u = if whole.is_empty() {
                ethers::types::U256::from(0)
            } else {
                ethers::types::U256::from_dec_str(whole).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid whole amount: {}", e)),
                    data: None,
                })?
            };
            let frac_u = if decimals == 0 {
                ethers::types::U256::from(0)
            } else {
                ethers::types::U256::from_dec_str(&frac_clean).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid fractional amount: {}", e)),
                    data: None,
                })?
            };

            let base = ethers::types::U256::from(10)
                .checked_pow(ethers::types::U256::from(decimals))
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Overflow computing decimals base"),
                    data: None,
                })?;

            Ok(whole_u * base + frac_u)
        } else {
            // integer string
            let whole_u = ethers::types::U256::from_dec_str(s).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid amount: {}", e)),
                data: None,
            })?;
            let base = ethers::types::U256::from(10)
                .checked_pow(ethers::types::U256::from(decimals))
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Overflow computing decimals base"),
                    data: None,
                })?;
            Ok(whole_u * base)
        }
    }

    async fn evm_read_erc20_decimals(
        &self,
        chain_id: u64,
        token: ethers::types::Address,
    ) -> Result<u8, ErrorData> {
        let provider = self.evm_provider(chain_id).await?;
        // decimals() selector = 0x313ce567
        let data = ethers::types::Bytes::from(hex::decode("313ce567").map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to build decimals() calldata: {}", e)),
            data: None,
        })?);
        let call = ethers::types::TransactionRequest {
            to: Some(ethers::types::NameOrAddress::Address(token)),
            data: Some(data),
            ..Default::default()
        };
        let typed: ethers::types::transaction::eip2718::TypedTransaction = call.into();

        let raw = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::call(
            &provider,
            &typed,
            None,
        )
        .await
        .map_err(|e| Self::sdk_error("evm_read_erc20_decimals:eth_call", e))?;

        // uint8 returns padded to 32 bytes.
        if raw.0.len() < 32 {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Invalid decimals() return"),
                data: None,
            });
        }
        Ok(raw.0[31])
    }

    // NOTE: resolve_evm_token_address is provided by utils/token_registry.rs.

    #[tool(description = "EVM: parse a human amount into wei (supports ETH via 18 decimals; ERC20 via decimals()). Accepts '1.5 usdc' style inputs.")]
    async fn evm_parse_amount(
        &self,
        Parameters(mut request): Parameters<EvmParseAmountRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // Allow shorthand in amount field:
        // - "1.5 usdc" / "0.1 eth"
        // - "1.5 token 0x..." / "1.5 contract 0x..." / "1.5 erc20 0x..."
        let mut amount_str = request.amount.trim().to_string();

        if request.symbol.is_none() && request.token_address.is_none() {
            let parts = amount_str
                .split_whitespace()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>();

            // Case 1: <num> <symbol>
            if parts.len() == 2 {
                let num = parts[0].clone();
                let sym = parts[1].clone();
                request.symbol = Some(sym);
                amount_str = num;
            }

            // Case 2: <num> (token|contract|erc20) <0xaddr>
            if parts.len() >= 3 {
                let maybe_num = parts[0].clone();
                let maybe_mid = parts[1].to_lowercase();
                let maybe_addr = parts[2].clone();
                if matches!(maybe_mid.as_str(), "token" | "contract" | "erc20")
                    && maybe_addr.starts_with("0x")
                {
                    // validate address
                    let _ = Self::parse_evm_address(&maybe_addr)?;
                    request.token_address = Some(maybe_addr);
                    amount_str = maybe_num;
                }
            }
        }

        let symbol = request.symbol.as_deref().map(|s| s.trim().to_lowercase());

        let token_address = if let Some(addr) = request.token_address.as_deref() {
            Some(Self::parse_evm_address(addr)?)
        } else if let Some(sym) = symbol.as_deref() {
            if sym == "eth" {
                None
            } else {
                Self::resolve_evm_token_address(sym, request.chain_id)
                    .and_then(|a| Self::parse_evm_address(&a).ok())
            }
        } else {
            None
        };

        // If this is not ETH and we couldn't resolve the token, fail with a helpful message.
        if token_address.is_none() {
            if let Some(sym) = symbol.as_deref() {
                if sym != "eth" {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Unknown token symbol '{}'. Provide token_address or set env EVM_{}_ADDRESS_{}",
                            sym,
                            sym.to_uppercase(),
                            request.chain_id
                        )),
                        data: None,
                    });
                }
            }
        }

        let decimals = if let Some(d) = request.decimals {
            d
        } else if token_address.is_none() {
            18
        } else {
            let addr = token_address.ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Missing token_address after resolution"),
                data: None,
            })?;
            self.evm_read_erc20_decimals(request.chain_id, addr).await?
        };

        let wei = Self::parse_decimal_to_u256(&amount_str, decimals)?;

        let response = Self::pretty_json(&json!({
            "chain_id": request.chain_id,
            "amount": request.amount,
            "parsed_amount": amount_str,
            "symbol": request.symbol,
            "token_address": token_address.map(|a| format!("0x{}", hex::encode(a.as_bytes()))),
            "decimals": decimals,
            "amount_wei": wei.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: parse a deadline input into unix seconds (supports relative durations like 20m/2h)")]
    async fn evm_parse_deadline(
        &self,
        Parameters(request): Parameters<EvmParseDeadlineRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let s = request.input.trim().to_lowercase();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_else(|_| std::time::Duration::from_secs(0))
            .as_secs();

        // If it parses as integer, treat as unix seconds unless relative=true.
        let is_plain_int = s.chars().all(|c| c.is_ascii_digit());
        let relative = request.relative.unwrap_or(!is_plain_int);

        let deadline = if !relative {
            s.parse::<u64>().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Invalid unix timestamp"),
                data: None,
            })?
        } else {
            let (num_str, unit) = s
                .chars()
                .partition::<String, _>(|c| c.is_ascii_digit());
            let n: u64 = num_str.parse().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Invalid duration number"),
                data: None,
            })?;

            let seconds = if unit == "s" || unit == "sec" || unit == "secs" {
                n
            } else if unit == "m" || unit == "min" || unit == "mins" {
                n * 60
            } else if unit == "h" || unit == "hr" || unit == "hrs" {
                n * 3600
            } else if unit == "d" || unit == "day" || unit == "days" {
                n * 86400
            } else {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Unsupported duration unit (use s|m|min|h|d)"),
                    data: None,
                });
            };
            now + seconds
        };

        let response = Self::pretty_json(&json!({
            "input": request.input,
            "now": now,
            "deadline": deadline,
            "relative": relative
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn parse_path_input(
        _chain_id: u64,
        input: &str,
    ) -> Result<Vec<String>, ErrorData> {
        let s = input.trim();
        if s.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("path input is required"),
                data: None,
            });
        }

        // Case 1: JSON array string
        if s.starts_with('[') {
            let v = serde_json::from_str::<Value>(s).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid JSON array: {}", e)),
                data: None,
            })?;
            let arr = v.as_array().ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Path JSON must be an array"),
                data: None,
            })?;

            let mut out = Vec::new();
            for item in arr {
                let token = item.as_str().ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Path items must be strings"),
                    data: None,
                })?;
                out.push(token.to_string());
            }
            return Ok(out);
        }

        // Case 2: Arrow syntax: A->B->C
        if s.contains("->") {
            return Ok(s
                .split("->")
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty())
                .collect());
        }

        // Case 3: Comma separated: A,B,C
        if s.contains(',') {
            return Ok(s
                .split(',')
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty())
                .collect());
        }

        // Single token
        Ok(vec![s.to_string()])
    }

    fn resolve_path_token(chain_id: u64, token: &str) -> Result<String, ErrorData> {
        let t = token.trim();
        if t.starts_with("0x") {
            let addr = Self::parse_evm_address(t)?;
            return Ok(format!("0x{}", hex::encode(addr.as_bytes())));
        }

        let sym = t.to_lowercase();
        if sym == "eth" {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Path token 'ETH' is ambiguous; use WETH address/symbol"),
                data: None,
            });
        }

        let addr = Self::resolve_evm_erc20_address(&sym, chain_id)
            .or_else(|| Self::resolve_evm_token_address(&sym, chain_id))
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Unknown path token '{}'. Provide 0x address or set env EVM_{}_ADDRESS_{}",
                    sym,
                    sym.to_uppercase(),
                    chain_id
                )),
                data: None,
            })?;

        let addr = Self::parse_evm_address(&addr)?;
        Ok(format!("0x{}", hex::encode(addr.as_bytes())))
    }

    #[tool(description = "EVM: parse a swap path into normalized address array. Supports 'WETH->USDC', '0xA,0xB', or JSON array.")]
    async fn evm_parse_path(
        &self,
        Parameters(request): Parameters<EvmParsePathRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let raw_items = Self::parse_path_input(request.chain_id, &request.input)?;
        if raw_items.len() < 2 {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Path must include at least 2 tokens"),
                data: None,
            });
        }

        let mut out: Vec<String> = Vec::new();
        for item in raw_items {
            out.push(Self::resolve_path_token(request.chain_id, &item)?);
        }

        let response = Self::pretty_json(&json!({
            "chain_id": request.chain_id,
            "input": request.input,
            "path": out
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn parse_slippage_bps(input: &str) -> Result<u64, ErrorData> {
        let s = input.trim().to_lowercase();
        if s.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("slippage is required"),
                data: None,
            });
        }

        if let Some(pct) = s.strip_suffix('%') {
            let pct = pct.trim();
            // allow decimals like 0.5%
            let v: f64 = pct.parse().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Invalid percent slippage"),
                data: None,
            })?;
            if v < 0.0 {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("slippage must be non-negative"),
                    data: None,
                });
            }
            // bps = percent * 100
            let bps = (v * 100.0).round() as i64;
            if bps < 0 {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("slippage must be non-negative"),
                    data: None,
                });
            }
            return Ok(bps as u64);
        }

        if let Some(bps) = s.strip_suffix("bps") {
            let bps = bps.trim();
            let v: u64 = bps.parse().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Invalid bps slippage"),
                data: None,
            })?;
            return Ok(v);
        }

        // fallback: treat as percent number (e.g. "1" == 1%)
        let v: f64 = s.parse().map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Invalid slippage"),
            data: None,
        })?;
        if v < 0.0 {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("slippage must be non-negative"),
                data: None,
            });
        }
        Ok((v * 100.0).round() as u64)
    }

    #[tool(description = "EVM: apply slippage to an expected amountOut (compute amountOutMin).")]
    async fn evm_apply_slippage(
        &self,
        Parameters(request): Parameters<EvmApplySlippageRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let expected = ethers::types::U256::from_dec_str(request.expected_amount_out_wei.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid expected_amount_out_wei: {}", e)),
                data: None,
            })?;
        let bps = Self::parse_slippage_bps(&request.slippage)?;
        if bps > 10_000 {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("slippage too large (>100%)"),
                data: None,
            });
        }

        let numerator = ethers::types::U256::from(10_000u64.saturating_sub(bps));
        let min_out = expected * numerator / ethers::types::U256::from(10_000u64);

        let response = Self::pretty_json(&json!({
            "expected_amount_out_wei": expected.to_string(),
            "slippage": request.slippage,
            "slippage_bps": bps,
            "amount_out_min_wei": min_out.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn evm_0x_base_url(chain_id: u64) -> Result<&'static str, ErrorData> {
        // 0x Swap API v1 endpoints (subdomain-per-chain).
        // If a chain is unsupported here, caller can still use EVM tools directly.
        let url = match chain_id {
            1 => "https://api.0x.org",
            8453 => "https://base.api.0x.org",
            10 => "https://optimism.api.0x.org",
            42161 => "https://arbitrum.api.0x.org",
            // testnets (best effort)
            11155111 => "https://api.0x.org",
            84532 => "https://base.api.0x.org",
            11155420 => "https://optimism.api.0x.org",
            421614 => "https://arbitrum.api.0x.org",
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "0x Swap API base url not configured for chain_id={}. Add mapping in evm_0x_base_url().",
                        chain_id
                    )),
                    data: None,
                })
            }
        };
        Ok(url)
    }

    fn normalize_token_for_0x(chain_id: u64, token: &str) -> Result<String, ErrorData> {
        let t = token.trim();
        if t.starts_with("0x") {
            let addr = Self::parse_evm_address(t)?;
            return Ok(format!("0x{}", hex::encode(addr.as_bytes())));
        }
        let sym = t.to_lowercase();
        if sym == "eth" {
            // 0x API accepts ETH as native
            return Ok("ETH".to_string());
        }
        let addr = Self::resolve_evm_token_address(&sym, chain_id)
            .or_else(|| Self::resolve_evm_erc20_address(&sym, chain_id))
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Unknown token '{}'. Provide 0x address or set env EVM_{}_ADDRESS_{}",
                    sym,
                    sym.to_uppercase(),
                    chain_id
                )),
                data: None,
            })?;
        let addr = Self::parse_evm_address(&addr)?;
        Ok(format!("0x{}", hex::encode(addr.as_bytes())))
    }

    async fn evm_0x_quote_internal(
        &self,
        chain_id: u64,
        taker: Option<String>,
        sell_token: String,
        buy_token: String,
        sell_amount: String,
        sell_amount_is_wei: bool,
        slippage: Option<String>,
    ) -> Result<Value, ErrorData> {
        let base = Self::evm_0x_base_url(chain_id)?;

        let sell_token = Self::normalize_token_for_0x(chain_id, &sell_token)?;
        let buy_token = Self::normalize_token_for_0x(chain_id, &buy_token)?;

        let original_human_sell_amount = sell_amount.clone();

        let mut sell_amount_wei = if sell_amount_is_wei {
            ethers::types::U256::from_dec_str(sell_amount.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid sell_amount wei: {}", e)),
                data: None,
            })?
        } else {
            // Use our own parser (handles decimals for ERC20).
            let parsed = self
                .evm_parse_amount(Parameters(EvmParseAmountRequest {
                    chain_id,
                    amount: sell_amount,
                    symbol: if sell_token == "ETH" {
                        Some("eth".to_string())
                    } else {
                        None
                    },
                    token_address: if sell_token == "ETH" {
                        None
                    } else {
                        Some(sell_token.clone())
                    },
                    decimals: None,
                }))
                .await?;
            let j = Self::evm_extract_first_json(&parsed).ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Failed to parse evm_parse_amount response"),
                data: None,
            })?;
            let w = j
                .get("amount_wei")
                .and_then(Value::as_str)
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Missing amount_wei"),
                    data: None,
                })?;
            ethers::types::U256::from_dec_str(w).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Invalid amount_wei from parser: {}", e)),
                data: None,
            })?
        };

        let slippage = slippage.unwrap_or_else(|| "1%".to_string());
        let slippage_fraction: f64 = if let Some(p) = slippage.trim().strip_suffix('%') {
            let v: f64 = p.trim().parse().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Invalid slippage percent"),
                data: None,
            })?;
            (v / 100.0).max(0.0)
        } else {
            // treat as percent number
            let v: f64 = slippage.trim().parse().map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Invalid slippage"),
                data: None,
            })?;
            (v / 100.0).max(0.0)
        };

        // Normalize takerAddress once (so helpers don't need to call Self::parse_evm_address).
        let taker_param = if let Some(t) = taker.as_deref() {
            let taker_addr = Self::parse_evm_address(t)?;
            Some(format!("0x{}", hex::encode(taker_addr.as_bytes())))
        } else {
            None
        };

        let client = reqwest::Client::new();

        async fn fetch_0x_quote(
            client: &reqwest::Client,
            base: &str,
            sell_token: &str,
            buy_token: &str,
            taker_param: &Option<String>,
            slippage_fraction: f64,
            sell_amount_wei: ethers::types::U256,
        ) -> Result<Value, ErrorData> {
            let mut url = format!("{}/swap/v1/quote", base);

            let mut query: Vec<(String, String)> = vec![
                ("sellToken".to_string(), sell_token.to_string()),
                ("buyToken".to_string(), buy_token.to_string()),
                ("sellAmount".to_string(), sell_amount_wei.to_string()),
                (
                    "slippagePercentage".to_string(),
                    format!("{}", slippage_fraction),
                ),
            ];
            if let Some(t) = taker_param.as_deref() {
                query.push(("takerAddress".to_string(), t.to_string()));
            }

            let qs = query
                .into_iter()
                .map(|(k, v)| {
                    format!(
                        "{}={}",
                        urlencoding::encode(&k),
                        urlencoding::encode(&v)
                    )
                })
                .collect::<Vec<_>>()
                .join("&");
            url.push('?');
            url.push_str(&qs);

            let resp = client.get(url).send().await.map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("0x quote request failed: {}", e)),
                data: None,
            })?;

            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            if !status.is_success() {
                return Err(ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("0x quote http {}: {}", status, text)),
                    data: None,
                });
            }

            serde_json::from_str::<Value>(&text).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Invalid 0x quote JSON: {}", e)),
                data: None,
            })
        }

        let mut v = fetch_0x_quote(
            &client,
            base,
            &sell_token,
            &buy_token,
            &taker_param,
            slippage_fraction,
            sell_amount_wei,
        )
        .await?;

        // Second-pass verification: if 0x returns sellTokenAddress, recompute sellAmount using that exact token decimals.
        // If our computed sellAmount differs, re-quote with the corrected amount.
        if !sell_amount_is_wei && sell_token != "ETH" {
            if let Some(token_addr) = v.get("sellTokenAddress").and_then(Value::as_str) {
                if let Ok(token) = Self::parse_evm_address(token_addr) {
                    let decimals = self.evm_read_erc20_decimals(chain_id, token).await.ok();
                    if let Some(decimals) = decimals {
                        // Parse the human sell amount again using the token returned by 0x.
                        let parsed = self
                            .evm_parse_amount(Parameters(EvmParseAmountRequest {
                                chain_id,
                                amount: original_human_sell_amount.clone(),
                                symbol: None,
                                token_address: Some(format!("0x{}", hex::encode(token.as_bytes()))),
                                decimals: Some(decimals),
                            }))
                            .await?;
                        let j = Self::evm_extract_first_json(&parsed).ok_or_else(|| ErrorData {
                            code: ErrorCode(-32603),
                            message: Cow::from("Failed to parse evm_parse_amount response"),
                            data: None,
                        })?;
                        let w = j
                            .get("amount_wei")
                            .and_then(Value::as_str)
                            .ok_or_else(|| ErrorData {
                                code: ErrorCode(-32603),
                                message: Cow::from("Missing amount_wei"),
                                data: None,
                            })?;
                        let corrected = ethers::types::U256::from_dec_str(w).map_err(|e| ErrorData {
                            code: ErrorCode(-32603),
                            message: Cow::from(format!("Invalid amount_wei from parser: {}", e)),
                            data: None,
                        })?;

                        if corrected != sell_amount_wei {
                            sell_amount_wei = corrected;
                            v = fetch_0x_quote(
                                &client,
                                base,
                                &sell_token,
                                &buy_token,
                                &taker_param,
                                slippage_fraction,
                                sell_amount_wei,
                            )
                            .await?;
                            if let Value::Object(ref mut map) = v {
                                map.insert(
                                    "web3mcp".to_string(),
                                    json!({
                                        "requoted": true,
                                        "sell_amount_requested": sell_amount_wei.to_string(),
                                        "note": "Re-quoted using sellTokenAddress decimals returned by 0x"
                                    }),
                                );
                            }
                        } else if let Value::Object(ref mut map) = v {
                            map.insert(
                                "web3mcp".to_string(),
                                json!({
                                    "requoted": false,
                                    "sell_amount_requested": sell_amount_wei.to_string()
                                }),
                            );
                        }
                    }
                }
            }
        }

        Ok(v)
    }

    #[tool(description = "EVM: 0x Swap API quote (returns to/data/value + amounts + allowanceTarget)")]
    async fn evm_0x_quote(
        &self,
        Parameters(request): Parameters<Evm0xQuoteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let v = self
            .evm_0x_quote_internal(
                request.chain_id,
                request.taker_address.clone(),
                request.sell_token.clone(),
                request.buy_token.clone(),
                request.sell_amount.clone(),
                request.sell_amount_is_wei.unwrap_or(false),
                request.slippage.clone(),
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "chain_id": request.chain_id,
            "quote": v
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: build a swap tx using 0x Swap API (returns EvmTxRequest; safe to preflight/sign/broadcast)")]
    async fn evm_0x_build_swap_tx(
        &self,
        Parameters(request): Parameters<Evm0xBuildSwapTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_evm_address(&request.sender)?;

        let quote = self
            .evm_0x_quote_internal(
                request.chain_id,
                Some(request.sender.clone()),
                request.sell_token.clone(),
                request.buy_token.clone(),
                request.sell_amount.clone(),
                request.sell_amount_is_wei.unwrap_or(false),
                request.slippage.clone(),
            )
            .await?;

        let to = quote
            .get("to")
            .and_then(Value::as_str)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("0x quote missing 'to'"),
                data: None,
            })?;
        let data = quote
            .get("data")
            .and_then(Value::as_str)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("0x quote missing 'data'"),
                data: None,
            })?;
        let value = quote
            .get("value")
            .and_then(Value::as_str)
            .unwrap_or("0");

        let tx = EvmTxRequest {
            chain_id: request.chain_id,
            from: format!("0x{}", hex::encode(sender.as_bytes())),
            to: to.to_string(),
            value_wei: value.to_string(),
            data_hex: Some(data.to_string()),
            nonce: None,
            gas_limit: None,
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
        };

        // Best-effort suggested approval for ERC20 sells.
        let allowance_target = quote.get("allowanceTarget").and_then(Value::as_str).map(|s| s.to_string());
        let sell_token_address = quote.get("sellTokenAddress").and_then(Value::as_str).map(|s| s.to_string());

        let suggested_approve = if let (Some(target), Some(token_addr)) =
            (allowance_target.clone(), sell_token_address.clone())
        {
            // If sell token is not ETH (0x uses ETH for native), then sellTokenAddress should exist.
            let amount_raw = if request.exact_approve.unwrap_or(false) {
                // Prefer 0x quote sellAmount (already base units)
                quote
                    .get("sellAmount")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| ethers::types::U256::MAX.to_string())
            } else {
                ethers::types::U256::MAX.to_string()
            };

            let built = self
                .evm_build_erc20_approve_tx(Parameters(EvmBuildErc20ApproveTxRequest {
                    sender: request.sender.clone(),
                    token: token_addr,
                    spender: target,
                    amount_raw,
                    chain_id: request.chain_id,
                    gas_limit: None,
                }))
                .await;

            match built {
                Ok(ok) => Self::evm_extract_first_json(&ok).and_then(|j| j.get("tx").cloned()),
                Err(_) => None,
            }
        } else {
            None
        };

        let response = Self::pretty_json(&json!({
            "chain_id": request.chain_id,
            "sender": request.sender,
            "tx": tx,
            "quote": quote,
            "allowance_target": allowance_target,
            "sell_token_address": sell_token_address,
            "suggested_approve_tx": suggested_approve,
            "note": "Run evm_preflight -> evm_sign_transaction_local -> evm_send_raw_transaction (or use intent confirm flow). If selling ERC20, you may need to approve allowance_target first."
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: compute event topic0 (keccak256(signature))")]
    async fn evm_event_topic0(
        &self,
        Parameters(request): Parameters<EvmEventTopic0Request>,
    ) -> Result<CallToolResult, ErrorData> {
        let sig = request.signature.trim();
        if !sig.contains('(') || !sig.contains(')') {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "Invalid event signature. Expected something like Transfer(address,address,uint256)",
                ),
                data: None,
            });
        }

        let hash = ethers::utils::keccak256(sig);
        let topic0 = format!("0x{}", hex::encode(hash));

        let response = Self::pretty_json(&json!({
            "signature": sig,
            "topic0": topic0
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn tx_request_to_evm_tx(tx: &ethers::types::TransactionRequest, chain_id: u64) -> EvmTxRequest {
        let from = tx
            .from
            .as_ref()
            .map(|a| format!("0x{}", hex::encode(a.as_bytes())))
            .unwrap_or_default();
        let to = match &tx.to {
            Some(ethers::types::NameOrAddress::Address(a)) => {
                format!("0x{}", hex::encode(a.as_bytes()))
            }
            Some(_) => "".to_string(),
            None => "".to_string(),
        };
        let value = tx.value.unwrap_or_else(|| ethers::types::U256::from(0));
        let data_hex = tx.data.as_ref().map(|b| format!("0x{}", hex::encode(b.as_ref())));

        // TransactionRequest does not include EIP-1559 fields; those are filled during evm_preflight.
        EvmTxRequest {
            chain_id,
            from,
            to,
            value_wei: value.to_string(),
            data_hex,
            nonce: tx.nonce.as_ref().map(|n| n.as_u64()),
            gas_limit: tx.gas.as_ref().map(|g| g.as_u64()),
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
        }
    }

    #[tool(description = "EVM: get gas price / EIP-1559 fee suggestions")]
    async fn evm_get_gas_price(
        &self,
        Parameters(request): Parameters<EvmGetGasPriceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let gas_price = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_gas_price(&provider)
            .await
            .map_err(|e| Self::sdk_error("evm_get_gas_price:get_gas_price", e))?;

        let (max_fee_per_gas, max_priority_fee_per_gas, eip1559_ok) =
            match <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::estimate_eip1559_fees(&provider, None)
                .await
            {
                Ok((max_fee, max_prio)) => (Some(max_fee), Some(max_prio), true),
                Err(_) => (None, None, false),
            };

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "gas_price_wei": gas_price.to_string(),
            "eip1559": {
                "supported": eip1559_ok,
                "max_fee_per_gas_wei": max_fee_per_gas.map(|v| v.to_string()),
                "max_priority_fee_per_gas_wei": max_priority_fee_per_gas.map(|v| v.to_string())
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: get balance (native ETH by default; ERC20 if token_address is provided)")]
    async fn evm_get_balance(
        &self,
        Parameters(request): Parameters<EvmGetBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;
        let address = Self::parse_evm_address(&request.address)?;

        let balance = if let Some(token_address) = request.token_address.as_deref() {
            // ERC20 balanceOf(address)
            let token = Self::parse_evm_address(token_address)?;
            let selector = &ethers::utils::keccak256("balanceOf(address)")[0..4];
            let data = {
                let mut out = Vec::with_capacity(4 + 32);
                out.extend_from_slice(selector);
                out.extend_from_slice(&ethers::abi::encode(&[ethers::abi::Token::Address(address)]));
                ethers::types::Bytes::from(out)
            };

            let call = ethers::types::TransactionRequest {
                to: Some(ethers::types::NameOrAddress::Address(token)),
                data: Some(data),
                ..Default::default()
            };
            let typed: ethers::types::transaction::eip2718::TypedTransaction = call.clone().into();

            let raw = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::call(
                &provider,
                &typed,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_get_balance:eth_call", e))?;

            // Decode as U256 (32 bytes)
            let bytes: Vec<u8> = raw.to_vec();
            if bytes.len() < 32 {
                return Err(ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("ERC20 balanceOf returned unexpected length"),
                    data: None,
                });
            }
            ethers::types::U256::from_big_endian(&bytes[bytes.len() - 32..])
        } else {
            <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_balance(
                &provider,
                address,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_get_balance:get_balance", e))?
        };

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "address": request.address,
            "token_address": request.token_address,
            "balance_wei": balance.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: get transaction receipt (includes logs)")]
    async fn evm_get_transaction_receipt(
        &self,
        Parameters(request): Parameters<EvmGetTransactionReceiptRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;
        let tx_hash = Self::parse_evm_h256(&request.tx_hash)?;

        let receipt = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction_receipt(&provider, tx_hash)
            .await
            .map_err(|e| Self::sdk_error("evm_get_transaction_receipt:get_transaction_receipt", e))?;

        let limit = request.decoded_logs_limit.unwrap_or(50);
        let (decoded_logs, decoded_logs_truncated, decoded_logs_total) = if let Some(receipt) = &receipt {
            Self::decode_receipt_logs(
                chain_id,
                receipt.logs.iter().collect::<Vec<_>>(),
                limit,
                request.only_addresses.clone(),
                request.only_topics0.clone(),
            )?
        } else {
            (Vec::new(), false, 0)
        };

        let include_receipt = request.include_receipt.unwrap_or(false);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": request.tx_hash,
            "decoded_logs": decoded_logs,
            "decoded_logs_truncated": decoded_logs_truncated,
            "decoded_logs_total": decoded_logs_total,
            "receipt": if include_receipt { receipt } else { None }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: decode a transaction receipt JSON using the local ABI registry")]
    async fn evm_decode_transaction_receipt(
        &self,
        Parameters(request): Parameters<EvmDecodeTransactionReceiptRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request.chain_id;

        let receipt = request
            .receipt_json
            .get("receipt")
            .cloned()
            .unwrap_or_else(|| request.receipt_json.clone());

        let receipt: ethers::types::TransactionReceipt = serde_json::from_value(receipt).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid receipt_json: {}", e)),
            data: None,
        })?;

        let limit = request.decoded_logs_limit.unwrap_or(50);
        let (decoded_logs, decoded_logs_truncated, decoded_logs_total) = Self::decode_receipt_logs(
            chain_id,
            receipt.logs.iter().collect::<Vec<_>>(),
            limit,
            request.only_addresses.clone(),
            request.only_topics0.clone(),
        )?;

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": format!("0x{}", hex::encode(receipt.transaction_hash.as_bytes())),
            "decoded_logs": decoded_logs,
            "decoded_logs_truncated": decoded_logs_truncated,
            "decoded_logs_total": decoded_logs_total
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ERC20: balanceOf(token, owner)")]
    async fn evm_erc20_balance_of(
        &self,
        Parameters(request): Parameters<EvmErc20BalanceOfRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let token = Self::parse_evm_address(&request.token)?;
        let owner = Self::parse_evm_address(&request.owner)?;

        let data = Self::encode_erc20_call(
            "balanceOf(address)",
            vec![ethers::abi::Token::Address(owner)],
        );

        let call = ethers::types::TransactionRequest {
            to: Some(ethers::types::NameOrAddress::Address(token)),
            data: Some(data),
            ..Default::default()
        };
        let typed: ethers::types::transaction::eip2718::TypedTransaction = call.clone().into();

        let raw = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::call(
            &provider,
            &typed,
            None,
        )
        .await
        .map_err(|e| Self::sdk_error("evm_erc20_balance_of:eth_call", e))?;

        let bytes: Vec<u8> = raw.to_vec();
        if bytes.len() < 32 {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("ERC20 balanceOf returned unexpected length"),
                data: None,
            });
        }
        let balance = ethers::types::U256::from_big_endian(&bytes[bytes.len() - 32..]);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "token": request.token,
            "owner": request.owner,
            "balance_raw": balance.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ERC20: allowance(token, owner, spender)")]
    async fn evm_erc20_allowance(
        &self,
        Parameters(request): Parameters<EvmErc20AllowanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let token = Self::parse_evm_address(&request.token)?;
        let owner = Self::parse_evm_address(&request.owner)?;
        let spender = Self::parse_evm_address(&request.spender)?;

        let data = Self::encode_erc20_call(
            "allowance(address,address)",
            vec![
                ethers::abi::Token::Address(owner),
                ethers::abi::Token::Address(spender),
            ],
        );

        let call = ethers::types::TransactionRequest {
            to: Some(ethers::types::NameOrAddress::Address(token)),
            data: Some(data),
            ..Default::default()
        };
        let typed: ethers::types::transaction::eip2718::TypedTransaction = call.clone().into();

        let raw = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::call(
            &provider,
            &typed,
            None,
        )
        .await
        .map_err(|e| Self::sdk_error("evm_erc20_allowance:eth_call", e))?;

        let bytes: Vec<u8> = raw.to_vec();
        if bytes.len() < 32 {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("ERC20 allowance returned unexpected length"),
                data: None,
            });
        }
        let allowance = ethers::types::U256::from_big_endian(&bytes[bytes.len() - 32..]);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "token": request.token,
            "owner": request.owner,
            "spender": request.spender,
            "allowance_raw": allowance.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ERC20: one-step transfer(token, to, amount_raw) with local signing")]
    async fn evm_execute_erc20_transfer(
        &self,
        Parameters(request): Parameters<EvmExecuteErc20TransferRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let from = Self::parse_evm_address(&request.sender)?;
        let token = Self::parse_evm_address(&request.token)?;
        let to = Self::parse_evm_address(&request.recipient)?;
        let amount = Self::parse_evm_u256("amount_raw", &request.amount_raw)?;

        let data = Self::encode_erc20_call(
            "transfer(address,uint256)",
            vec![
                ethers::abi::Token::Address(to),
                ethers::abi::Token::Uint(amount),
            ],
        );

        let tx_request = ethers::types::TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(token)),
            value: Some(ethers::types::U256::from(0)),
            data: Some(data),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        self.evm_execute_tx_request(
            chain_id,
            tx_request,
            request.allow_sender_mismatch.unwrap_or(false),
        )
        .await
    }

    #[tool(description = "EVM ERC20: build approve(token, spender, amount_raw) tx (no signing/broadcast)")]
    async fn evm_build_erc20_approve_tx(
        &self,
        Parameters(request): Parameters<EvmBuildErc20ApproveTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let from = Self::parse_evm_address(&request.sender)?;
        let token = Self::parse_evm_address(&request.token)?;
        let spender = Self::parse_evm_address(&request.spender)?;
        let amount = Self::parse_evm_u256("amount_raw", &request.amount_raw)?;

        let data = Self::encode_erc20_call(
            "approve(address,uint256)",
            vec![
                ethers::abi::Token::Address(spender),
                ethers::abi::Token::Uint(amount),
            ],
        );

        let tx_request = ethers::types::TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(token)),
            value: Some(ethers::types::U256::from(0)),
            data: Some(data),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        let tx = Self::tx_request_to_evm_tx(&tx_request, request.chain_id);

        let response = Self::pretty_json(&json!({
            "tx": tx,
            "note": "Run evm_preflight -> evm_sign_transaction_local -> evm_send_raw_transaction"
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ERC20: one-step approve(token, spender, amount_raw) with local signing")]
    async fn evm_execute_erc20_approve(
        &self,
        Parameters(request): Parameters<EvmExecuteErc20ApproveRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let from = Self::parse_evm_address(&request.sender)?;
        let token = Self::parse_evm_address(&request.token)?;
        let spender = Self::parse_evm_address(&request.spender)?;
        let amount = Self::parse_evm_u256("amount_raw", &request.amount_raw)?;

        let data = Self::encode_erc20_call(
            "approve(address,uint256)",
            vec![
                ethers::abi::Token::Address(spender),
                ethers::abi::Token::Uint(amount),
            ],
        );

        let tx_request = ethers::types::TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(token)),
            value: Some(ethers::types::U256::from(0)),
            data: Some(data),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        self.evm_execute_tx_request(
            chain_id,
            tx_request,
            request.allow_sender_mismatch.unwrap_or(false),
        )
        .await
    }

    fn evm_abi_registry_dir() -> std::path::PathBuf {
        if let Ok(dir) = std::env::var("EVM_ABI_REGISTRY_DIR") {
            return std::path::PathBuf::from(dir);
        }
        if let Ok(home) = std::env::var("HOME") {
            return std::path::PathBuf::from(home)
                .join(".web3mcp")
                .join("abi_registry")
                .join("evm");
        }
        std::path::PathBuf::from("./abi_registry/evm")
    }

    fn normalize_evm_address(address: &str) -> Result<String, ErrorData> {
        let a = Self::parse_evm_address(address)?;
        Ok(format!("0x{}", hex::encode(a.as_bytes())))
    }

    fn evm_abi_path(chain_id: u64, address: &str) -> Result<std::path::PathBuf, ErrorData> {
        let addr = Self::normalize_evm_address(address)?;
        Ok(Self::evm_abi_registry_dir()
            .join(chain_id.to_string())
            .join(format!("{}.json", addr)))
    }

    fn evm_load_contract_abi(
        chain_id: u64,
        address: &str,
    ) -> Result<Option<ethers::abi::Abi>, ErrorData> {
        let path = Self::evm_abi_path(chain_id, address)?;
        if !path.exists() {
            return Ok(None);
        }
        let bytes = std::fs::read(&path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read ABI entry: {}", e)),
            data: None,
        })?;
        let v: Value = serde_json::from_slice(&bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to parse ABI entry JSON: {}", e)),
            data: None,
        })?;

        let abi_val = v.get("abi").cloned().unwrap_or(Value::Null);
        if abi_val.is_null() {
            return Ok(None);
        }

        // The registry is expected to store a standard ABI JSON array.
        // If someone stored nested arrays, we treat it as unsupported.
        if let Value::Array(items) = abi_val {
            let looks_like_abi = items
                .iter()
                .any(|it| it.get("type").and_then(Value::as_str).is_some());
            if looks_like_abi {
                let abi: ethers::abi::Abi = serde_json::from_value(Value::Array(items)).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to parse ABI: {}", e)),
                    data: None,
                })?;
                return Ok(Some(abi));
            }
        }

        Ok(None)
    }

    fn decode_receipt_logs(
        chain_id: u64,
        logs: Vec<&ethers::types::Log>,
        limit: usize,
        only_addresses: Option<Vec<String>>,
        only_topics0: Option<Vec<String>>,
    ) -> Result<(Vec<Value>, bool, usize), ErrorData> {
        let normalized_allowlist = only_addresses.map(|addrs| {
            addrs
                .into_iter()
                .filter_map(|a| Self::normalize_evm_address(&a).ok())
                .collect::<std::collections::BTreeSet<_>>()
        });

        let normalized_topics0 = only_topics0.map(|topics| {
            topics
                .into_iter()
                .filter_map(|t| {
                    let t = t.trim();
                    let t = t.strip_prefix("0x").unwrap_or(t);
                    if t.len() != 64 {
                        return None;
                    }
                    Some(format!("0x{}", t.to_lowercase()))
                })
                .collect::<std::collections::BTreeSet<_>>()
        });

        let filtered = logs
            .into_iter()
            .filter(|log| {
                if let Some(allow) = &normalized_allowlist {
                    let addr = format!("0x{}", hex::encode(log.address.as_bytes()));
                    if !allow.contains(&addr) {
                        return false;
                    }
                }

                if let Some(allow) = &normalized_topics0 {
                    let topic0 = log
                        .topics
                        .get(0)
                        .map(|t| format!("0x{}", hex::encode(t.as_bytes())));
                    match topic0 {
                        Some(t0) => allow.contains(&t0.to_lowercase()),
                        None => false,
                    }
                } else {
                    true
                }
            })
            .collect::<Vec<_>>();

        let total = filtered.len();
        let mut out = Vec::new();

        for log in filtered.into_iter().take(limit) {
            let addr = format!("0x{}", hex::encode(log.address.as_bytes()));
            if let Ok(Some(abi)) = Self::evm_load_contract_abi(chain_id, &addr) {
                if let Some(decoded) = Self::evm_decode_log_with_abi(log, &abi) {
                    out.push(decoded);
                }
            }
        }

        let truncated = total > limit;
        Ok((out, truncated, total))
    }

    fn evm_decode_log_with_abi(
        log: &ethers::types::Log,
        abi: &ethers::abi::Abi,
    ) -> Option<Value> {
        // Try to decode by matching topic0 against known event signatures.
        let topic0 = log.topics.get(0).cloned()?;

        // ethers::abi::Abi::events() yields an iterator of all events (flattened).
        for event in abi.events() {
            let sig = event.signature();
            let sig_hash = ethers::utils::keccak256(sig);
            let sig_topic = ethers::types::H256::from_slice(&sig_hash);
            if sig_topic != topic0 {
                continue;
            }

            // Decode topics+data.
            let raw = ethers::abi::RawLog {
                topics: log.topics.clone(),
                data: log.data.to_vec(),
            };
            if let Ok(parsed) = event.parse_log(raw) {
                // Build a stable JSON representation.
                let params = parsed
                    .params
                    .into_iter()
                    .map(|p| {
                        let value = match p.value {
                            ethers::abi::Token::Address(a) => {
                                json!(format!("0x{}", hex::encode(a.as_bytes())))
                            }
                            ethers::abi::Token::Uint(u) => json!(u.to_string()),
                            ethers::abi::Token::Int(i) => json!(i.to_string()),
                            ethers::abi::Token::Bool(b) => json!(b),
                            ethers::abi::Token::String(s) => json!(s),
                            ethers::abi::Token::Bytes(b) => json!(format!("0x{}", hex::encode(b))),
                            ethers::abi::Token::FixedBytes(b) => {
                                json!(format!("0x{}", hex::encode(b)))
                            }
                            other => json!(format!("{:?}", other)),
                        };
                        json!({
                            "name": p.name,
                            "value": value
                        })
                    })
                    .collect::<Vec<_>>();

                let address = log.address;
                return Some(json!({
                    "event": event.name,
                    "signature": sig,
                    "address": format!("0x{}", hex::encode(address.as_bytes())),
                    "log_index": log.log_index.map(|v| v.as_u64()),
                    "transaction_hash": log
                        .transaction_hash
                        .map(|h| format!("0x{}", hex::encode(h.as_bytes()))),
                    "block_number": log.block_number.map(|v| v.as_u64()),
                    "topic0": log
                        .topics
                        .get(0)
                        .map(|t| format!("0x{}", hex::encode(t.as_bytes()))),
                    "data_hex": format!("0x{}", hex::encode(log.data.to_vec())),
                    "params": params
                }));
            }
        }

        None
    }

fn abi_entry_json(
        chain_id: u64,
        address: &str,
        name: Option<String>,
        abi_json: String,
    ) -> Result<Value, ErrorData> {
        // Validate ABI is valid JSON.
        let abi_val: Value = serde_json::from_str(&abi_json).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid abi_json: {}", e)),
            data: None,
        })?;

        Ok(json!({
            "chain_id": chain_id,
            "address": Self::normalize_evm_address(address)?,
            "name": name,
            "abi": abi_val
        }))
    }

    #[tool(description = "EVM ABI Registry: register a contract ABI under abi_registry/evm/<chain_id>/<address>.json")]
    async fn evm_register_contract(
        &self,
        Parameters(request): Parameters<EvmRegisterContractRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let path = Self::evm_abi_path(request.chain_id, &request.address)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to create registry dir: {}", e)),
                data: None,
            })?;
        }

        let entry = Self::abi_entry_json(
            request.chain_id,
            &request.address,
            request.name,
            request.abi_json,
        )?;

        let bytes = serde_json::to_vec_pretty(&entry).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize entry: {}", e)),
            data: None,
        })?;

        std::fs::write(&path, bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to write ABI entry: {}", e)),
            data: None,
        })?;

        let response = Self::pretty_json(&json!({
            "ok": true,
            "path": path.to_string_lossy(),
            "chain_id": request.chain_id,
            "address": Self::normalize_evm_address(&request.address)?
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ABI Registry: register a contract ABI from a local file path")]
    async fn evm_register_contract_from_path(
        &self,
        Parameters(request): Parameters<EvmRegisterContractFromPathRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let bytes = std::fs::read(&request.abi_path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read abi_path: {}", e)),
            data: None,
        })?;

        let v: Value = serde_json::from_slice(&bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid ABI JSON file: {}", e)),
            data: None,
        })?;

        // Accept either:
        // 1) Raw ABI array (standard), or
        // 2) Full registry entry JSON with { abi: [...] }
        let abi_json = if v.get("abi").is_some() {
            v.get("abi").cloned().unwrap_or(Value::Null)
        } else {
            v
        };

        let abi_json_string = serde_json::to_string(&abi_json).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize ABI JSON: {}", e)),
            data: None,
        })?;

        // Delegate to the canonical register tool to keep output consistent.
        self.evm_register_contract(Parameters(EvmRegisterContractRequest {
            chain_id: request.chain_id,
            address: request.address,
            name: request.name,
            abi_json: abi_json_string,
        }))
        .await
    }

    #[tool(description = "EVM ABI Registry: list registered contracts (optionally filter by chain_id)")]
    async fn evm_list_contracts(
        &self,
        Parameters(request): Parameters<EvmListContractsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let root = Self::evm_abi_registry_dir();
        let mut out: Vec<Value> = Vec::new();

        let chain_dirs: Vec<std::path::PathBuf> = if let Some(chain_id) = request.chain_id {
            vec![root.join(chain_id.to_string())]
        } else {
            match std::fs::read_dir(&root) {
                Ok(rd) => rd.filter_map(|e| e.ok()).map(|e| e.path()).collect(),
                Err(_) => vec![],
            }
        };

        for dir in chain_dirs {
            let chain_id = dir
                .file_name()
                .and_then(|s| s.to_str())
                .and_then(|s| s.parse::<u64>().ok());
            let Ok(rd) = std::fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let p = e.path();
                if p.extension().and_then(|s| s.to_str()) != Some("json") {
                    continue;
                }
                let Ok(bytes) = std::fs::read(&p) else { continue };
                let Ok(v) = serde_json::from_slice::<Value>(&bytes) else { continue };
                out.push(json!({
                    "chain_id": chain_id.or_else(|| v.get("chain_id").and_then(Value::as_u64)),
                    "address": v.get("address"),
                    "name": v.get("name"),
                    "path": p.to_string_lossy()
                }));
            }
        }

        let response = Self::pretty_json(&json!({
            "root": root.to_string_lossy(),
            "items": out
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn extract_hex_addresses(text: &str) -> Vec<String> {
        text.split_whitespace()
            .filter(|w| w.starts_with("0x") && w.len() >= 10)
            .map(|w| w.trim_matches(|c: char| c == ',' || c == ';' || c == ')' || c == '(' || c == '"').to_string())
            .collect()
    }

    fn extract_numbers(text: &str) -> Vec<String> {
        // Very simple: collect tokens that parse as decimal numbers (or 0x hex).
        let mut out = Vec::new();
        for raw in text.split_whitespace() {
            let w = raw.trim_matches(|c: char| c == ',' || c == ';' || c == ')' || c == '(' || c == '"');
            if w.is_empty() {
                continue;
            }
            if w.starts_with("0x") {
                // treat as a number-ish token as well
                out.push(w.to_string());
                continue;
            }
            // allow digits with dot
            if w.chars().all(|c| c.is_ascii_digit() || c == '.') {
                out.push(w.to_string());
            }
        }
        out
    }

    fn score_function(name: &str, signature: &str, text: &str, hint: Option<&str>) -> i64 {
        let t = text.to_lowercase();
        let n = name.to_lowercase();
        let s = signature.to_lowercase();
        let mut score = 0;

        if t.contains(&n) {
            score += 200;
        }
        if t.contains(&s) {
            score += 400;
        }
        if let Some(h) = hint {
            let h = h.to_lowercase();
            if n == h {
                score += 300;
            }
            if n.contains(&h) {
                score += 120;
            }
            if t.contains(&h) {
                score += 80;
            }
        }

        // Generic action keywords.
        for (kw, bonus) in [
            ("approve", 60),
            ("transfer", 60),
            ("swap", 60),
            ("deposit", 40),
            ("withdraw", 40),
            ("mint", 40),
            ("burn", 40),
            ("borrow", 40),
            ("repay", 40),
        ] {
            if t.contains(kw) && n.contains(kw) {
                score += bonus;
            }
        }

        score
    }

    fn infer_args_for_function(
        func: &ethers::abi::Function,
        text: &str,
    ) -> (Vec<Value>, Vec<Value>) {
        use ethers::abi::ParamType;

        let addrs = Self::extract_hex_addresses(text);
        let nums = Self::extract_numbers(text);
        let mut addr_i = 0usize;
        let mut num_i = 0usize;

        let mut filled: Vec<Value> = Vec::new();
        let mut missing: Vec<Value> = Vec::new();

        for input in func.inputs.iter() {
            match &input.kind {
                ParamType::Address => {
                    if addr_i < addrs.len() {
                        filled.push(Value::String(addrs[addr_i].clone()));
                        addr_i += 1;
                    } else {
                        filled.push(Value::String("<address>".to_string()));
                        missing.push(json!({"name": input.name, "type": "address"}));
                    }
                }
                ParamType::Uint(_) | ParamType::Int(_) => {
                    if num_i < nums.len() {
                        // For integers we keep as string to avoid JSON number limits.
                        filled.push(Value::String(nums[num_i].clone()));
                        num_i += 1;
                    } else {
                        filled.push(Value::String("<amount>".to_string()));
                        missing.push(json!({"name": input.name, "type": input.kind.to_string()}));
                    }
                }
                ParamType::Bool => {
                    // naive
                    if text.to_lowercase().contains("true") {
                        filled.push(Value::Bool(true));
                    } else if text.to_lowercase().contains("false") {
                        filled.push(Value::Bool(false));
                    } else {
                        filled.push(Value::Bool(false));
                        missing.push(json!({"name": input.name, "type": "bool"}));
                    }
                }
                _ => {
                    filled.push(Value::String("<value>".to_string()));
                    missing.push(json!({"name": input.name, "type": input.kind.to_string()}));
                }
            }
        }

        (filled, missing)
    }

    #[tool(description = "EVM ABI Registry: fuzzy search contracts by name/address/path (helps natural-language workflows)")]
    async fn evm_find_contracts(
        &self,
        Parameters(request): Parameters<EvmFindContractsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let root = Self::evm_abi_registry_dir();
        let query = request.query.trim().to_lowercase();
        let limit = request.limit.unwrap_or(10).min(50);

        if query.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("query is required"),
                data: None,
            });
        }

        let chain_dirs: Vec<std::path::PathBuf> = if let Some(chain_id) = request.chain_id {
            vec![root.join(chain_id.to_string())]
        } else {
            match std::fs::read_dir(&root) {
                Ok(rd) => rd.filter_map(|e| e.ok()).map(|e| e.path()).collect(),
                Err(_) => vec![],
            }
        };

        let mut scored: Vec<(i64, Value)> = Vec::new();

        for dir in chain_dirs {
            let chain_id = dir
                .file_name()
                .and_then(|s| s.to_str())
                .and_then(|s| s.parse::<u64>().ok());
            let Ok(rd) = std::fs::read_dir(&dir) else { continue };

            for e in rd.flatten() {
                let p = e.path();
                if p.extension().and_then(|s| s.to_str()) != Some("json") {
                    continue;
                }
                let path_str = p.to_string_lossy().to_string();
                let Ok(bytes) = std::fs::read(&p) else { continue };
                let Ok(v) = serde_json::from_slice::<Value>(&bytes) else { continue };

                let name = v.get("name").and_then(Value::as_str).unwrap_or("");
                let address = v.get("address").and_then(Value::as_str).unwrap_or("");

                let hay_name = name.to_lowercase();
                let hay_addr = address.to_lowercase();
                let hay_path = path_str.to_lowercase();

                let mut score: i64 = 0;
                if hay_addr == query {
                    score += 1000;
                }
                if hay_name.starts_with(&query) {
                    score += 300;
                }
                if hay_addr.starts_with(&query) {
                    score += 300;
                }
                if hay_name.contains(&query) {
                    score += 120;
                }
                if hay_addr.contains(&query) {
                    score += 120;
                }
                if hay_path.contains(&query) {
                    score += 60;
                }

                if score > 0 {
                    scored.push((
                        score,
                        json!({
                            "score": score,
                            "chain_id": chain_id.or_else(|| v.get("chain_id").and_then(Value::as_u64)),
                            "address": address,
                            "name": name,
                            "path": path_str
                        }),
                    ));
                }
            }
        }

        scored.sort_by(|a, b| b.0.cmp(&a.0));
        let items: Vec<Value> = scored.into_iter().take(limit).map(|(_, v)| v).collect();

        let response = Self::pretty_json(&json!({
            "root": root.to_string_lossy(),
            "query": request.query,
            "items": items
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ABI Registry: get a registered contract entry")]
    async fn evm_get_contract(
        &self,
        Parameters(request): Parameters<EvmGetContractRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let path = Self::evm_abi_path(request.chain_id, &request.address)?;
        let bytes = std::fs::read(&path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read contract entry: {}", e)),
            data: None,
        })?;
        let v: Value = serde_json::from_slice(&bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Invalid registry JSON: {}", e)),
            data: None,
        })?;
        let response = Self::pretty_json(&v)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ABI Registry: plan a contract call from natural language (no execution). Returns candidate functions + inferred args + missing fields.")]
    async fn evm_plan_contract_call(
        &self,
        Parameters(request): Parameters<EvmPlanContractCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let text = request.text.clone();
        let hint = request.function_hint.as_deref();
        let limit = request.limit.unwrap_or(5).min(20);

        // Resolve contract (B-mode default): do NOT auto-pick unless accept_best_match=true.
        let accept = request.accept_best_match.unwrap_or(false);
        let (address, entry, abi) = Self::resolve_contract_for_call(
            request.chain_id,
            request.address.clone(),
            request.contract_name.clone(),
            request.contract_query.clone(),
            accept,
        )?;

        // Score functions.
        let mut funcs: Vec<(i64, Value)> = Vec::new();
        for f in abi.functions() {
            let sig = Self::function_signature(f);
            let score = Self::score_function(&f.name, &sig, &text, hint);
            if score <= 0 {
                continue;
            }

            let (filled_args, missing) = Self::infer_args_for_function(f, &text);

            funcs.push((
                score,
                json!({
                    "score": score,
                    "function": f.name,
                    "signature": sig,
                    "inputs": f.inputs.iter().map(|p| json!({"name": p.name, "type": p.kind.to_string()})).collect::<Vec<_>>(),
                    "filled_args": filled_args,
                    "missing": missing
                }),
            ));
        }

        funcs.sort_by(|a, b| b.0.cmp(&a.0));
        let mut items: Vec<Value> = funcs.into_iter().take(limit).map(|(_, v)| v).collect();

        // If we have no scored functions, still provide a few functions as fallback.
        if items.is_empty() {
            let mut fallback: Vec<Value> = Vec::new();
            for f in abi.functions().take(limit) {
                fallback.push(json!({
                    "score": 0,
                    "function": f.name,
                    "signature": Self::function_signature(f),
                    "inputs": f.inputs.iter().map(|p| json!({"name": p.name, "type": p.kind.to_string()})).collect::<Vec<_>>()
                }));
            }
            items = fallback;
        }

        // Add stable candidate_id + recommended execute payload.
        let mut candidates: Vec<Value> = Vec::new();
        for (i, mut v) in items.into_iter().enumerate() {
            let signature = v
                .get("signature")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let function = v
                .get("function")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let args = v.get("filled_args").cloned().unwrap_or(Value::Null);
            let missing = v
                .get("missing")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();

            let mut questions: Vec<String> = Vec::new();
            for m in missing.iter() {
                let name = m.get("name").and_then(Value::as_str).unwrap_or("arg");
                let ty = m.get("type").and_then(Value::as_str).unwrap_or("value");
                questions.push(format!("Provide {} ({})", name, ty));
            }

            if let Value::Object(ref mut map) = v {
                map.insert("candidate_id".to_string(), json!(i));
                map.insert(
                    "recommended_execute_payload".to_string(),
                    json!({
                        "chain_id": request.chain_id,
                        "sender": "<sender>",
                        "address": address,
                        "function": function,
                        "function_signature": signature,
                        "args": args,
                        "value_wei": null,
                        "gas_limit": null,
                        "allow_sender_mismatch": false
                    }),
                );
                map.insert("questions".to_string(), json!(questions));
            }

            candidates.push(v);
        }

        // Convenience: suggest a next step using the top candidate.
        let next_step = candidates
            .get(0)
            .and_then(|c| c.get("recommended_execute_payload"))
            .cloned();
        let next_questions = candidates
            .get(0)
            .and_then(|c| c.get("questions"))
            .cloned()
            .unwrap_or(json!([]));

        let response = Self::pretty_json(&json!({
            "chain_id": request.chain_id,
            "contract": {
                "address": address,
                "name": entry.get("name"),
                "entry": entry
            },
            "text": request.text,
            "function_hint": request.function_hint,
            "candidates": candidates,
            "next": {
                "recommended_execute_payload": next_step,
                "questions": next_questions,
                "how_to_execute": "Pick a candidate_id (or function_signature) and call evm_execute_contract_call with sender + function_signature + args. If questions is non-empty, fill those first."
            },
            "note": "This tool only plans; it never executes. Default behavior is safe: if contract_query is ambiguous, require explicit confirmation unless accept_best_match=true."
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn abi_find_function<'a>(
        abi: &'a ethers::abi::Abi,
        name: &str,
        arg_len: usize,
    ) -> Option<&'a ethers::abi::Function> {
        let funcs = abi.functions().filter(|f| f.name == name);
        for f in funcs {
            if f.inputs.len() == arg_len {
                return Some(f);
            }
        }
        None
    }

    fn token_to_json(token: &ethers::abi::Token) -> Value {
        use ethers::abi::Token;
        match token {
            Token::Address(a) => json!(format!("0x{}", hex::encode(a.as_bytes()))),
            Token::Uint(u) => json!(u.to_string()),
            Token::Int(i) => json!(i.to_string()),
            Token::Bool(b) => json!(*b),
            Token::String(s) => json!(s),
            Token::Bytes(b) => json!(format!("0x{}", hex::encode(b))),
            Token::FixedBytes(b) => json!(format!("0x{}", hex::encode(b))),
            Token::Array(items) | Token::FixedArray(items) => {
                json!(items.iter().map(Self::token_to_json).collect::<Vec<_>>())
            }
            Token::Tuple(items) => json!(items.iter().map(Self::token_to_json).collect::<Vec<_>>()),
        }
    }

    fn json_to_token(
        kind: &ethers::abi::ParamType,
        v: &Value,
    ) -> Result<ethers::abi::Token, ErrorData> {
        use ethers::abi::{ParamType, Token};

        let err = |msg: &str| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(msg.to_string()),
            data: None,
        };

        match kind {
            ParamType::Address => {
                let s = v.as_str().ok_or_else(|| err("Expected address string"))?;
                Ok(Token::Address(Self::parse_evm_address(s)?))
            }
            ParamType::Uint(_) => {
                let s = v.as_str().map(|s| s.to_string()).unwrap_or_else(|| v.to_string());
                Ok(Token::Uint(Self::parse_evm_u256("uint", &s)?))
            }
            ParamType::Int(_) => {
                let s = v.as_str().map(|s| s.to_string()).unwrap_or_else(|| v.to_string());
                // MVP: use U256-backed int. (Good enough for common positive ints.)
                Ok(Token::Int(Self::parse_evm_u256("int", &s)?))
            }
            ParamType::Bool => Ok(Token::Bool(v.as_bool().ok_or_else(|| err("Expected bool"))?)),
            ParamType::String => Ok(Token::String(
                v.as_str().ok_or_else(|| err("Expected string"))?.to_string(),
            )),
            ParamType::Bytes => {
                let s = v.as_str().ok_or_else(|| err("Expected 0x hex bytes string"))?;
                let hexs = s.strip_prefix("0x").unwrap_or(s);
                let b = hex::decode(hexs).map_err(|e| err(&format!("Invalid hex bytes: {}", e)))?;
                Ok(Token::Bytes(b))
            }
            ParamType::FixedBytes(n) => {
                let s = v.as_str().ok_or_else(|| err("Expected 0x hex bytes string"))?;
                let hexs = s.strip_prefix("0x").unwrap_or(s);
                let b = hex::decode(hexs).map_err(|e| err(&format!("Invalid hex bytes: {}", e)))?;
                if b.len() != *n {
                    return Err(err(&format!("Expected {} bytes, got {}", n, b.len())));
                }
                Ok(Token::FixedBytes(b))
            }
            other => Err(err(&format!(
                "Unsupported param type (MVP): {:?}",
                other
            ))),
        }
    }

    fn load_registered_abi(chain_id: u64, address: &str) -> Result<(Value, ethers::abi::Abi), ErrorData> {
        let path = Self::evm_abi_path(chain_id, address)?;
        let bytes = std::fs::read(&path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read ABI entry: {}", e)),
            data: None,
        })?;
        let entry: Value = serde_json::from_slice(&bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Invalid ABI entry JSON: {}", e)),
            data: None,
        })?;
        let abi_val = entry.get("abi").cloned().ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("ABI entry missing 'abi'"),
            data: None,
        })?;
        let abi: ethers::abi::Abi = serde_json::from_value(abi_val).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Invalid ABI JSON: {}", e)),
            data: None,
        })?;
        Ok((entry, abi))
    }

    fn find_contract_by_name(chain_id: u64, name: &str) -> Result<(Value, ethers::abi::Abi), ErrorData> {
        let root = Self::evm_abi_registry_dir().join(chain_id.to_string());
        let rd = std::fs::read_dir(&root).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read registry dir: {}", e)),
            data: None,
        })?;

        let needle = name.trim().to_lowercase();

        for e in rd.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) != Some("json") {
                continue;
            }
            let Ok(bytes) = std::fs::read(&p) else { continue };
            let Ok(entry) = serde_json::from_slice::<Value>(&bytes) else { continue };
            let entry_name = entry
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_lowercase();
            let entry_addr = entry
                .get("address")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_lowercase();

            if entry_name == needle || entry_addr == needle {
                let abi_val = entry.get("abi").cloned().ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("ABI entry missing 'abi'"),
                    data: None,
                })?;
                let abi: ethers::abi::Abi = serde_json::from_value(abi_val).map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Invalid ABI JSON: {}", e)),
                    data: None,
                })?;
                return Ok((entry, abi));
            }
        }

        Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Contract not found in registry by name/address: {}", name)),
            data: None,
        })
    }

    fn resolve_contract_by_query(
        chain_id: u64,
        query: &str,
        accept_best_match: bool,
    ) -> Result<(Value, ethers::abi::Abi), ErrorData> {
        let root = Self::evm_abi_registry_dir().join(chain_id.to_string());
        let rd = std::fs::read_dir(&root).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read registry dir: {}", e)),
            data: None,
        })?;

        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("contract_query is empty"),
                data: None,
            });
        }

        let mut scored: Vec<(i64, Value)> = Vec::new();
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) != Some("json") {
                continue;
            }
            let path_str = p.to_string_lossy().to_string();
            let Ok(bytes) = std::fs::read(&p) else { continue };
            let Ok(v) = serde_json::from_slice::<Value>(&bytes) else { continue };

            let name = v.get("name").and_then(Value::as_str).unwrap_or("");
            let address = v.get("address").and_then(Value::as_str).unwrap_or("");

            let hay_name = name.to_lowercase();
            let hay_addr = address.to_lowercase();
            let hay_path = path_str.to_lowercase();

            let mut score: i64 = 0;
            if hay_addr == q {
                score += 1000;
            }
            if hay_name.starts_with(&q) {
                score += 300;
            }
            if hay_addr.starts_with(&q) {
                score += 300;
            }
            if hay_name.contains(&q) {
                score += 120;
            }
            if hay_addr.contains(&q) {
                score += 120;
            }
            if hay_path.contains(&q) {
                score += 60;
            }

            if score > 0 {
                scored.push((score, v));
            }
        }

        scored.sort_by(|a, b| b.0.cmp(&a.0));

        if scored.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("No registry matches for query: {}", query)),
                data: None,
            });
        }

        // If ambiguous and not accepting best match, return candidates.
        if scored.len() > 1 && !accept_best_match {
            let candidates: Vec<Value> = scored
                .iter()
                .take(5)
                .map(|(score, v)| {
                    json!({
                        "score": score,
                        "name": v.get("name"),
                        "address": v.get("address")
                    })
                })
                .collect();
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Ambiguous contract_query '{}'. Provide address/contract_name or set accept_best_match=true.",
                    query
                )),
                data: Some(json!(candidates)),
            });
        }

        let best = scored.remove(0).1;
        let abi_val = best.get("abi").cloned().ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("ABI entry missing 'abi'"),
            data: None,
        })?;
        let abi: ethers::abi::Abi = serde_json::from_value(abi_val).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Invalid ABI JSON: {}", e)),
            data: None,
        })?;
        Ok((best, abi))
    }

    fn resolve_contract_for_call(
        chain_id: u64,
        address: Option<String>,
        contract_name: Option<String>,
        contract_query: Option<String>,
        accept_best_match: bool,
    ) -> Result<(String, Value, ethers::abi::Abi), ErrorData> {
        if let Some(addr) = address {
            let (entry, abi) = Self::load_registered_abi(chain_id, &addr)?;
            return Ok((Self::normalize_evm_address(&addr)?, entry, abi));
        }
        if let Some(name) = contract_name {
            let (entry, abi) = Self::find_contract_by_name(chain_id, &name)?;
            let addr = entry
                .get("address")
                .and_then(Value::as_str)
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Registry entry missing address"),
                    data: None,
                })?;
            return Ok((addr.to_string(), entry, abi));
        }
        if let Some(q) = contract_query {
            let (entry, abi) = Self::resolve_contract_by_query(chain_id, &q, accept_best_match)?;
            let addr = entry
                .get("address")
                .and_then(Value::as_str)
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Registry entry missing address"),
                    data: None,
                })?;
            return Ok((addr.to_string(), entry, abi));
        }
        Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Must provide address, contract_name, or contract_query"),
            data: None,
        })
    }

    fn function_signature(func: &ethers::abi::Function) -> String {
        let types = func
            .inputs
            .iter()
            .map(|p| p.kind.to_string())
            .collect::<Vec<_>>()
            .join(",");
        format!("{}({})", func.name, types)
    }

    fn abi_find_function_exact<'a>(
        abi: &'a ethers::abi::Abi,
        signature: &str,
    ) -> Option<&'a ethers::abi::Function> {
        let sig = signature.trim();
        let name = sig.split('(').next().unwrap_or(sig);
        for f in abi.functions().filter(|f| f.name == name) {
            if Self::function_signature(f) == sig {
                return Some(f);
            }
        }
        None
    }

    #[tool(description = "EVM ABI Registry: call a view/pure function using registered ABI")]
    async fn evm_call_view(
        &self,
        Parameters(request): Parameters<EvmCallViewRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let provider = self.evm_provider(request.chain_id).await?;

        let (address_norm, _entry, abi) = Self::resolve_contract_for_call(
            request.chain_id,
            request.address.clone(),
            request.contract_name.clone(),
            request.contract_query.clone(),
            request.accept_best_match.unwrap_or(false),
        )?;
        let contract = Self::parse_evm_address(&address_norm)?;

        let args = request.args.unwrap_or(Value::Array(vec![]));
        let args_arr = args
            .as_array()
            .cloned()
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("args must be a JSON array"),
                data: None,
            })?;

        let func = if let Some(sig) = request.function_signature.as_deref() {
            Self::abi_find_function_exact(&abi, sig).ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Function not found in ABI (by exact signature)"),
                data: None,
            })?
        } else {
            Self::abi_find_function(&abi, &request.function, args_arr.len()).ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Function not found in ABI (by name + arg count). Tip: pass function_signature to disambiguate overloads."),
                data: None,
            })?
        };
        let mut tokens: Vec<ethers::abi::Token> = Vec::new();
        for (i, param) in func.inputs.iter().enumerate() {
            tokens.push(Self::json_to_token(&param.kind, &args_arr[i])?);
        }

        let data = func.encode_input(&tokens).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to encode call data: {}", e)),
            data: None,
        })?;

        let call = ethers::types::TransactionRequest {
            to: Some(ethers::types::NameOrAddress::Address(contract)),
            data: Some(ethers::types::Bytes::from(data)),
            ..Default::default()
        };
        let typed: ethers::types::transaction::eip2718::TypedTransaction = call.clone().into();

        let raw = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::call(
            &provider,
            &typed,
            None,
        )
        .await
        .map_err(|e| Self::sdk_error("evm_call_view:eth_call", e))?;

        let decoded_tokens = func.decode_output(raw.as_ref()).ok();
        let decoded = decoded_tokens
            .as_ref()
            .map(|tokens| tokens.iter().map(Self::token_to_json).collect::<Vec<_>>());

        let decoded_named = decoded_tokens.as_ref().map(|tokens| {
            func.outputs
                .iter()
                .enumerate()
                .map(|(i, out)| {
                    let name = if out.name.is_empty() {
                        format!("out_{}", i)
                    } else {
                        out.name.clone()
                    };
                    let value = tokens.get(i).map(Self::token_to_json).unwrap_or(Value::Null);
                    (name, value)
                })
                .collect::<serde_json::Map<String, Value>>()
        });

        let response = Self::pretty_json(&json!({
            "chain_id": request.chain_id,
            "address": address_norm,
            "function": request.function,
            "function_signature": request.function_signature.unwrap_or_else(|| Self::function_signature(func)),
            "args": args_arr,
            "result_hex": format!("0x{}", hex::encode(raw.as_ref())),
            "decoded": decoded,
            "decoded_named": decoded_named
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ABI Registry: build a contract tx (nonpayable/payable) using registered ABI. Returns an EvmTxRequest; run evm_preflight -> evm_sign_transaction_local -> evm_send_raw_transaction.")]
    async fn evm_build_contract_tx(
        &self,
        Parameters(request): Parameters<EvmBuildContractTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (address_norm, entry, abi) = Self::resolve_contract_for_call(
            request.chain_id,
            request.address.clone(),
            request.contract_name.clone(),
            request.contract_query.clone(),
            request.accept_best_match.unwrap_or(false),
        )?;
        let contract = Self::parse_evm_address(&address_norm)?;

        let args = request.args.unwrap_or(Value::Array(vec![]));
        let args_arr = args
            .as_array()
            .cloned()
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("args must be a JSON array"),
                data: None,
            })?;

        let func = if let Some(sig) = request.function_signature.as_deref() {
            Self::abi_find_function_exact(&abi, sig).ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Function not found in ABI (by exact signature)"),
                data: None,
            })?
        } else {
            Self::abi_find_function(&abi, &request.function, args_arr.len()).ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Function not found in ABI (by name + arg count). Tip: pass function_signature to disambiguate overloads."),
                data: None,
            })?
        };

        let mut tokens: Vec<ethers::abi::Token> = Vec::new();
        for (i, param) in func.inputs.iter().enumerate() {
            tokens.push(Self::json_to_token(&param.kind, &args_arr[i])?);
        }

        let data = func.encode_input(&tokens).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to encode call data: {}", e)),
            data: None,
        })?;

        let value = if let Some(v) = request.value_wei.as_deref() {
            Self::parse_evm_u256("value_wei", v)?
        } else {
            ethers::types::U256::from(0)
        };

        let tx_request = ethers::types::TransactionRequest {
            from: Some(Self::parse_evm_address(&request.sender)?),
            to: Some(ethers::types::NameOrAddress::Address(contract)),
            value: Some(value),
            data: Some(ethers::types::Bytes::from(data)),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        let tx = Self::tx_request_to_evm_tx(&tx_request, request.chain_id);

        let resolved = json!({
            "chain_id": request.chain_id,
            "address": address_norm,
            "name": entry.get("name").and_then(Value::as_str),
            "path": entry.get("path").and_then(Value::as_str)
        });

        let response = Self::pretty_json(&json!({
            "contract": resolved,
            "function": request.function,
            "function_signature": request.function_signature.clone().unwrap_or_else(|| Self::function_signature(func)),
            "args": args_arr,
            "tx": tx,
            "note": "Run evm_preflight -> evm_sign_transaction_local -> evm_send_raw_transaction"
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ABI Registry: execute a contract call (nonpayable/payable) using registered ABI")]
    async fn evm_execute_contract_call(
        &self,
        Parameters(request): Parameters<EvmExecuteContractCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let built = self
            .evm_build_contract_tx(Parameters(EvmBuildContractTxRequest {
                chain_id: request.chain_id,
                sender: request.sender.clone(),
                address: request.address.clone(),
                contract_name: request.contract_name.clone(),
                contract_query: request.contract_query.clone(),
                accept_best_match: request.accept_best_match,
                function: request.function.clone(),
                function_signature: request.function_signature.clone(),
                args: request.args.clone(),
                value_wei: request.value_wei.clone(),
                gas_limit: request.gas_limit,
            }))
            .await?;

        let built_json = Self::evm_extract_first_json(&built).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse built tx"),
            data: None,
        })?;
        let tx: EvmTxRequest = serde_json::from_value(
            built_json.get("tx").cloned().unwrap_or(Value::Null),
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode tx: {}", e)),
            data: None,
        })?;

        let preflight = self
            .evm_preflight(Parameters(EvmPreflightRequest { tx }))
            .await?;
        let preflight_json = Self::evm_extract_first_json(&preflight).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse preflight"),
            data: None,
        })?;
        let tx: EvmTxRequest = serde_json::from_value(
            preflight_json.get("tx").cloned().unwrap_or(Value::Null),
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode preflight tx: {}", e)),
            data: None,
        })?;

        if request.dry_run_only.unwrap_or(false) {
            let response = Self::pretty_json(&json!({
                "tx": tx,
                "note": "dry_run_only=true: tx is built and preflighted, but NOT signed/broadcasted"
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let signed = self
            .evm_sign_transaction_local(Parameters(EvmSignLocalRequest {
                tx,
                allow_sender_mismatch: request.allow_sender_mismatch,
            }))
            .await?;

        let signed_json = Self::evm_extract_first_json(&signed).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse signed"),
            data: None,
        })?;
        let raw_tx = signed_json
            .get("raw_tx")
            .and_then(Value::as_str)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Missing raw_tx"),
                data: None,
            })?
            .to_string();

        self.evm_send_raw_transaction(Parameters(EvmSendRawTransactionRequest {
            chain_id: Some(request.chain_id),
            raw_tx,
        }))
        .await
    }

    #[tool(description = "EVM: get transaction by hash")]
    async fn evm_get_transaction(
        &self,
        Parameters(request): Parameters<EvmGetTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;
        let hash = Self::parse_evm_h256(&request.tx_hash)?;

        let tx = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction(
            &provider,
            hash,
        )
        .await
        .map_err(|e| Self::sdk_error("evm_get_transaction", e))?;

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": request.tx_hash,
            "transaction": tx
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: build a native transfer tx (fills to/value; optional data). Use evm_preflight to fill nonce/gas/fees.")]
    async fn evm_build_transfer_native(
        &self,
        Parameters(request): Parameters<EvmBuildTransferNativeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let from = Self::parse_evm_address(&request.sender)?;
        let to = Self::parse_evm_address(&request.recipient)?;
        let value = Self::parse_evm_u256("amount_wei", &request.amount_wei)?;

        let tx = EvmTxRequest {
            chain_id,
            from: request.sender,
            to: request.recipient,
            value_wei: value.to_string(),
            data_hex: request.data_hex,
            nonce: None,
            gas_limit: request.gas_limit,
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
        };

        // Basic safety: optional large transfer confirmation.
        let confirm_large = request.confirm_large_transfer.unwrap_or(false);
        let threshold = request
            .large_transfer_threshold_wei
            .as_deref()
            .unwrap_or("100000000000000000"); // 0.1 ETH default
        let threshold_u256 = Self::parse_evm_u256("large_transfer_threshold_wei", threshold)?;
        if value >= threshold_u256 && !confirm_large {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Large transfer: amount_wei={} >= threshold_wei={}. Set confirm_large_transfer=true to proceed.",
                    value, threshold_u256
                )),
                data: None,
            });
        }

        // Avoid unused warnings (we only parse to validate)
        let _ = (from, to);

        let response = Self::pretty_json(&tx)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: preflight a tx (fills nonce, gas_limit, max_fee_per_gas, max_priority_fee_per_gas).")]
    async fn evm_preflight(
        &self,
        Parameters(request): Parameters<EvmPreflightRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let mut tx = request.tx.clone();
        let chain_id = tx.chain_id;
        let provider = self.evm_provider(chain_id).await?;

        let from = Self::parse_evm_address(&tx.from)?;
        let to = Self::parse_evm_address(&tx.to)?;
        let value = Self::parse_evm_u256("value_wei", &tx.value_wei)?;
        let data = if let Some(hex) = tx.data_hex.as_deref() {
            let hex = hex.strip_prefix("0x").unwrap_or(hex);
            let bytes = hex::decode(hex).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid data_hex: {}", e)),
                data: None,
            })?;
            ethers::types::Bytes::from(bytes)
        } else {
            ethers::types::Bytes::from(Vec::<u8>::new())
        };

        // Nonce
        if tx.nonce.is_none() {
            let nonce = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction_count(
                &provider,
                from,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_preflight:get_transaction_count", e))?;
            tx.nonce = Some(nonce.as_u64());
        }

        // Fee data (EIP-1559 where available)
        if tx.max_fee_per_gas_wei.is_none() || tx.max_priority_fee_per_gas_wei.is_none() {
            // Prefer EIP-1559 fee estimation.
            let fees = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::estimate_eip1559_fees(
                &provider,
                None,
            )
            .await;

            match fees {
                Ok((max_fee, max_prio)) => {
                    if tx.max_fee_per_gas_wei.is_none() {
                        tx.max_fee_per_gas_wei = Some(max_fee.to_string());
                    }
                    if tx.max_priority_fee_per_gas_wei.is_none() {
                        tx.max_priority_fee_per_gas_wei = Some(max_prio.to_string());
                    }
                }
                Err(_) => {
                    // Fallback: legacy gas price.
                    let gas_price = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_gas_price(
                        &provider,
                    )
                    .await
                    .map_err(|e| Self::sdk_error("evm_preflight:get_gas_price", e))?;

                    if tx.max_fee_per_gas_wei.is_none() {
                        tx.max_fee_per_gas_wei = Some(gas_price.to_string());
                    }
                    if tx.max_priority_fee_per_gas_wei.is_none() {
                        tx.max_priority_fee_per_gas_wei = Some("0".to_string());
                    }
                }
            }
        }

        // Gas limit
        if tx.gas_limit.is_none() {
            let estimate_req = ethers::types::TransactionRequest {
                from: Some(from),
                to: Some(ethers::types::NameOrAddress::Address(to)),
                value: Some(value),
                data: Some(data.clone()),
                ..Default::default()
            };
            let typed: ethers::types::transaction::eip2718::TypedTransaction =
                estimate_req.clone().into();

            let est = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::estimate_gas(
                &provider,
                &typed,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_preflight:estimate_gas", e))?;

            // buffer 20%
            let buffered = est
                .checked_mul(ethers::types::U256::from(12))
                .unwrap_or(est)
                / ethers::types::U256::from(10);
            tx.gas_limit = Some(buffered.as_u64());
        }

        let response = Self::pretty_json(&json!({
            "tx": tx,
            "note": "Use evm_sign_transaction_local to sign, then evm_send_raw_transaction to broadcast."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: sign a tx using a local private key (EVM_PRIVATE_KEY env). Returns raw_tx hex.")]
    async fn evm_sign_transaction_local(
        &self,
        Parameters(request): Parameters<EvmSignLocalRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request.tx.chain_id;
        let pk = std::env::var("EVM_PRIVATE_KEY").map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Missing EVM_PRIVATE_KEY env var"),
            data: None,
        })?;
        let wallet: ethers::signers::LocalWallet = pk.parse().map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid EVM_PRIVATE_KEY: {}", e)),
            data: None,
        })?;
        let wallet = ethers::signers::Signer::with_chain_id(wallet, chain_id);

        let from = Self::parse_evm_address(&request.tx.from)?;
        let to = Self::parse_evm_address(&request.tx.to)?;
        let value = Self::parse_evm_u256("value_wei", &request.tx.value_wei)?;
        let nonce = request.tx.nonce.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("tx.nonce is required; run evm_preflight first"),
            data: None,
        })?;
        let gas_limit = request.tx.gas_limit.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("tx.gas_limit is required; run evm_preflight first"),
            data: None,
        })?;

        let max_fee = request
            .tx
            .max_fee_per_gas_wei
            .as_deref()
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "tx.max_fee_per_gas_wei is required; run evm_preflight first",
                ),
                data: None,
            })?;
        let max_fee = Self::parse_evm_u256("max_fee_per_gas_wei", max_fee)?;

        let max_prio = request
            .tx
            .max_priority_fee_per_gas_wei
            .as_deref()
            .unwrap_or("0");
        let max_prio = Self::parse_evm_u256("max_priority_fee_per_gas_wei", max_prio)?;

        let data = if let Some(hex) = request.tx.data_hex.as_deref() {
            let hex = hex.strip_prefix("0x").unwrap_or(hex);
            let bytes = hex::decode(hex).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid data_hex: {}", e)),
                data: None,
            })?;
            ethers::types::Bytes::from(bytes)
        } else {
            ethers::types::Bytes::from(Vec::<u8>::new())
        };

        // Basic sender mismatch protection.
        if !request.allow_sender_mismatch.unwrap_or(false) {
            let wallet_addr = ethers::signers::Signer::address(&wallet);
            if wallet_addr != from {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Signer mismatch: wallet={} tx.from={}. Set allow_sender_mismatch=true if intentional.",
                        wallet_addr, from
                    )),
                    data: None,
                });
            }
        }

        let tx1559 = ethers::types::transaction::eip1559::Eip1559TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(to)),
            value: Some(value),
            data: Some(data),
            nonce: Some(nonce.into()),
            gas: Some(gas_limit.into()),
            max_fee_per_gas: Some(max_fee),
            max_priority_fee_per_gas: Some(max_prio),
            chain_id: Some(chain_id.into()),
            ..Default::default()
        };

        let mut typed: ethers::types::transaction::eip2718::TypedTransaction = tx1559.into();
        // Ensure chain id is set
        typed.set_chain_id(chain_id);

        let sig = ethers::signers::Signer::sign_transaction(&wallet, &typed)
            .await
            .map_err(|e| Self::sdk_error("evm_sign_transaction_local", e))?;

        let raw = typed.rlp_signed(&sig);
        let raw_hex = format!("0x{}", hex::encode(raw.as_ref()));

        // Optional audit log.
        self.write_audit_log(
            "evm_sign_transaction_local",
            json!({
                "chain_id": chain_id,
                "from": request.tx.from,
                "to": request.tx.to,
                "value_wei": request.tx.value_wei,
                "nonce": nonce,
                "gas_limit": gas_limit,
                "max_fee_per_gas_wei": max_fee.to_string(),
                "max_priority_fee_per_gas_wei": max_prio.to_string(),
                "raw_tx_prefix": &raw_hex.chars().take(18).collect::<String>()
            }),
        );

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "raw_tx": raw_hex
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn evm_extract_first_json(result: &CallToolResult) -> Option<Value> {
        let content = result.content.first()?;
        let text = match &content.raw {
            RawContent::Text(text) => Some(text.text.clone()),
            RawContent::Resource(resource) => match &resource.resource {
                ResourceContents::TextResourceContents { text, .. } => Some(text.clone()),
                _ => None,
            },
            _ => None,
        }?;
        serde_json::from_str::<Value>(&text).ok()
    }

    fn evm_explorer_tx_url(chain_id: u64, tx_hash: &str) -> Option<String> {
        let base = match chain_id {
            8453 => "https://basescan.org/tx/",
            84532 => "https://sepolia.basescan.org/tx/",
            1 => "https://etherscan.io/tx/",
            11155111 => "https://sepolia.etherscan.io/tx/",
            42161 => "https://arbiscan.io/tx/",
            421614 => "https://sepolia.arbiscan.io/tx/",
            56 => "https://bscscan.com/tx/",
            97 => "https://testnet.bscscan.com/tx/",
            _ => return None,
        };
        Some(format!("{}{}", base, tx_hash))
    }

    #[tool(description = "EVM: broadcast a raw signed transaction")]
    async fn evm_send_raw_transaction(
        &self,
        Parameters(request): Parameters<EvmSendRawTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let raw_hex = request.raw_tx.strip_prefix("0x").unwrap_or(&request.raw_tx);
        let raw = hex::decode(raw_hex).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid raw_tx hex: {}", e)),
            data: None,
        })?;

        let pending = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::send_raw_transaction(
            &provider,
            ethers::types::Bytes::from(raw),
        )
        .await
        .map_err(|e| Self::sdk_error("evm_send_raw_transaction", e))?;

        let tx_hash = format!("0x{}", hex::encode(pending.tx_hash().as_bytes()));
        let explorer_url = Self::evm_explorer_tx_url(chain_id, &tx_hash);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": tx_hash,
            "explorer_url": explorer_url
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    async fn evm_execute_tx_request(
        &self,
        chain_id: u64,
        tx_request: ethers::types::TransactionRequest,
        allow_sender_mismatch: bool,
    ) -> Result<CallToolResult, ErrorData> {
        let built_json_for_return = serde_json::to_value(Self::tx_request_to_evm_tx(&tx_request, chain_id))
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to serialize tx_request: {}", e)),
                data: None,
            })?;

        let tx: EvmTxRequest = serde_json::from_value(built_json_for_return.clone()).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode EVM tx: {}", e)),
            data: None,
        })?;

        let preflight = self
            .evm_preflight(Parameters(EvmPreflightRequest { tx: tx.clone() }))
            .await?;

        let pre_json = Self::evm_extract_first_json(&preflight).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_preflight result"),
            data: None,
        })?;
        let pre_json_for_return = pre_json.clone();

        let tx_val = pre_json.get("tx").cloned().unwrap_or_else(|| pre_json.clone());
        let tx: EvmTxRequest = serde_json::from_value(tx_val).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode preflight tx: {}", e)),
            data: None,
        })?;

        let signed = self
            .evm_sign_transaction_local(Parameters(EvmSignLocalRequest {
                tx: tx.clone(),
                allow_sender_mismatch: Some(allow_sender_mismatch),
            }))
            .await?;

        let signed_json = Self::evm_extract_first_json(&signed).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_sign_transaction_local result"),
            data: None,
        })?;

        let raw_tx = signed_json
            .get("raw_tx")
            .and_then(Value::as_str)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Missing raw_tx from signer"),
                data: None,
            })?
            .to_string();
        let raw_tx_prefix = raw_tx.chars().take(18).collect::<String>();

        let sent = self
            .evm_send_raw_transaction(Parameters(EvmSendRawTransactionRequest {
                raw_tx,
                chain_id: Some(chain_id),
            }))
            .await?;

        let sent_json = Self::evm_extract_first_json(&sent).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_send_raw_transaction result"),
            data: None,
        })?;

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_built": built_json_for_return,
            "tx_preflight": pre_json_for_return,
            "raw_tx_prefix": raw_tx_prefix,
            "send": sent_json
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // (removed duplicate evm_get_transaction tool; use the earlier definition)

    #[tool(description = "EVM: speed up a pending tx by sending a replacement with the same nonce and higher fees (safe-default: returns confirmation_id)")]
    async fn evm_speed_up_tx(
        &self,
        Parameters(request): Parameters<EvmSpeedUpTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let provider = self.evm_provider(request.chain_id).await?;

        let strict = request.strict.unwrap_or(false);

        // Source tx fields
        let (from, nonce, to, value, data_hex, gas_limit_from_tx, old_max_fee, old_max_prio, original_tx_hash) =
            if let Some(tx_hash) = request.tx_hash.as_deref() {
                let h = Self::parse_evm_h256(tx_hash)?;
                let tx = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction(&provider, h)
                    .await
                    .map_err(|e| Self::sdk_error("evm_speed_up_tx:get_transaction", e))?
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("Transaction not found by hash"),
                        data: None,
                    })?;

                let from = tx.from;
                let nonce = tx.nonce;
                let to = tx.to.unwrap_or(from);
                let value = tx.value;
                let data_hex = Some(format!("0x{}", hex::encode(tx.input.0.clone())));
                let gas_limit_from_tx = tx.gas.as_u64();

                // old fee hints from tx if present
                let old_max_fee = tx.max_fee_per_gas.or(tx.gas_price);
                let old_max_prio = tx.max_priority_fee_per_gas;

                (
                    from,
                    nonce,
                    to,
                    value,
                    data_hex,
                    Some(gas_limit_from_tx),
                    old_max_fee,
                    old_max_prio,
                    Some(tx_hash.to_string()),
                )
            } else {
                // from+nonce mode (requires full tx payload for speed-up)
                let from = Self::parse_evm_address(
                    request.from.as_deref().ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("Missing tx_hash or from"),
                        data: None,
                    })?,
                )?;
                let nonce = ethers::types::U256::from(
                    request.nonce.ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("Missing nonce"),
                        data: None,
                    })?,
                );
                let to = Self::parse_evm_address(
                    request.to.as_deref().ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Missing to (required when tx_hash is not provided)",
                        ),
                        data: None,
                    })?,
                )?;
                let value = Self::parse_evm_u256(
                    "value_wei",
                    request.value_wei.as_deref().unwrap_or("0"),
                )?;
                let data_hex = Some(request.data_hex.clone().unwrap_or_else(|| "0x".to_string()));
                (from, nonce, to, value, data_hex, None, None, None, None)
            };

        // Fee suggestions (best-effort): use legacy gas_price and convert into EIP-1559 params.
        let gas_price = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_gas_price(&provider)
            .await
            .unwrap_or_else(|_| ethers::types::U256::from(0));
        let suggested_max_fee = gas_price.checked_mul(ethers::types::U256::from(2)).unwrap_or(gas_price);
        let suggested_max_prio = gas_price
            .checked_div(ethers::types::U256::from(10))
            .unwrap_or(ethers::types::U256::from(0));

        let old_max_fee = old_max_fee.unwrap_or(gas_price);
        let old_max_prio = old_max_prio.unwrap_or(ethers::types::U256::from(0));

        let bump_bps = request.fee_bump_bps.unwrap_or(12_000);

        let max_fee = if let Some(v) = request.max_fee_per_gas_wei.as_deref() {
            Self::parse_evm_u256("max_fee_per_gas_wei", v)?
        } else {
            crate::utils::evm_tx_replace::bump_u256(Some(old_max_fee), Some(suggested_max_fee), bump_bps)
        };
        let max_prio = if let Some(v) = request.max_priority_fee_per_gas_wei.as_deref() {
            Self::parse_evm_u256("max_priority_fee_per_gas_wei", v)?
        } else {
            crate::utils::evm_tx_replace::bump_u256(Some(old_max_prio), Some(suggested_max_prio), bump_bps)
        };

        let tx_req = EvmTxRequest {
            chain_id: request.chain_id,
            from: format!("0x{}", hex::encode(from.as_bytes())),
            to: format!("0x{}", hex::encode(to.as_bytes())),
            value_wei: value.to_string(),
            data_hex,
            nonce: Some(nonce.as_u64()),
            gas_limit: None,
            max_fee_per_gas_wei: Some(max_fee.to_string()),
            max_priority_fee_per_gas_wei: Some(max_prio.to_string()),
        };

        let tx_final: EvmTxRequest = if strict && gas_limit_from_tx.is_some() {
            let mut t = tx_req;
            t.gas_limit = gas_limit_from_tx;
            t
        } else {
            // Preflight for gas limit and sanity.
            let pre = self.evm_preflight(Parameters(EvmPreflightRequest { tx: tx_req })).await?;
            let pre_json = Self::evm_extract_first_json(&pre).ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Failed to parse evm_preflight response"),
                data: None,
            })?;
            serde_json::from_value(pre_json.get("tx").cloned().unwrap_or(Value::Null)).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode preflight tx: {}", e)),
                data: None,
            })?
        };

        let confirmation_id = format!("evm_replace_{}_{}", crate::utils::evm_confirm_store::now_ms(), nonce);
        let ttl = crate::utils::evm_confirm_store::default_ttl_ms();
        let now_ms = crate::utils::evm_confirm_store::now_ms();
        let expires = now_ms + ttl;
        let hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx_final);
        crate::utils::evm_confirm_store::insert_pending(&confirmation_id, &tx_final, now_ms, expires, &hash)?;

        self.write_audit_log(
            "evm_speed_up_tx",
            json!({
                "event": "pending",
                "original_tx_hash": original_tx_hash,
                "confirmation_id": confirmation_id,
                "nonce": nonce.as_u64(),
                "max_fee_per_gas_wei": tx_final.max_fee_per_gas_wei,
                "max_priority_fee_per_gas_wei": tx_final.max_priority_fee_per_gas_wei,
                "strict": strict,
            }),
        );

        let response = Self::pretty_json(&json!({
            "status": "pending",
            "original_tx_hash": original_tx_hash,
            "confirmation_id": confirmation_id,
            "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx_final),
            "tx_summary_hash": hash,
            "expires_in_ms": ttl,
            "web3mcp": {
                "debug": {
                    "decision": "evm_speed_up_tx",
                    "decision_label": "evm_speed_up_tx",
                    "strict": strict
                }
            },
            "next": {
                "how_to_confirm": format!("confirm {} hash:{} (replacement)", confirmation_id, hash)
            }
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: cancel a pending tx by sending a 0-value self-transfer with the same nonce and higher fees (safe-default: returns confirmation_id)")]
    async fn evm_cancel_tx(
        &self,
        Parameters(request): Parameters<EvmCancelTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let provider = self.evm_provider(request.chain_id).await?;

        let strict = request.strict.unwrap_or(false);

        let (from, nonce, old_max_fee, old_max_prio, original_tx_hash) = if let Some(tx_hash) = request.tx_hash.as_deref() {
            let h = Self::parse_evm_h256(tx_hash)?;
            let tx = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction(&provider, h)
                .await
                .map_err(|e| Self::sdk_error("evm_cancel_tx:get_transaction", e))?
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Transaction not found by hash"),
                    data: None,
                })?;
            (
                tx.from,
                tx.nonce,
                tx.max_fee_per_gas.or(tx.gas_price),
                tx.max_priority_fee_per_gas,
                Some(tx_hash.to_string()),
            )
        } else {
            let from = Self::parse_evm_address(
                request.from.as_deref().ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Missing tx_hash or from"),
                    data: None,
                })?,
            )?;
            let nonce = ethers::types::U256::from(
                request.nonce.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Missing nonce"),
                    data: None,
                })?,
            );
            (from, nonce, None, None, None)
        };

        let gas_price = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_gas_price(&provider)
            .await
            .unwrap_or_else(|_| ethers::types::U256::from(0));
        let suggested_max_fee = gas_price
            .checked_mul(ethers::types::U256::from(2))
            .unwrap_or(gas_price);
        let suggested_max_prio = gas_price
            .checked_div(ethers::types::U256::from(10))
            .unwrap_or(ethers::types::U256::from(0));

        let old_max_fee = old_max_fee.unwrap_or(gas_price);
        let old_max_prio = old_max_prio.unwrap_or(ethers::types::U256::from(0));

        let bump_bps = request.fee_bump_bps.unwrap_or(13_000);
        let max_fee = crate::utils::evm_tx_replace::bump_u256(Some(old_max_fee), Some(suggested_max_fee), bump_bps);
        let max_prio = crate::utils::evm_tx_replace::bump_u256(Some(old_max_prio), Some(suggested_max_prio), bump_bps);

        let tx_req = EvmTxRequest {
            chain_id: request.chain_id,
            from: format!("0x{}", hex::encode(from.as_bytes())),
            to: format!("0x{}", hex::encode(from.as_bytes())),
            value_wei: "0".to_string(),
            data_hex: Some("0x".to_string()),
            nonce: Some(nonce.as_u64()),
            gas_limit: None,
            max_fee_per_gas_wei: Some(max_fee.to_string()),
            max_priority_fee_per_gas_wei: Some(max_prio.to_string()),
        };

        let pre = self.evm_preflight(Parameters(EvmPreflightRequest { tx: tx_req })).await?;
        let pre_json = Self::evm_extract_first_json(&pre).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_preflight response"),
            data: None,
        })?;
        let tx_final: EvmTxRequest = serde_json::from_value(pre_json.get("tx").cloned().unwrap_or(Value::Null)).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode preflight tx: {}", e)),
            data: None,
        })?;

        let confirmation_id = format!("evm_cancel_{}_{}", crate::utils::evm_confirm_store::now_ms(), nonce);
        let ttl = crate::utils::evm_confirm_store::default_ttl_ms();
        let now_ms = crate::utils::evm_confirm_store::now_ms();
        let expires = now_ms + ttl;
        let hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx_final);
        crate::utils::evm_confirm_store::insert_pending(&confirmation_id, &tx_final, now_ms, expires, &hash)?;

        self.write_audit_log(
            "evm_cancel_tx",
            json!({
                "event": "pending",
                "original_tx_hash": original_tx_hash,
                "confirmation_id": confirmation_id,
                "nonce": nonce.as_u64(),
                "max_fee_per_gas_wei": tx_final.max_fee_per_gas_wei,
                "max_priority_fee_per_gas_wei": tx_final.max_priority_fee_per_gas_wei,
                "strict": strict,
            }),
        );

        let response = Self::pretty_json(&json!({
            "status": "pending",
            "original_tx_hash": original_tx_hash,
            "confirmation_id": confirmation_id,
            "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx_final),
            "tx_summary_hash": hash,
            "expires_in_ms": ttl,
            "web3mcp": {
                "debug": {
                    "decision": "evm_cancel_tx",
                    "decision_label": "evm_cancel_tx",
                    "strict": strict
                }
            },
            "next": {
                "how_to_confirm": format!("confirm {} hash:{} (cancel)", confirmation_id, hash)
            }
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: one-step native transfer (build -> preflight -> sign -> send). Amount is in ETH (18 decimals).")]
    async fn evm_execute_transfer_native(
        &self,
        Parameters(request): Parameters<EvmExecuteTransferNativeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let amount_wei = ethers::utils::parse_units(&request.amount, 18).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid amount (expected ETH units): {}", e)),
            data: None,
        })?;

        let tx_request = ethers::types::TransactionRequest {
            from: Some(Self::parse_evm_address(&request.sender)?),
            to: Some(ethers::types::NameOrAddress::Address(Self::parse_evm_address(
                &request.recipient,
            )?)),
            value: Some(amount_wei.into()),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        self.evm_execute_tx_request(chain_id, tx_request, false).await
    }
