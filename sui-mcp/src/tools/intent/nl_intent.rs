    /// Interpret natural language intent into tool calls
    #[tool(description = "Interpret natural language intent into tool calls")]
    async fn interpret_intent(
        &self,
        Parameters(request): Parameters<IntentRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let text = request.text.clone();
        let lower = text.to_lowercase();
        let sender = request.sender.clone().unwrap_or_else(|| "<sender>".to_string());
        let network = request.network.clone();

        let (intent, action, entities, confidence, plan) =
            Self::parse_intent_plan(&text, &lower, sender, network.clone());
        let pipeline = Self::tool_plan_to_pipeline(&plan);

        let response = Self::pretty_json(&json!({
            "text": request.text,
            "intent": intent,
            "action": action,
            "confidence": confidence,
            "entities": entities,
            "tool_plan": plan,
            "pipeline": pipeline,
            "notes": "Fill <...> placeholders using generate_move_call_payload before executing."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute an intent with optional zkLogin inputs
    #[tool(description = "Execute an intent using provided overrides (supports zkLogin)")]
    async fn execute_intent(
        &self,
        Parameters(request): Parameters<IntentExecuteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let text = request.text.clone();
        let lower = text.to_lowercase();
        let sender = request.sender.clone();
        let network = request.network.clone();
        let (intent, _action, entities, _confidence, _plan) =
            Self::parse_intent_plan(&text, &lower, sender.clone(), network.clone());

        let amount = request.amount.or_else(|| entities.get("amount_u64").and_then(|v| v.as_u64()));
        let recipient = request
            .recipient
            .or_else(|| entities.get("recipient").and_then(|v| v.as_str().map(|s| s.to_string())));
        let validator = request
            .validator
            .or_else(|| entities.get("validator").and_then(|v| v.as_str().map(|s| s.to_string())));
        let object_id = request
            .object_id
            .or_else(|| entities.get("object_id").and_then(|v| v.as_str().map(|s| s.to_string())));
        let staked_sui = request
            .staked_sui
            .or_else(|| entities.get("staked_sui").and_then(|v| v.as_str().map(|s| s.to_string())));

        let gas_budget = request.gas_budget.unwrap_or(1_000_000);

        // Network routing: humans can say "Base", "Ethereum", "BSC", etc.
        let resolved_network = Self::resolve_intent_network(network.clone(), &lower);
        let family = resolved_network
            .get("family")
            .and_then(Value::as_str)
            .unwrap_or("sui");
        let chain_id = resolved_network.get("chain_id").and_then(Value::as_u64);

        match intent.as_str() {
            "get_reference_gas_price" => {
                Self::ensure_sui_intent_family(&resolved_network, "get_reference_gas_price")?;
                let result = self.get_reference_gas_price().await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "get_chain_identifier" => {
                Self::ensure_sui_intent_family(&resolved_network, "get_chain_identifier")?;
                let result = self.get_chain_identifier().await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "get_protocol_config" => {
                Self::ensure_sui_intent_family(&resolved_network, "get_protocol_config")?;
                let result = self.get_protocol_config().await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "get_latest_checkpoint_sequence" => {
                Self::ensure_sui_intent_family(&resolved_network, "get_latest_checkpoint_sequence")?;
                let result = self.get_latest_checkpoint_sequence().await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "get_total_transactions" => {
                Self::ensure_sui_intent_family(&resolved_network, "get_total_transactions")?;
                let result = self.get_total_transactions().await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "swap" => {
                // EVM swap uses 0x Swap API (safe: dry-run only). Sui swap not implemented.
                if family != "evm" {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("swap intent is currently only supported on EVM via 0x"),
                        data: None,
                    });
                }

                let chain_id = chain_id.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("chain_id is required for EVM swap"),
                    data: None,
                })?;

                let sender = sender;
                if sender.starts_with('<') {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("sender is required for EVM swap"),
                        data: None,
                    });
                }

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

                if sell.starts_with('<') || buy.starts_with('<') {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "swap requires two tokens in the prompt, e.g. 'swap 0.1 eth to usdc on base'",
                        ),
                        data: None,
                    });
                }

                let amount = entities
                    .get("amount")
                    .and_then(Value::as_str)
                    .unwrap_or("<amount>")
                    .to_string();
                let amount_for_swap = amount.clone();

                if amount.starts_with('<') {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("swap requires an amount, e.g. 'swap 0.1 eth to usdc on base'"),
                        data: None,
                    });
                }

                // Slippage (tolerant default): 1%
                let slippage = Self::extract_slippage_percent(&lower).or_else(|| Some("1%".to_string()));

                // 1) Build swap tx via 0x.
                let built = self
                    .evm_0x_build_swap_tx(Parameters(Evm0xBuildSwapTxRequest {
                        chain_id,
                        sender: sender.clone(),
                        sell_token: sell,
                        buy_token: buy,
                        sell_amount: amount_for_swap,
                        sell_amount_is_wei: Some(false),
                        slippage,
                        exact_approve: Some(true),
                    }))
                    .await?;

                let built_json = Self::extract_first_json(&built).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse 0x build response"),
                    data: None,
                })?;
                let tx: EvmTxRequest = serde_json::from_value(
                    built_json.get("tx").cloned().unwrap_or(Value::Null),
                )
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to decode built tx: {}", e)),
                    data: None,
                })?;

                // 2) Preflight.
                let preflight = self
                    .evm_preflight(Parameters(EvmPreflightRequest { tx }))
                    .await?;
                let preflight_json = Self::extract_first_json(&preflight).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse evm_preflight response"),
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

                // 3) Store pending confirmation.
                let confirmation_id = Self::evm_next_confirmation_id();
                let now_ms = crate::utils::evm_confirm_store::now_ms();
                let ttl_ms = crate::utils::evm_confirm_store::default_ttl_ms();
                let expires_at_ms = now_ms + ttl_ms;
                let tx_summary_hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx);

                crate::utils::evm_confirm_store::insert_pending(
                    &confirmation_id,
                    &tx,
                    now_ms,
                    expires_at_ms,
                    &tx_summary_hash,
                )?;

                // If 0x indicates an allowanceTarget, we likely need to approve before swapping.
                let allowance_target = built_json
                    .get("allowance_target")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
                let sell_token_address = built_json
                    .get("sell_token_address")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
                let suggested_approve_tx = built_json.get("suggested_approve_tx").cloned();

                // Check current allowance and only prompt approve if needed.
                let mut allowance_info: Option<Value> = None;
                let mut approve_flow: Option<Value> = None;

                if let (Some(token_addr), Some(spender)) = (sell_token_address.clone(), allowance_target.clone()) {
                    if token_addr != "ETH" {
                        // Get current allowance
                        let allowance_res = self
                            .evm_erc20_allowance(Parameters(EvmErc20AllowanceRequest {
                                token: token_addr.clone(),
                                owner: sender.clone(),
                                spender: spender.clone(),
                                chain_id: Some(chain_id),
                            }))
                            .await?;
                        let allowance_json = Self::extract_first_json(&allowance_res).unwrap_or(json!({}));
                        allowance_info = Some(allowance_json.clone());

                        let allowance_raw = allowance_json
                            .get("allowance_raw")
                            .and_then(Value::as_str)
                            .and_then(|s| ethers::types::U256::from_dec_str(s).ok())
                            .unwrap_or_else(|| ethers::types::U256::from(0));

                        // Prefer 0x quote's exact sellAmount if present, otherwise fall back to our parser.
                        let sell_amount_wei = if let Some(s) = built_json
                            .get("quote")
                            .and_then(|q| q.get("sellAmount"))
                            .and_then(Value::as_str)
                        {
                            ethers::types::U256::from_dec_str(s)
                                .ok()
                                .unwrap_or_else(|| ethers::types::U256::from(0))
                        } else {
                            let sell_amount_res = self
                                .evm_parse_amount(Parameters(EvmParseAmountRequest {
                                    chain_id,
                                    amount: amount.clone(),
                                    symbol: None,
                                    token_address: Some(token_addr.clone()),
                                    decimals: None,
                                }))
                                .await;

                            sell_amount_res
                                .ok()
                                .and_then(|r| Self::extract_first_json(&r))
                                .and_then(|j| j.get("amount_wei").and_then(Value::as_str).map(|s| s.to_string()))
                                .and_then(|s| ethers::types::U256::from_dec_str(&s).ok())
                                .unwrap_or_else(|| ethers::types::U256::from(0))
                        };

                        // Store metadata so confirm-time can block swap if allowance is still insufficient.
                        let _ = crate::utils::evm_confirm_store::set_expected_allowance(
                            &confirmation_id,
                            &token_addr,
                            &spender,
                            &sell_amount_wei.to_string(),
                        );

                        let needs_approve = sell_amount_wei > ethers::types::U256::from(0)
                            && allowance_raw < sell_amount_wei;

                        // If we have a suggested approve tx and approve is needed, preflight it and create its own confirmation.
                        if needs_approve {
                            if let Some(stx) = suggested_approve_tx.clone() {
                                if let Ok(approve_tx) = serde_json::from_value::<EvmTxRequest>(stx.clone()) {
                                    let approve_preflight = self
                                        .evm_preflight(Parameters(EvmPreflightRequest { tx: approve_tx }))
                                        .await?;
                                    let approve_preflight_json = Self::extract_first_json(&approve_preflight)
                                        .ok_or_else(|| ErrorData {
                                            code: ErrorCode(-32603),
                                            message: Cow::from("Failed to parse approve preflight"),
                                            data: None,
                                        })?;
                                    let approve_tx: EvmTxRequest = serde_json::from_value(
                                        approve_preflight_json.get("tx").cloned().unwrap_or(Value::Null),
                                    )
                                    .map_err(|e| ErrorData {
                                        code: ErrorCode(-32603),
                                        message: Cow::from(format!("Failed to decode approve tx: {}", e)),
                                        data: None,
                                    })?;

                                    let approve_confirmation_id = Self::evm_next_confirmation_id();
                                    let approve_hash = crate::utils::evm_confirm_store::tx_summary_hash(&approve_tx);
                                    crate::utils::evm_confirm_store::insert_pending(
                                        &approve_confirmation_id,
                                        &approve_tx,
                                        now_ms,
                                        expires_at_ms,
                                        &approve_hash,
                                    )?;

                                    // Store safety metadata for confirm-time checks.
                                    let _ = crate::utils::evm_confirm_store::set_expected_allowance(
                                        &approve_confirmation_id,
                                        &token_addr,
                                        &spender,
                                        &sell_amount_wei.to_string(),
                                    );

                                    let _ = crate::utils::evm_confirm_store::set_approve_link(
                                        &confirmation_id,
                                        &approve_confirmation_id,
                                    );
                                    let _ = crate::utils::evm_confirm_store::set_swap_link(
                                        &approve_confirmation_id,
                                        &confirmation_id,
                                    );

                                    approve_flow = Some(json!({
                                        "needed": true,
                                        "allowance_raw": allowance_raw.to_string(),
                                        "required_raw": sell_amount_wei.to_string(),
                                        "confirmation_id": approve_confirmation_id,
                                        "expires_in_ms": ttl_ms,
                                        "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&approve_tx),
                                        "tx_summary_hash": approve_hash,
                                        "preflight": approve_preflight_json,
                                        "next": {
                                            "how_to_confirm": format!("confirm {} hash:{} (approve) (and include same network)", approve_confirmation_id, approve_hash)
                                        }
                                    }));
                                }
                            }
                        } else {
                            approve_flow = Some(json!({
                                "needed": false,
                                "allowance_raw": allowance_raw.to_string(),
                                "required_raw": sell_amount_wei.to_string()
                            }));
                        }
                    }
                }

                let response = Self::pretty_json(&json!({
                    "resolved_network": resolved_network,
                    "mode": "dry_run_only",
                    "provider": "0x",
                    "swap": {
                        "confirmation_id": confirmation_id,
                        "expires_in_ms": ttl_ms,
                        "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                        "tx_summary_hash": tx_summary_hash,
                        "preflight": preflight_json,
                        "next": {
                            "how_to_confirm": format!("confirm {} hash:{} (swap) (and include same network)", confirmation_id, tx_summary_hash)
                        }
                    },
                    "approve": approve_flow,
                    "build": built_json,
                    "allowance": {
                        "sell_token_address": sell_token_address,
                        "allowance_target": allowance_target,
                        "current": allowance_info,
                        "suggested_approve_tx": suggested_approve_tx,
                        "note": "If approve.needed=true, confirm approve first, then confirm swap. If approve.needed=false, you can confirm swap directly."
                    },
                    "note": "Safe default: not signed/broadcast. Confirm to execute." 
                }))?;

                return Ok(CallToolResult::success(vec![Content::text(response)]));
            }
            "get_coins" => {
                if family == "evm" {
                    let chain_id = chain_id.ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("chain_id is required for EVM get_coins"),
                        data: None,
                    })?;

                    // For EVM, map common coin words to ERC20s.
                    // Supports USDC (Circle defaults) and USDT (partial defaults + env overrides).
                    let token_address = if lower.contains("usdc") {
                        Self::resolve_evm_erc20_address("usdc", chain_id)
                    } else if lower.contains("usdt") {
                        Self::resolve_evm_erc20_address("usdt", chain_id)
                    } else {
                        None
                    }
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Unsupported EVM coin query. Try: 'balance usdc on Base' or 'balance token 0xYourToken on Base' or set EVM_USDC_ADDRESS_<chain_id> / EVM_USDT_ADDRESS_<chain_id>",
                        ),
                        data: None,
                    })?;

                    let result = self
                        .evm_get_balance(Parameters(EvmGetBalanceRequest {
                            address: sender,
                            chain_id: Some(chain_id),
                            token_address: Some(token_address),
                        }))
                        .await?;

                    return Self::wrap_resolved_network_result(&resolved_network, &result);
                }

                Self::ensure_sui_intent_family(&resolved_network, "get_coins")?;

                let coin_type = entities
                    .get("coin_type")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());

                let result = self
                    .get_coins(Parameters(GetCoinsRequest {
                        address: sender,
                        coin_type,
                        limit: Some(50),
                    }))
                    .await?;

                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "query_transaction_events" => {
                Self::ensure_sui_intent_family(&resolved_network, "query_transaction_events")?;

                let digest = entities
                    .get("digest")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("digest is required for query_transaction_events"),
                        data: None,
                    })?;

                if digest.starts_with('<') {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "digest is required for query_transaction_events (provide a tx digest)",
                        ),
                        data: None,
                    });
                }

                let result = self
                    .query_transaction_events(Parameters(QueryEventsRequest {
                        digest: digest.to_string(),
                    }))
                    .await?;

                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "evm_get_gas_price" => {
                let result = self
                    .evm_get_gas_price(Parameters(EvmGetGasPriceRequest { chain_id }))
                    .await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "evm_get_transaction_receipt" => {
                let tx_hash = entities
                    .get("tx_hash")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("tx_hash is required for evm_get_transaction_receipt"),
                        data: None,
                    })?;

                let result = self
                    .evm_get_transaction_receipt(Parameters(EvmGetTransactionReceiptRequest {
                        tx_hash: tx_hash.to_string(),
                        chain_id,
                        include_receipt: Some(false),
                        decoded_logs_limit: None,
                        only_addresses: None,
                        only_topics0: None,
                    }))
                    .await?;
                return Self::wrap_resolved_network_result(&resolved_network, &result);
            }
            "evm_confirm_execution" => {
                let chain_id = chain_id.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("chain_id is required for confirm"),
                    data: None,
                })?;

                let id = crate::utils::evm_confirm_store::extract_confirmation_id(&text)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Missing confirmation id. Paste the evm_dryrun_<...> id from the previous dry-run response.",
                        ),
                        data: None,
                    })?;

                let provided_hash = crate::utils::evm_confirm_store::extract_tx_summary_hash(&text)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Missing tx_summary_hash. Send: confirm <confirmation_id> hash:<tx_summary_hash>",
                        ),
                        data: None,
                    })?;

                let conn = crate::utils::evm_confirm_store::connect()?;
                crate::utils::evm_confirm_store::cleanup_expired(
                    &conn,
                    crate::utils::evm_confirm_store::now_ms(),
                )?;

                let row = crate::utils::evm_confirm_store::get_row(&conn, &id)?.ok_or_else(|| {
                    ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Unknown/expired confirmation id (not found). Run the dry-run again to regenerate.",
                        ),
                        data: None,
                    }
                })?;

                if row.chain_id != chain_id {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Confirmation chain_id mismatch: stored={} current={}",
                            row.chain_id, chain_id
                        )),
                        data: None,
                    });
                }

                if crate::utils::evm_confirm_store::now_ms() > row.expires_at_ms {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Confirmation id has expired. Run the dry-run again to regenerate.",
                        ),
                        data: None,
                    });
                }

                // Status handling.
                if row.status == "sent" {
                    let response = Self::pretty_json(&json!({
                        "resolved_network": resolved_network,
                        "status": "sent",
                        "confirmation_id": id,
                        "tx_hash": row.tx_hash,
                        "note": "Already broadcast (recorded in sqlite)"
                    }))?;
                    return Ok(CallToolResult::success(vec![Content::text(response)]));
                }

                if row.tx_summary_hash.to_lowercase() != provided_hash {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "tx_summary_hash mismatch. expected={} got={}",
                            row.tx_summary_hash, provided_hash
                        )),
                        data: None,
                    });
                }

                let mut tx = row.tx;

                // Re-preflight at confirm time (nonce/fees may have changed since dry-run).
                let preflight = self
                    .evm_preflight(Parameters(EvmPreflightRequest { tx }))
                    .await?;
                let preflight_json = Self::extract_first_json(&preflight).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse evm_preflight response during confirm"),
                    data: None,
                })?;
                tx = serde_json::from_value(preflight_json.get("tx").cloned().unwrap_or(Value::Null))
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to decode preflight tx during confirm: {}", e)),
                        data: None,
                    })?;

                let new_hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx);
                if new_hash != provided_hash {
                    let new_expires = crate::utils::evm_confirm_store::now_ms()
                        + crate::utils::evm_confirm_store::default_ttl_ms();
                    crate::utils::evm_confirm_store::update_pending(
                        &conn,
                        &id,
                        &tx,
                        new_expires,
                        &new_hash,
                    )?;

                    let response = Self::pretty_json(&json!({
                        "resolved_network": resolved_network,
                        "status": "pending",
                        "confirmation_id": id,
                        "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                        "tx_summary_hash": new_hash,
                        "note": "Tx changed during confirm-time preflight (likely nonce/fees). Re-confirm with new hash." 
                    }))?;
                    return Ok(CallToolResult::success(vec![Content::text(response)]));
                }

                // For swap (and other non-approve tx): if we have expected allowance metadata, block execution unless allowance is sufficient.
                // This prevents "swap before approve" failures.
                if let Some(expected_token) = row.expected_token.as_deref() {
                    // Skip if this is an approve() tx (handled separately above).
                    let is_approve = tx
                        .data_hex
                        .as_deref()
                        .map(|d| d.strip_prefix("0x").unwrap_or(d))
                        .map(|h| h.len() >= 8 && h[..8].eq_ignore_ascii_case("095ea7b3"))
                        .unwrap_or(false);

                    if !is_approve {
                        if let (Some(spender), Some(required_raw)) = (
                            row.expected_spender.as_deref(),
                            row.required_allowance_raw.as_deref(),
                        ) {
                            let required = ethers::types::U256::from_dec_str(required_raw)
                                .unwrap_or_else(|_| ethers::types::U256::from(0));

                            if required > ethers::types::U256::from(0) {
                                let allowance_res = self
                                    .evm_erc20_allowance(Parameters(EvmErc20AllowanceRequest {
                                        token: expected_token.to_string(),
                                        owner: tx.from.clone(),
                                        spender: spender.to_string(),
                                        chain_id: Some(chain_id),
                                    }))
                                    .await?;
                                let allowance_json =
                                    Self::extract_first_json(&allowance_res).unwrap_or(json!({}));
                                let allowance_raw = allowance_json
                                    .get("allowance_raw")
                                    .and_then(Value::as_str)
                                    .and_then(|s| ethers::types::U256::from_dec_str(s).ok())
                                    .unwrap_or_else(|| ethers::types::U256::from(0));

                                if allowance_raw < required {
                                    let mut approve_status: Option<String> = None;

                                    let mut data = json!({
                                        "status": "pending",
                                        "reason": "allowance_insufficient",
                                        "token": expected_token,
                                        "spender": spender,
                                        "allowance_raw": allowance_raw.to_string(),
                                        "required_raw": required.to_string(),
                                        "approve_confirmation_id": row.approve_confirmation_id,
                                    });

                                    // If we know the approve confirmation, add its status/tx_hash to improve UX.
                                    if let Some(approve_id) = row.approve_confirmation_id.as_deref() {
                                        if let Ok(Some(approve_row)) =
                                            crate::utils::evm_confirm_store::get_row(&conn, approve_id)
                                        {
                                            approve_status = Some(approve_row.status.clone());
                                            if let Value::Object(ref mut m) = data {
                                                m.insert(
                                                    "approve_status".to_string(),
                                                    Value::String(approve_row.status.clone()),
                                                );
                                                if let Some(h) = approve_row.tx_hash.clone() {
                                                    m.insert("approve_tx_hash".to_string(), Value::String(h));
                                                }
                                            }
                                        }
                                    }

                                    let d = crate::utils::evm_confirm_ux::allowance_insufficient_decision(
                                        &allowance_raw.to_string(),
                                        &required.to_string(),
                                        approve_status.as_deref(),
                                    );
                                    if let Value::Object(ref mut m) = data {
                                        m.insert("note".to_string(), Value::String(d.note.clone()));
                                    }

                                    // Normalize decision label to help UIs display a crisp state.
                                    let decision_label = if matches!(
                                        d.action,
                                        crate::utils::evm_confirm_ux::AllowanceConfirmAction::WaitForApproveMined
                                    ) {
                                        "approve_sent_wait"
                                    } else {
                                        "confirm_approve_first"
                                    };

                                    crate::utils::evm_confirm_ux::attach_web3mcp_debug(
                                        &mut data,
                                        json!({
                                            "decision": "allowance_insufficient",
                                            "decision_label": decision_label,
                                            "action": format!("{:?}", d.action),
                                            "approve_status": approve_status,
                                        }),
                                    );

                                    self.write_audit_log(
                                        "evm_confirm_execution",
                                        json!({
                                            "event": "blocked",
                                            "reason": "allowance_insufficient",
                                            "decision_label": decision_label,
                                            "confirmation_id": id,
                                            "token": expected_token,
                                            "spender": spender,
                                            "allowance_raw": allowance_raw.to_string(),
                                            "required_raw": required.to_string(),
                                            "approve_confirmation_id": row.approve_confirmation_id,
                                            "approve_status": approve_status,
                                        }),
                                    );

                                    return Err(ErrorData {
                                        code: ErrorCode(-32602),
                                        message: Cow::from(d.message),
                                        data: Some(data),
                                    });
                                }
                            }
                        }
                    }
                }

                // Large-value double confirmation (requires token:...)
                if let Some((_token, msg)) = crate::utils::evm_confirm_store::ensure_second_confirmation(
                    &conn,
                    &id,
                    &provided_hash,
                    &text,
                    &tx,
                )? {
                    let response = Self::pretty_json(&json!({
                        "resolved_network": resolved_network,
                        "status": "pending",
                        "confirmation_id": id,
                        "tx_summary": crate::utils::evm_confirm_store::tx_summary_for_response(&tx),
                        "tx_summary_hash": provided_hash,
                        "note": "Second confirmation required for large-value tx",
                        "next": { "how_to_confirm": msg }
                    }))?;
                    return Ok(CallToolResult::success(vec![Content::text(response)]));
                }

                // Strong approve safety checks: prevent approving wrong spender; skip if allowance already sufficient.
                if let Some(data_hex) = tx.data_hex.as_deref() {
                    if let Some((spender, amount_u256)) =
                        crate::utils::evm_calldata::decode_erc20_approve(data_hex)
                    {
                        let token_addr = tx.to.clone();

                        // If we have expected spender metadata, enforce it.
                        if let Some(expected) = row.expected_spender.as_deref() {
                            if !expected.eq_ignore_ascii_case(&spender) {
                                let _ = crate::utils::evm_confirm_store::mark_failed(
                                    &conn,
                                    &id,
                                    &format!(
                                        "approve spender mismatch: expected={} got={}",
                                        expected, spender
                                    ),
                                );
                                let mut data = json!({
                                    "status": "failed",
                                    "reason": "approve_spender_mismatch",
                                    "expected_spender": expected,
                                    "got_spender": spender,
                                });
                                crate::utils::evm_confirm_ux::attach_web3mcp_debug(
                                    &mut data,
                                    json!({
                                        "decision": "approve_spender_mismatch",
                                        "decision_label": "approve_spender_mismatch",
                                        "expected_spender": expected,
                                        "got_spender": spender,
                                    }),
                                );

                                // Audit
                                self.write_audit_log(
                                    "evm_confirm_execution",
                                    json!({
                                        "event": "blocked",
                                        "reason": "approve_spender_mismatch",
                                        "confirmation_id": id,
                                        "expected_spender": expected,
                                        "got_spender": spender,
                                    }),
                                );

                                return Err(ErrorData {
                                    code: ErrorCode(-32602),
                                    message: Cow::from(format!(
                                        "Approve spender mismatch: expected {} but tx approves {}",
                                        expected, spender
                                    )),
                                    data: Some(data),
                                });
                            }
                        }

                        // If the approve amount is smaller than what the flow requires, block (prevents stale/incorrect approve).
                        if let Some(required_raw) = row.required_allowance_raw.as_deref() {
                            if let Ok(required_u256) = ethers::types::U256::from_dec_str(required_raw) {
                                if required_u256 > ethers::types::U256::from(0) && amount_u256 < required_u256 {
                                    let _ = crate::utils::evm_confirm_store::mark_failed(
                                        &conn,
                                        &id,
                                        &format!(
                                            "approve amount too small: tx={} required={}",
                                            amount_u256, required_u256
                                        ),
                                    );
                                    let mut data = json!({
                                        "status": "failed",
                                        "reason": "approve_amount_too_small",
                                        "approve_amount_raw": amount_u256.to_string(),
                                        "required_raw": required_u256.to_string(),
                                    });
                                    crate::utils::evm_confirm_ux::attach_web3mcp_debug(
                                        &mut data,
                                        json!({
                                            "decision": "approve_amount_too_small",
                                            "decision_label": "approve_amount_too_small",
                                            "approve_amount_raw": amount_u256.to_string(),
                                            "required_raw": required_u256.to_string(),
                                        }),
                                    );

                                    self.write_audit_log(
                                        "evm_confirm_execution",
                                        json!({
                                            "event": "blocked",
                                            "reason": "approve_amount_too_small",
                                            "confirmation_id": id,
                                            "approve_amount_raw": amount_u256.to_string(),
                                            "required_raw": required_u256.to_string(),
                                        }),
                                    );

                                    return Err(ErrorData {
                                        code: ErrorCode(-32602),
                                        message: Cow::from(format!(
                                            "Approve amount too small ({} < {}). Please rebuild approve.",
                                            amount_u256, required_u256
                                        )),
                                        data: Some(data),
                                    });
                                }
                            }
                        }

                        // If allowance already >= required, skip this approve.
                        let required = row
                            .required_allowance_raw
                            .as_deref()
                            .and_then(|s| ethers::types::U256::from_dec_str(s).ok())
                            .unwrap_or(amount_u256);

                        let allowance_res = self
                            .evm_erc20_allowance(Parameters(EvmErc20AllowanceRequest {
                                token: token_addr.clone(),
                                owner: tx.from.clone(),
                                spender: spender.clone(),
                                chain_id: Some(chain_id),
                            }))
                            .await?;
                        let allowance_json = Self::extract_first_json(&allowance_res).unwrap_or(json!({}));
                        let allowance_raw = allowance_json
                            .get("allowance_raw")
                            .and_then(Value::as_str)
                            .and_then(|s| ethers::types::U256::from_dec_str(s).ok())
                            .unwrap_or_else(|| ethers::types::U256::from(0));

                        if allowance_raw >= required {
                            let reason = format!(
                                "approve skipped: allowance {} >= required {}",
                                allowance_raw, required
                            );
                            let _ = crate::utils::evm_confirm_store::mark_skipped(&conn, &id, &reason);

                            let mut resp = json!({
                                "resolved_network": resolved_network,
                                "status": "skipped",
                                "confirmation_id": id,
                                "note": "Allowance already sufficient; approve not needed",
                                "allowance_raw": allowance_raw.to_string(),
                                "required_raw": required.to_string(),
                                "spender": spender,
                                "token": token_addr
                            });
                            crate::utils::evm_confirm_ux::attach_web3mcp_debug(
                                &mut resp,
                                json!({
                                    "decision": "approve_skipped",
                                    "decision_label": "approve_skipped",
                                    "allowance_raw": allowance_raw.to_string(),
                                    "required_raw": required.to_string(),
                                }),
                            );

                            self.write_audit_log(
                                "evm_confirm_execution",
                                json!({
                                    "event": "skipped",
                                    "reason": "allowance_sufficient",
                                    "confirmation_id": id,
                                    "allowance_raw": allowance_raw.to_string(),
                                    "required_raw": required.to_string(),
                                    "spender": spender,
                                    "token": token_addr,
                                }),
                            );


                            // If this approve is linked to a swap, provide the next confirm command.
                            if let Some(swap_id) = row.swap_confirmation_id.as_deref() {
                                if let Ok(Some(swap_row)) =
                                    crate::utils::evm_confirm_store::get_row(&conn, swap_id)
                                {
                                    if let Value::Object(ref mut m) = resp {
                                        m.insert(
                                            "swap_confirmation_id".to_string(),
                                            Value::String(swap_id.to_string()),
                                        );
                                        m.insert(
                                            "next".to_string(),
                                            json!({
                                                "how_to_confirm_swap": format!(
                                                    "confirm {} hash:{} (swap)",
                                                    swap_id, swap_row.tx_summary_hash
                                                )
                                            }),
                                        );
                                    }
                                }
                            }

                            let response = Self::pretty_json(&resp)?;
                            return Ok(CallToolResult::success(vec![Content::text(response)]));
                        }
                    }
                }

                // Mark as consumed (atomic-ish): we keep the row, but status changes.
                crate::utils::evm_confirm_store::mark_consumed(&conn, &id)?;

                let signed = self
                    .evm_sign_transaction_local(Parameters(EvmSignLocalRequest {
                        tx,
                        allow_sender_mismatch: Some(false),
                    }))
                    .await?;

                let signed_json = Self::extract_first_json(&signed).ok_or_else(|| ErrorData {
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

                // Record signed prefix for observability (option C: no full raw_tx stored).
                let _ = crate::utils::evm_confirm_store::mark_signed(&conn, &id, &raw_tx);

                let sent = self
                    .evm_send_raw_transaction(Parameters(EvmSendRawTransactionRequest {
                        chain_id: Some(chain_id),
                        raw_tx,
                    }))
                    .await;

                match sent {
                    Ok(ok) => {
                        if let Some(v) = Self::extract_first_json(&ok) {
                            if let Some(tx_hash) = v.get("tx_hash").and_then(Value::as_str) {
                                let _ = crate::utils::evm_confirm_store::mark_sent(&conn, &id, tx_hash);
                            }
                        }
                        return Self::wrap_resolved_network_result(&resolved_network, &ok);
                    }
                    Err(e) => {
                        let _ = crate::utils::evm_confirm_store::mark_failed(&conn, &id, &e.message);
                        return Err(e);
                    }
                }
            }
            "evm_contract_dry_run" => {
                let chain_id = chain_id.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("chain_id is required for EVM contract calls"),
                    data: None,
                })?;

                let sender = sender;
                if sender.starts_with('<') {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("sender is required for EVM contract calls"),
                        data: None,
                    });
                }

                let contract_query = entities
                    .get("contract_query")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string())
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "Missing contract identifier. Say e.g. 'call balanceOf on usdc on Base' or provide a contract 0x... address.",
                        ),
                        data: None,
                    })?;

                let function_hint = entities
                    .get("function_hint")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());

                // 1) Plan.
                let planned = self
                    .evm_plan_contract_call(Parameters(EvmPlanContractCallRequest {
                        chain_id,
                        address: None,
                        contract_name: None,
                        contract_query: Some(contract_query.clone()),
                        accept_best_match: Some(true),
                        text: text.clone(),
                        function_hint,
                        limit: Some(5),
                    }))
                    .await?;

                let planned_json = Self::extract_first_json(&planned).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse evm_plan_contract_call response"),
                    data: None,
                })?;

                let top = planned_json
                    .get("candidates")
                    .and_then(Value::as_array)
                    .and_then(|arr| arr.first())
                    .cloned()
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("No candidates returned by evm_plan_contract_call"),
                        data: None,
                    })?;

                let signature = top
                    .get("signature")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("Missing signature in plan candidate"),
                        data: None,
                    })?
                    .to_string();

                let mut filled_args = top.get("filled_args").cloned().unwrap_or(json!([]));
                let missing = top
                    .get("missing")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();

                // Tolerant mode: try to auto-convert obvious amount strings (e.g. "1.5" with usdc/usdt/eth in text)
                // into uint256 wei-like strings before building.
                if let Value::Array(ref mut arr) = filled_args {
                    // If user provided a token/contract/erc20 address in the prompt, prefer it.
                    let token_addr = if lower.contains("token")
                        || lower.contains("contract")
                        || lower.contains("erc20")
                    {
                        let addrs = entities
                            .get("addresses")
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default()
                            .into_iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect::<Vec<_>>();
                        Self::infer_evm_token_address_from_text(&lower, &addrs)
                    } else {
                        None
                    };

                    // infer a symbol from the overall text
                    let sym = if lower.contains("usdc") {
                        Some("usdc".to_string())
                    } else if lower.contains("usdt") {
                        Some("usdt".to_string())
                    } else if lower.contains("weth") {
                        Some("weth".to_string())
                    } else if lower.contains("dai") {
                        Some("dai".to_string())
                    } else if lower.contains("cbeth") {
                        Some("cbeth".to_string())
                    } else if lower.contains("eth") {
                        Some("eth".to_string())
                    } else {
                        None
                    };

                    for v in arr.iter_mut() {
                        if let Value::String(s) = v {
                            let s_trim = s.trim();
                            // only attempt if it looks like a number or a "<num> <sym>" pair
                            if s_trim.chars().any(|c| c.is_ascii_digit()) && !s_trim.starts_with("0x") {
                                if let Ok(result) = self
                                    .evm_parse_amount(Parameters(EvmParseAmountRequest {
                                        chain_id,
                                        amount: s_trim.to_string(),
                                        symbol: sym.clone(),
                                        token_address: token_addr.clone(),
                                        decimals: None,
                                    }))
                                    .await
                                {
                                    if let Some(j) = Self::extract_first_json(&result) {
                                        if let Some(w) = j.get("amount_wei").and_then(Value::as_str) {
                                            *v = Value::String(w.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // If there are missing args, stop here (safe by default).
                if !missing.is_empty() {
                    let response = Self::pretty_json(&json!({
                        "resolved_network": resolved_network,
                        "mode": "dry_run_only",
                        "plan": planned_json,
                        "selected": {
                            "function_signature": signature,
                            "filled_args": filled_args,
                            "missing": missing
                        },
                        "next": {
                            "how": "Provide the missing args, then call evm_build_contract_tx (or evm_execute_contract_call with dry_run_only=true)",
                            "suggested_build": {
                                "chain_id": chain_id,
                                "sender": sender,
                                "contract_query": contract_query,
                                "accept_best_match": true,
                                "function": top.get("function"),
                                "function_signature": signature,
                                "args": filled_args
                            }
                        }
                    }))?;
                    return Ok(CallToolResult::success(vec![Content::text(response)]));
                }

                // 2) Build.
                let built = self
                    .evm_build_contract_tx(Parameters(EvmBuildContractTxRequest {
                        chain_id,
                        sender: sender.clone(),
                        address: None,
                        contract_name: None,
                        contract_query: Some(contract_query),
                        accept_best_match: Some(true),
                        function: top
                            .get("function")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string(),
                        function_signature: Some(signature),
                        args: Some(filled_args),
                        value_wei: None,
                        gas_limit: None,
                    }))
                    .await?;

                let built_json = Self::extract_first_json(&built).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse evm_build_contract_tx response"),
                    data: None,
                })?;
                let tx: EvmTxRequest = serde_json::from_value(
                    built_json.get("tx").cloned().unwrap_or(Value::Null),
                )
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to decode built tx: {}", e)),
                    data: None,
                })?;

                // 3) Preflight.
                let preflight = self
                    .evm_preflight(Parameters(EvmPreflightRequest { tx }))
                    .await?;
                let preflight_json = Self::extract_first_json(&preflight).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse evm_preflight response"),
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

                let confirmation_id = Self::evm_next_confirmation_id();
                let now_ms = crate::utils::evm_confirm_store::now_ms();
                let ttl_ms = crate::utils::evm_confirm_store::default_ttl_ms();
                let expires_at_ms = now_ms + ttl_ms;

                let tx_summary_hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx);
                crate::utils::evm_confirm_store::insert_pending(
                    &confirmation_id,
                    &tx,
                    now_ms,
                    expires_at_ms,
                    &tx_summary_hash,
                )?;

                // Human-friendly summary for quick review.
                let tx_summary = crate::utils::evm_confirm_store::tx_summary_for_response(&tx);

                let tx_summary_hash = crate::utils::evm_confirm_store::tx_summary_hash(&tx);

                let response = Self::pretty_json(&json!({
                    "resolved_network": resolved_network,
                    "mode": "dry_run_only",
                    "confirmation_id": confirmation_id,
                    "expires_in_ms": ttl_ms,
                    "tx_summary": tx_summary,
                    "tx_summary_hash": tx_summary_hash,
                    "plan": planned_json,
                    "build": built_json,
                    "preflight": preflight_json,
                    "next": {
                        "how_to_confirm": "Send: confirm <confirmation_id> hash:<tx_summary_hash> (and include the same network like 'on Base')",
                        "warning": "Confirm step will SIGN+BROADCAST using EVM_PRIVATE_KEY",
                        "expires_in_ms": ttl_ms
                    },
                    "note": "Safe default: not signed or broadcast. Confirmation is required to execute." 
                }))?;
                return Ok(CallToolResult::success(vec![Content::text(response)]));
            }
            "get_balance" => {
                if family == "evm" {
                    let result = self
                        .evm_get_balance(Parameters(EvmGetBalanceRequest {
                            address: sender,
                            chain_id,
                            token_address: None,
                        }))
                        .await?;

                    return Self::wrap_resolved_network_result(&resolved_network, &result);
                }

                let result = self
                    .get_balance(Parameters(GetBalanceRequest {
                        address: sender,
                        coin_type: None,
                    }))
                    .await?;

                Self::wrap_resolved_network_result(&resolved_network, &result)
            }
            "transfer" => {
                if family == "evm" {
                    let recipient = recipient.ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("recipient is required for EVM transfer"),
                        data: None,
                    })?;

                    // Humans specify ETH units (e.g. 0.001), not wei.
                    let amount_str = entities
                        .get("amount")
                        .and_then(Value::as_str)
                        .ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from(
                                "amount is required for EVM transfer (e.g. 'send 0.01 ETH to 0x... on Base')",
                            ),
                            data: None,
                        })?
                        .to_string();

                    // Use the one-step tool to reduce duplication and keep execution stable.
                    let result = self
                        .evm_execute_transfer_native(Parameters(EvmExecuteTransferNativeRequest {
                            sender: sender.clone(),
                            recipient: recipient.clone(),
                            amount: amount_str,
                            chain_id,
                            gas_limit: None,
                            confirm_large_transfer: Some(false),
                            large_transfer_threshold_wei: None,
                        }))
                        .await?;

                    return Self::wrap_resolved_network_result(&resolved_network, &result);
                }

                // Sui default (zkLogin flow)
                let recipient = recipient.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("recipient is required for transfer"),
                    data: None,
                })?;
                let input_coins = request.input_coins.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("input_coins is required for transfer"),
                    data: None,
                })?;
                let tx = self
                    .build_transfer_sui_intent_tx(
                        sender.clone(),
                        recipient,
                        input_coins,
                        amount,
                        gas_budget,
                    )
                    .await?;
                let exec = self
                    .execute_zklogin_from_builder_result(
                        tx,
                        request.zk_login_inputs_json.clone(),
                        request.address_seed.clone(),
                        request.max_epoch,
                        request.user_signature.clone(),
                        "transfer",
                    )
                    .await?;
                return Self::wrap_resolved_network_result(&resolved_network, &exec);
            }
            "transfer_object" => {
                let recipient = recipient.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("recipient is required for transfer object"),
                    data: None,
                })?;
                let object_id = object_id.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("object_id is required for transfer object"),
                    data: None,
                })?;

                let tx = self
                    .build_transfer_object_intent_tx(
                        sender.clone(),
                        object_id,
                        recipient,
                        gas_budget,
                        request.gas_object_id.clone(),
                    )
                    .await?;
                let exec = self
                    .execute_zklogin_from_builder_result(
                        tx,
                        request.zk_login_inputs_json.clone(),
                        request.address_seed.clone(),
                        request.max_epoch,
                        request.user_signature.clone(),
                        "transfer object",
                    )
                    .await?;
                return Self::wrap_resolved_network_result(&resolved_network, &exec);
            }
            "stake" => {
                let validator = validator.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("validator is required for stake"),
                    data: None,
                })?;
                let coins = request.input_coins.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("input_coins is required for stake"),
                    data: None,
                })?;

                let tx = self
                    .build_add_stake_intent_tx(
                        sender.clone(),
                        validator,
                        coins,
                        amount,
                        gas_budget,
                        request.gas_object_id.clone(),
                    )
                    .await?;
                let exec = self
                    .execute_zklogin_from_builder_result(
                        tx,
                        request.zk_login_inputs_json.clone(),
                        request.address_seed.clone(),
                        request.max_epoch,
                        request.user_signature.clone(),
                        "stake",
                    )
                    .await?;

                return Self::wrap_resolved_network_result(&resolved_network, &exec);
            }
            "unstake" => {
                let staked_sui = staked_sui.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("staked_sui is required for withdraw"),
                    data: None,
                })?;

                let tx = self
                    .build_withdraw_stake_intent_tx(
                        sender.clone(),
                        staked_sui,
                        gas_budget,
                        request.gas_object_id.clone(),
                    )
                    .await?;
                let exec = self
                    .execute_zklogin_from_builder_result(
                        tx,
                        request.zk_login_inputs_json.clone(),
                        request.address_seed.clone(),
                        request.max_epoch,
                        request.user_signature.clone(),
                        "withdraw",
                    )
                    .await?;

                return Self::wrap_resolved_network_result(&resolved_network, &exec);
            }
            "mint" | "borrow" | "lend" => {
                let package = request.package.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("package is required for move call intents"),
                    data: None,
                })?;
                let module = request.module.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("module is required for move call intents"),
                    data: None,
                })?;
                let function = request.function.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("function is required for move call intents"),
                    data: None,
                })?;
                let type_args = request.type_args.unwrap_or_default();
                let arguments = request.arguments.unwrap_or_default();

                let exec = self
                    .auto_execute_move_call_filled(Parameters(AutoExecuteMoveCallRequest {
                        sender,
                        package,
                        module,
                        function,
                        type_args,
                        arguments,
                        gas_budget,
                        gas_object_id: request.gas_object_id.clone(),
                        gas_price: request.gas_price,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await?;

                return Self::wrap_resolved_network_result(&resolved_network, &exec);
            }
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Unsupported intent: {}", intent)),
                    data: None,
                })
            }
        }
    }

    fn resolve_intent_network(network: Option<String>, lower: &str) -> Value {
        fn is_test(s: &str) -> bool {
            s.contains("test") || s.contains("testnet") || s.contains("sepolia") || s.contains("amoy") || s.contains("mumbai") || s.contains("alfajores") || s.contains("测试")
        }
        fn is_main(s: &str) -> bool {
            s.contains("mainnet") || s.contains("main") || s.contains("one") || s.contains("主网")
        }
        fn is_dev(s: &str) -> bool {
            s.contains("dev") || s.contains("devnet")
        }

        #[derive(Clone, Copy)]
        struct EvmChainRule {
            keywords: &'static [&'static str],
            name_main: &'static str,
            name_test: &'static str,
            name_dev: Option<&'static str>,
            chain_id_main: u64,
            chain_id_test: Option<u64>,
            chain_id_dev: Option<u64>,
        }

        // Note: keep this list tight and high-signal; first match wins.
        const EVM_RULES: &[EvmChainRule] = &[
            EvmChainRule {
                keywords: &["base"],
                name_main: "base",
                name_test: "base-sepolia",
                name_dev: None,
                chain_id_main: 8453,
                chain_id_test: Some(84532),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["arbitrum", "arb"],
                name_main: "arbitrum",
                name_test: "arbitrum-sepolia",
                name_dev: None,
                chain_id_main: 42161,
                chain_id_test: Some(421614),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["optimism", "op"],
                name_main: "optimism",
                name_test: "op-sepolia",
                name_dev: None,
                chain_id_main: 10,
                chain_id_test: Some(11155420),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["polygon", "matic"],
                name_main: "polygon",
                name_test: "polygon-amoy",
                name_dev: None,
                chain_id_main: 137,
                chain_id_test: Some(80002),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["avax", "avalanche"],
                name_main: "avalanche",
                name_test: "avalanche-fuji",
                name_dev: None,
                chain_id_main: 43114,
                chain_id_test: Some(43113),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["bsc", "bnb"],
                name_main: "bsc",
                name_test: "bsc-testnet",
                name_dev: None,
                chain_id_main: 56,
                chain_id_test: Some(97),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["celo"],
                name_main: "celo",
                name_test: "celo-alfajores",
                name_dev: None,
                chain_id_main: 42220,
                chain_id_test: Some(44787),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["kava"],
                name_main: "kava",
                name_test: "kava-testnet",
                name_dev: None,
                chain_id_main: 2222,
                chain_id_test: Some(2221),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["world chain", "worldchain"],
                name_main: "worldchain",
                name_test: "worldchain-sepolia",
                name_dev: None,
                chain_id_main: 480,
                chain_id_test: Some(4801),
                chain_id_dev: None,
            },
            EvmChainRule {
                keywords: &["monad"],
                name_main: "monad",
                name_test: "monad-testnet",
                name_dev: Some("monad-devnet"),
                chain_id_main: 143,
                chain_id_test: Some(10143),
                chain_id_dev: Some(20143),
            },
            // Kaia: Kairos testnet exists as 1001
            EvmChainRule {
                keywords: &["kaia"],
                name_main: "kaia",
                name_test: "kaia-kairos",
                name_dev: None,
                chain_id_main: 8217,
                chain_id_test: Some(1001),
                chain_id_dev: None,
            },
            // HyperEVM: chainid.network currently lists only testnet=998.
            EvmChainRule {
                keywords: &["hyperevm", "hyper evm", "hyperliquid"],
                name_main: "hyperevm",
                name_test: "hyperevm-testnet",
                name_dev: None,
                chain_id_main: 998,
                chain_id_test: Some(998),
                chain_id_dev: None,
            },
            // Ethereum last (because 'eth' is a substring in lots of words).
            EvmChainRule {
                keywords: &["ethereum", "eth"],
                name_main: "ethereum",
                name_test: "sepolia",
                name_dev: None,
                chain_id_main: 1,
                chain_id_test: Some(11155111),
                chain_id_dev: None,
            },
        ];

        let raw = network.unwrap_or_else(|| "".to_string());
        let key = raw.trim().to_lowercase();

        // If user didn't specify a network, infer from the text.
        let inferred = if key.is_empty() {
            // prefer EVM routing if user mentions any EVM chain keywords
            if EVM_RULES
                .iter()
                .any(|rule| Self::match_any(lower, rule.keywords))
            {
                lower.to_string()
            } else {
                "sui".to_string()
            }
        } else {
            key
        };

        // Sui is the default fallback.
        if inferred.contains("sui") {
            return json!({
                "raw": raw,
                "normalized": "sui",
                "family": "sui",
                "chain_id": null
            });
        }

        if let Some(rule) = EVM_RULES
            .iter()
            .find(|rule| Self::match_any(&inferred, rule.keywords))
        {
            let cid = if is_dev(&inferred) {
                rule.chain_id_dev.or(rule.chain_id_test).unwrap_or(rule.chain_id_main)
            } else if is_test(&inferred) {
                rule.chain_id_test.unwrap_or(rule.chain_id_main)
            } else if is_main(&inferred) {
                rule.chain_id_main
            } else {
                // Safe default: if a test chain_id exists, prefer it; otherwise mainnet.
                rule.chain_id_test.unwrap_or(rule.chain_id_main)
            };

            let name = if Some(cid) == rule.chain_id_dev {
                rule.name_dev.unwrap_or(rule.name_test)
            } else if Some(cid) == rule.chain_id_test {
                rule.name_test
            } else {
                rule.name_main
            };

            return json!({
                "raw": raw,
                "normalized": name,
                "family": "evm",
                "chain_id": cid
            });
        }

        // Final fallback
        json!({
            "raw": raw,
            "normalized": "sui",
            "family": "sui",
            "chain_id": null
        })
    }

    fn parse_intent_plan(
        text: &str,
        lower: &str,
        sender: String,
        network: Option<String>,
    ) -> (String, Option<String>, Value, f64, Vec<Value>) {
        let amount = Self::extract_amount(text, lower);
        let amount_u64 = amount
            .as_ref()
            .and_then(|value| value.parse::<f64>().ok())
            .map(|value| value as u64);
        let addresses = Self::extract_addresses(text);
        let digests = Self::extract_digests(text);
        let resolved_network = Self::resolve_intent_network(network, lower);

        let token_list = ["sui", "usdc", "usdt", "weth", "dai", "cbeth", "eth", "btc"];
        let mut tokens = Vec::new();
        for token in token_list.iter() {
            if let Some(pos) = lower.find(token) {
                tokens.push((pos, token.to_string()));
            }
        }
        tokens.sort_by_key(|(pos, _)| *pos);
        let from_token = tokens.get(0).map(|(_, token)| token.to_uppercase());
        let to_token = tokens.get(1).map(|(_, token)| token.to_uppercase());

        let mut intent = "unknown".to_string();
        let mut action = None;
        let mut confidence = 0.3;
        let mut plan = Vec::new();
        let mut entities = json!({
            "amount": amount,
            "amount_u64": amount_u64,
            "from_coin": from_token,
            "to_coin": to_token,
            "addresses": addresses,
            "digests": digests,
            "network": resolved_network
        });

        #[derive(Clone, Copy)]
        struct IntentRule {
            intent: &'static str,
            action: Option<&'static str>,
            confidence: f64,
            keywords: &'static [&'static str],
        }

        // Ordered by priority: first match wins.
        const RULES: &[IntentRule] = &[
            IntentRule {
                intent: "swap",
                action: None,
                confidence: 0.5,
                keywords: &["swap", "兑换", "换"],
            },
            IntentRule {
                intent: "quote",
                action: Some("quote"),
                confidence: 0.5,
                keywords: &["quote", "报价"],
            },
            IntentRule {
                intent: "get_balance",
                action: None,
                confidence: 0.8,
                keywords: &["balance", "余额"],
            },
            IntentRule {
                intent: "get_reference_gas_price",
                action: None,
                confidence: 0.7,
                keywords: &["gas price", "reference gas", "手续费", "gas"],
            },
            IntentRule {
                intent: "evm_get_gas_price",
                action: None,
                confidence: 0.6,
                keywords: &["evm gas", "eth gas", "gas price on", "gas price (evm)"],
            },
            IntentRule {
                intent: "get_protocol_config",
                action: None,
                confidence: 0.65,
                keywords: &["protocol config", "协议配置"],
            },
            IntentRule {
                intent: "get_chain_identifier",
                action: None,
                confidence: 0.65,
                keywords: &["chain id", "chain identifier", "链 id", "链标识"],
            },
            IntentRule {
                intent: "get_latest_checkpoint_sequence",
                action: None,
                confidence: 0.6,
                keywords: &["checkpoint", "检查点"],
            },
            IntentRule {
                intent: "get_total_transactions",
                action: None,
                confidence: 0.6,
                keywords: &["total tx", "total transactions", "交易总数", "总交易"],
            },
            IntentRule {
                intent: "get_coins",
                action: None,
                confidence: 0.6,
                keywords: &["coins", "coin", "我的 coin"],
            },
            IntentRule {
                intent: "query_transaction_events",
                action: None,
                confidence: 0.55,
                keywords: &["events", "事件"],
            },
            IntentRule {
                intent: "evm_get_transaction_receipt",
                action: None,
                confidence: 0.55,
                keywords: &["receipt", "tx receipt", "transaction receipt", "logs"],
            },
            // Generic EVM contract interaction (safe by default: dry-run only).
            IntentRule {
                intent: "evm_confirm_execution",
                action: None,
                confidence: 0.6,
                keywords: &["confirm", "确认", "确认执行", "确认发送", "broadcast"],
            },
            IntentRule {
                intent: "evm_contract_dry_run",
                action: None,
                confidence: 0.55,
                keywords: &[
                    "contract call",
                    "call",
                    "execute",
                    "approve",
                    "allowance",
                    "balanceof",
                    "deposit",
                    "withdraw",
                    "swap",
                ],
            },
            // More specific than transfer
            IntentRule {
                intent: "transfer_object",
                action: None,
                confidence: 0.55,
                keywords: &["transfer object", "转对象", "转物"],
            },
            IntentRule {
                intent: "transfer",
                action: None,
                confidence: 0.6,
                keywords: &["transfer", "转账", "发送"],
            },
            IntentRule {
                intent: "stake",
                action: None,
                confidence: 0.6,
                keywords: &["stake", "质押"],
            },
            IntentRule {
                intent: "unstake",
                action: None,
                confidence: 0.6,
                keywords: &["unstake", "withdraw stake", "取回"],
            },
            IntentRule {
                intent: "pay_sui",
                action: None,
                confidence: 0.45,
                keywords: &["pay sui", "批量转", "批量转账"],
            },
            IntentRule {
                intent: "mint",
                action: None,
                confidence: 0.45,
                keywords: &["mint", "铸造"],
            },
            IntentRule {
                intent: "borrow",
                action: None,
                confidence: 0.45,
                keywords: &["borrow", "借"],
            },
            IntentRule {
                intent: "lend",
                action: None,
                confidence: 0.45,
                keywords: &["lend", "贷"],
            },
        ];

        if let Some(rule) = RULES.iter().find(|rule| Self::match_any(lower, rule.keywords)) {
            intent = rule.intent.to_string();
            action = rule.action.map(|s| s.to_string());
            confidence = rule.confidence;
        }

        match intent.as_str() {
            "swap" => {
                if lower.contains("exact out") || lower.contains("精确输出") {
                    action = Some("swap_exact_out".to_string());
                } else if lower.contains("exact in") || lower.contains("精确输入") {
                    action = Some("swap_exact_in".to_string());
                }
            }
            "quote" => {}
            "get_balance" => {
                let family = entities
                    .get("network")
                    .and_then(|v| v.get("family"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("sui");

                if family == "evm" {
                    let chain_id = entities
                        .get("network")
                        .and_then(|v| v.get("chain_id"))
                        .and_then(|v| v.as_u64());

                    let token_address = chain_id.and_then(|cid| {
                        // 1) If user provided a contract address in the text, prefer it.
                        Self::infer_evm_token_address_from_text(lower, &addresses).or_else(|| {
                            // 2) Otherwise, resolve common symbols.
                            if lower.contains("usdc") {
                                Self::resolve_evm_erc20_address("usdc", cid)
                            } else if lower.contains("usdt") {
                                Self::resolve_evm_erc20_address("usdt", cid)
                            } else {
                                None
                            }
                        })
                    });
                    entities["token_address"] = json!(token_address);

                    plan.push(json!({
                        "tool": "evm_get_balance",
                        "params": {
                            "address": sender,
                            "chain_id": chain_id,
                            "token_address": token_address
                        }
                    }));
                } else {
                    plan.push(json!({
                        "tool": "get_balance",
                        "params": {
                            "address": sender,
                            "coin_type": null
                        }
                    }));
                }
            }
            "get_reference_gas_price" => {
                plan.push(json!({"tool":"get_reference_gas_price","params":{}}));
            }
            "evm_get_gas_price" => {
                let chain_id = entities
                    .get("network")
                    .and_then(|v| v.get("chain_id"))
                    .and_then(|v| v.as_u64());

                plan.push(json!({
                    "tool": "evm_get_gas_price",
                    "params": {
                        "chain_id": chain_id
                    }
                }));
            }
            "get_protocol_config" => {
                plan.push(json!({"tool":"get_protocol_config","params":{}}));
            }
            "get_chain_identifier" => {
                plan.push(json!({"tool":"get_chain_identifier","params":{}}));
            }
            "get_latest_checkpoint_sequence" => {
                plan.push(json!({"tool":"get_latest_checkpoint_sequence","params":{}}));
            }
            "get_total_transactions" => {
                plan.push(json!({"tool":"get_total_transactions","params":{}}));
            }
            "get_coins" => {
                let coin_type = if lower.contains("usdc") {
                    Some(Self::resolve_sui_coin_type("usdc").unwrap_or_else(|| "<usdc_coin_type>".to_string()))
                } else if lower.contains("usdt") {
                    Self::resolve_sui_coin_type("usdt").or_else(|| Some("<usdt_coin_type>".to_string()))
                } else {
                    None
                };
                entities["coin_type"] = json!(coin_type);

                plan.push(json!({
                    "tool": "get_coins",
                    "params": {
                        "address": sender,
                        "coin_type": coin_type,
                        "limit": 50
                    }
                }));
            }
            "query_transaction_events" => {
                let digest = digests
                    .get(0)
                    .cloned()
                    .unwrap_or_else(|| "<digest>".to_string());
                entities["digest"] = json!(digest);

                plan.push(json!({
                    "tool": "query_transaction_events",
                    "params": {
                        "digest": digest
                    }
                }));
            }
            "evm_get_transaction_receipt" => {
                // EVM tx hashes are 0x... (already captured by extract_addresses)
                let tx_hash = addresses.get(0).cloned().unwrap_or_else(|| "<tx_hash>".to_string());
                entities["tx_hash"] = json!(tx_hash);

                let chain_id = entities
                    .get("network")
                    .and_then(|v| v.get("chain_id"))
                    .and_then(|v| v.as_u64());

                plan.push(json!({
                    "tool": "evm_get_transaction_receipt",
                    "params": {
                        "tx_hash": tx_hash,
                        "chain_id": chain_id
                    }
                }));
            }
            "evm_contract_dry_run" => {
                let family = entities
                    .get("network")
                    .and_then(|v| v.get("family"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("sui");

                if family != "evm" {
                    // If user asked for contract call but we're not on EVM, leave plan empty (unknown).
                    intent = "unknown".to_string();
                } else {
                    let chain_id = entities
                        .get("network")
                        .and_then(|v| v.get("chain_id"))
                        .and_then(|v| v.as_u64());

                    let contract_query = Self::extract_contract_query(lower)
                        .or_else(|| addresses.last().cloned());
                    entities["contract_query"] = json!(contract_query);

                    let function_hint = Self::extract_function_hint(lower);
                    entities["function_hint"] = json!(function_hint);

                    plan.push(json!({
                        "tool": "evm_plan_contract_call",
                        "params": {
                            "chain_id": chain_id,
                            "contract_query": contract_query,
                            "accept_best_match": true,
                            "text": text,
                            "function_hint": function_hint,
                            "limit": 5
                        }
                    }));

                    // NOTE: safe by default; do not sign/broadcast unless explicitly confirmed.
                }
            }
            "transfer" => {
                let recipient = addresses.get(0).cloned().unwrap_or_else(|| "<recipient>".to_string());
                entities["recipient"] = json!(recipient);

                let family = entities
                    .get("network")
                    .and_then(|v| v.get("family"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("sui");

                if family == "evm" {
                    let chain_id = entities
                        .get("network")
                        .and_then(|v| v.get("chain_id"))
                        .and_then(|v| v.as_u64());

                    let amount = entities
                        .get("amount")
                        .and_then(|v| v.as_str())
                        .unwrap_or("<amount_eth>");

                    plan.push(json!({
                        "tool": "evm_execute_transfer_native",
                        "params": {
                            "sender": sender,
                            "recipient": recipient,
                            "amount": amount,
                            "chain_id": chain_id,
                            "gas_limit": null,
                            "confirm_large_transfer": false,
                            "large_transfer_threshold_wei": null
                        }
                    }));
                } else {
                    plan.push(json!({
                        "tool": "build_transfer_sui",
                        "params": {
                            "sender": sender,
                            "recipient": recipient,
                            "input_coins": [],
                            "auto_select_coins": true,
                            "amount": amount_u64,
                            "gas_budget": 1000000
                        }
                    }));
                }
            }
            "transfer_object" => {
                let object_id = addresses.get(0).cloned().unwrap_or_else(|| "<object_id>".to_string());
                let recipient = addresses.get(1).cloned().unwrap_or_else(|| "<recipient>".to_string());
                entities["object_id"] = json!(object_id);
                entities["recipient"] = json!(recipient);
                plan.push(json!({
                    "tool": "build_transfer_object",
                    "params": {
                        "sender": sender,
                        "object_id": object_id,
                        "recipient": recipient,
                        "gas_budget": 1000000,
                        "gas_object_id": null
                    }
                }));
            }
            "stake" => {
                let validator = addresses.get(0).cloned().unwrap_or_else(|| "<validator>".to_string());
                entities["validator"] = json!(validator);
                plan.push(json!({
                    "tool": "build_add_stake",
                    "params": {
                        "sender": sender,
                        "validator": validator,
                        "coins": ["<coin_object_id>"],
                        "amount": amount_u64,
                        "gas_budget": 1000000,
                        "gas_object_id": null
                    }
                }));
            }
            "unstake" => {
                let staked_sui = addresses.get(0).cloned().unwrap_or_else(|| "<staked_sui>".to_string());
                entities["staked_sui"] = json!(staked_sui);
                plan.push(json!({
                    "tool": "build_withdraw_stake",
                    "params": {
                        "sender": sender,
                        "staked_sui": staked_sui,
                        "gas_budget": 1000000,
                        "gas_object_id": null
                    }
                }));
            }
            "pay_sui" => {
                plan.push(json!({
                    "tool": "build_pay_sui",
                    "params": {
                        "sender": sender,
                        "recipients": ["<recipient>", "<recipient>"] ,
                        "amounts": [10000000, 10000000],
                        "input_coins": ["<coin_object_id>"],
                        "gas_budget": 1000000
                    }
                }));
            }
            "mint" | "borrow" | "lend" => {
                plan.push(json!({
                    "tool": "auto_execute_move_call_filled",
                    "params": {
                        "sender": sender,
                        "package": "<package>",
                        "module": "<module>",
                        "function": "<function>",
                        "type_args": [],
                        "arguments": [],
                        "gas_budget": 1000000,
                        "gas_object_id": null,
                        "gas_price": null,
                        "zk_login_inputs_json": "<zk_login_inputs_json>",
                        "address_seed": "<address_seed>",
                        "max_epoch": "<max_epoch>",
                        "user_signature": "<user_signature>"
                    }
                }));
            }
            _ => {}
        }


        (intent, action, entities, confidence, plan)
    }

    fn tool_plan_to_pipeline(plan: &[Value]) -> Vec<Value> {
        plan.iter()
            .map(|item| {
                let params = item.get("params").cloned().unwrap_or(Value::Null);
                let mut missing = Vec::new();
                Self::collect_placeholders(&params, &mut missing);
                json!({
                    "tool": item.get("tool").cloned().unwrap_or(Value::Null),
                    "params": params,
                    "ready": missing.is_empty(),
                    "missing": missing
                })
            })
            .collect()
    }

    fn collect_placeholders(value: &Value, missing: &mut Vec<String>) {
        match value {
            Value::String(value) => {
                if value.starts_with('<') && value.ends_with('>') {
                    missing.push(value.clone());
                }
            }
            Value::Array(items) => {
                for item in items {
                    Self::collect_placeholders(item, missing);
                }
            }
            Value::Object(map) => {
                for value in map.values() {
                    Self::collect_placeholders(value, missing);
                }
            }
            _ => {}
        }
    }

    fn extract_amount(_text: &str, lower: &str) -> Option<String> {
        if let Some(value) = Self::extract_arabic_number(lower) {
            return Some(value);
        }
        Self::extract_chinese_number(lower).map(|value| value.to_string())
    }

    fn extract_slippage_percent(lower: &str) -> Option<String> {
        // Very simple heuristic: pick the first token containing '%' like '1%' or '0.5%'
        for raw in lower.split_whitespace() {
            let t = raw.trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c));
            if let Some(pct) = t.strip_suffix('%') {
                if pct.chars().all(|c| c.is_ascii_digit() || c == '.') {
                    return Some(format!("{}%", pct));
                }
            }
        }
        None
    }

    fn match_any(lower: &str, needles: &[&str]) -> bool {
        needles.iter().any(|needle| lower.contains(needle))
    }

    fn extract_contract_query(lower: &str) -> Option<String> {
        let l = lower.trim();

        // Try: "... on <contract>" (take the last ' on ' to avoid network 'on base').
        if let Some(idx) = l.rfind(" on ") {
            let mut tail = l[(idx + 4)..].trim().to_string();
            for stop in [" on ", " with ", " for ", " to ", " using "] {
                if let Some(j) = tail.find(stop) {
                    tail = tail[..j].trim().to_string();
                }
            }
            tail = tail
                .trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c))
                .to_string();
            if !tail.is_empty() {
                return Some(tail);
            }
        }

        // Try: "contract <...>"
        if let Some(idx) = l.find("contract ") {
            let tail = l[(idx + "contract ".len())..]
                .split_whitespace()
                .next()
                .unwrap_or("")
                .trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c))
                .to_string();
            if !tail.is_empty() {
                return Some(tail);
            }
        }

        None
    }

    fn extract_function_hint(lower: &str) -> Option<String> {
        const HINTS: &[(&str, &[&str])] = &[
            ("approve", &["approve", "授权"]),
            ("transfer", &["transfer", "转账", "发送"]),
            ("swap", &["swap", "兑换", "换"]),
            ("deposit", &["deposit", "存入"]),
            ("withdraw", &["withdraw", "提取", "取出"]),
            ("mint", &["mint", "铸造"]),
        ];

        for (hint, words) in HINTS.iter() {
            if words.iter().any(|w| lower.contains(w)) {
                return Some((*hint).to_string());
            }
        }
        None
    }

    fn extract_arabic_number(text: &str) -> Option<String> {
        let mut current = String::new();
        for ch in text.chars() {
            if ch.is_ascii_digit() || ch == '.' {
                current.push(ch);
            } else if !current.is_empty() {
                break;
            }
        }
        if current.is_empty() { None } else { Some(current) }
    }

    fn extract_chinese_number(text: &str) -> Option<u64> {
        let mut buffer = String::new();
        for ch in text.chars() {
            if "零一二三四五六七八九十百千万亿两".contains(ch) {
                buffer.push(ch);
            } else if !buffer.is_empty() {
                break;
            }
        }
        if buffer.is_empty() {
            return None;
        }

        let digits = |ch| match ch {
            '零' => Some(0),
            '一' => Some(1),
            '二' => Some(2),
            '两' => Some(2),
            '三' => Some(3),
            '四' => Some(4),
            '五' => Some(5),
            '六' => Some(6),
            '七' => Some(7),
            '八' => Some(8),
            '九' => Some(9),
            _ => None,
        };

        let mut total: u64 = 0;
        let mut section: u64 = 0;
        let mut number: u64 = 0;

        for ch in buffer.chars() {
            if let Some(value) = digits(ch) {
                number = value;
            } else {
                let unit = match ch {
                    '十' => 10,
                    '百' => 100,
                    '千' => 1000,
                    '万' => 10_000,
                    '亿' => 100_000_000,
                    _ => 1,
                };
                if unit >= 10_000 {
                    section = (section + number) * unit;
                    total += section;
                    section = 0;
                } else {
                    if number == 0 {
                        number = 1;
                    }
                    section += number * unit;
                }
                number = 0;
            }
        }
        Some(total + section + number)
    }

    fn extract_addresses(text: &str) -> Vec<String> {
        text.split_whitespace()
            .filter(|item| item.starts_with("0x"))
            .map(|item| item.trim_matches(|c: char| c == ',' || c == ';').to_string())
            .collect()
    }

    fn extract_digests(text: &str) -> Vec<String> {
        // Sui transaction digests are base58-encoded strings (not 0x...).
        // We keep this simple: split on whitespace, trim common punctuation,
        // and accept tokens that `parse_digest` validates.
        text.split_whitespace()
            .map(|item| item.trim_matches(|c: char| ",.;:()[]{}<>\"'".contains(c)))
            .filter(|item| !item.is_empty() && !item.starts_with("0x"))
            .filter(|item| Self::parse_digest(item).is_ok())
            .map(|item| item.to_string())
            .collect()
    }

    fn extract_tx_bytes(result: &CallToolResult) -> Option<String> {
        let text = Self::extract_text(result)?;
        serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|value| value.get("tx_bytes").and_then(|value| value.as_str()).map(|value| value.to_string()))
    }

    fn extract_text(result: &CallToolResult) -> Option<String> {
        let content = result.content.first()?;
        match &content.raw {
            RawContent::Text(text) => Some(text.text.clone()),
            RawContent::Resource(resource) => match &resource.resource {
                ResourceContents::TextResourceContents { text, .. } => Some(text.clone()),
                _ => None,
            },
            _ => None,
        }
    }

    fn extract_first_json(result: &CallToolResult) -> Option<Value> {
        let text = Self::extract_text(result)?;
        serde_json::from_str::<Value>(&text).ok()
    }

    fn evm_next_confirmation_id() -> String {
        static COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        let n = COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let now_ms = crate::utils::evm_confirm_store::now_ms();
        format!("evm_dryrun_{}_{}", now_ms, n)
    }
