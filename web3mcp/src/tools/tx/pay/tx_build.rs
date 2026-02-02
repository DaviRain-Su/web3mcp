    /// Auto-generated tool: build transfer object
    #[tool(description = "Auto-generated tool: build transfer object")]
    async fn build_transfer_object(
        &self,
        Parameters(request): Parameters<BuildTransferObjectRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, gas_budget) = self
            .build_transfer_object_data(
                &request.sender,
                &request.object_id,
                &request.recipient,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "gas_budget": gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a transfer SUI transaction
    #[tool(description = "Build a transaction to transfer SUI")]
    async fn build_transfer_sui(
        &self,
        Parameters(request): Parameters<BuildTransferSuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, input_coin_ids, gas_budget) = self
            .build_transfer_sui_data(
                &request.sender,
                &request.recipient,
                request.amount,
                request.gas_budget,
                &request.input_coins,
                request.auto_select_coins,
                request.confirm_large_transfer,
                request.large_transfer_threshold,
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "input_coins": input_coin_ids,
            "gas_budget": gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a transfer SUI transaction using local keystore
    #[tool(description = "Execute a transfer SUI transaction using local keystore")]
    async fn execute_transfer_sui(
        &self,
        Parameters(request): Parameters<ExecuteTransferSuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let merge_summary = if request.auto_merge_small_coins.unwrap_or(false) {
            Some(
                self.merge_small_sui_coins(
                    &request.sender,
                    request.merge_threshold.unwrap_or(10),
                    request.merge_max_inputs.unwrap_or(10),
                    request.keystore_path.as_deref(),
                    request.signer.as_deref(),
                )
                .await?,
            )
        } else {
            None
        };

        let (tx_data, input_coin_ids, _) = self
            .build_transfer_sui_data(
                &request.sender,
                &request.recipient,
                request.amount,
                request.gas_budget,
                &request.input_coins,
                request.auto_select_coins,
                request.confirm_large_transfer,
                request.large_transfer_threshold,
            )
            .await?;

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(signer) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            Self::parse_address(&request.sender)?
        };

        let tx_sender = tx_data.sender();
        if tx_sender != signer && !request.allow_sender_mismatch.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Signer {} does not match transaction sender {}. Set allow_sender_mismatch=true to proceed",
                    signer, tx_sender
                )),
                data: None,
            });
        }

        let (result, preflight) = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data,
                request.allow_sender_mismatch,
                request.preflight,
                request.allow_preflight_failure,
                "execute_transfer_sui",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "input_coins": input_coin_ids,
            "merge_summary": merge_summary,
            "dry_run": preflight,
            "result": result,
            "summary": summary
        }))?;

        self.write_audit_log(
            "execute_transfer_sui",
            json!({
                "sender": request.sender,
                "recipient": request.recipient,
                "amount": request.amount,
                "signer": signer.to_string(),
                "digest": result.digest,
                "merge_summary": merge_summary
            }),
        );

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a transfer object transaction using local keystore
    #[tool(description = "Execute a transfer object transaction using local keystore")]
    async fn execute_transfer_object(
        &self,
        Parameters(request): Parameters<ExecuteTransferObjectRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, _) = self
            .build_transfer_object_data(
                &request.sender,
                &request.object_id,
                &request.recipient,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        if !request.confirm.unwrap_or(false) {
            // Safe default: create a pending confirmation instead of broadcasting.
            let tx_bytes_b64 = Self::encode_tx_bytes(&tx_data)?;
            let tx_bytes = Self::decode_base64("tx_bytes", &tx_bytes_b64)?;

            let created = crate::utils::evm_confirm_store::now_ms();
            let ttl = crate::utils::sui_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::sui_confirm_store::tx_summary_hash(&tx_bytes);

            let seed = format!(
                "{}:{}:{}:{}:{}",
                created,
                request.sender,
                request.recipient,
                request.object_id,
                hash
            );
            let id_suffix = hex::encode(ethers::utils::keccak256(seed.as_bytes()));
            let confirmation_id = format!("sui_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "sender": request.sender,
                "recipient": request.recipient,
                "object_id": request.object_id
            });

            crate::utils::sui_confirm_store::insert_pending(
                &confirmation_id,
                &tx_bytes_b64,
                created,
                expires,
                &hash,
                "execute_transfer_object",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "tool_context": json!({
                    "tool": "execute_transfer_object"
                }),
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call sui_confirm_execution to sign+broadcast (requires keystore_path).",
                "next": {
                    "how_to_confirm": if self.sui_is_mainnet_rpc_url() { let t = crate::utils::sui_confirm_store::make_confirm_token(&confirmation_id, &hash); format!("sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>", confirmation_id, hash, t) } else { format!("sui_confirm_execution id:{} tx_summary_hash:{} keystore_path:<path>", confirmation_id, hash) }
                }
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(signer) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            Self::parse_address(&request.sender)?
        };

        let (result, preflight) = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data,
                request.allow_sender_mismatch,
                request.preflight,
                request.allow_preflight_failure,
                "execute_transfer_object",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "dry_run": preflight,
            "result": result,
            "summary": summary
        }))?;

        self.write_audit_log(
            "execute_transfer_object",
            json!({
                "sender": request.sender,
                "recipient": request.recipient,
                "object_id": request.object_id,
                "signer": signer.to_string(),
                "digest": result.digest
            }),
        );

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a pay SUI transaction using local keystore
    #[tool(description = "Execute a pay SUI transaction using local keystore")]
    async fn execute_pay_sui(
        &self,
        Parameters(request): Parameters<ExecutePaySuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // NOTE: safe-default confirmation handling happens after tx_data is built.
        let (tx_data, _) = self
            .build_pay_sui_data(
                &request.sender,
                &request.recipients,
                &request.amounts,
                &request.input_coins,
                request.gas_budget,
            )
            .await?;

        if !request.confirm.unwrap_or(false) {
            // Safe default: create a pending confirmation instead of broadcasting.
            let tx_bytes_b64 = Self::encode_tx_bytes(&tx_data)?;
            let tx_bytes = Self::decode_base64("tx_bytes", &tx_bytes_b64)?;

            let created = crate::utils::evm_confirm_store::now_ms();
            let ttl = crate::utils::sui_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::sui_confirm_store::tx_summary_hash(&tx_bytes);

            // short id: sui_confirm_<16hex>
            let seed = format!(
                "{}:{}:{}:{}",
                created,
                request.sender,
                request.recipients.len(),
                hash
            );
            let id_suffix = hex::encode(ethers::utils::keccak256(seed.as_bytes()));
            let confirmation_id = format!("sui_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "sender": request.sender,
                "recipients": request.recipients,
                "amounts": request.amounts,
                "input_coins": request.input_coins
            });

            crate::utils::sui_confirm_store::insert_pending(
                &confirmation_id,
                &tx_bytes_b64,
                created,
                expires,
                &hash,
                "execute_pay_sui",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "tool_context": json!({
                    "tool": "execute_pay_sui"
                }),
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call sui_confirm_execution to sign+broadcast (requires keystore_path).",
                "next": {
                    "how_to_confirm": if self.sui_is_mainnet_rpc_url() { let t = crate::utils::sui_confirm_store::make_confirm_token(&confirmation_id, &hash); format!("sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>", confirmation_id, hash, t) } else { format!("sui_confirm_execution id:{} tx_summary_hash:{} keystore_path:<path>", confirmation_id, hash) }
                }
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(signer) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            Self::parse_address(&request.sender)?
        };

        let (result, preflight) = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data,
                request.allow_sender_mismatch,
                request.preflight,
                request.allow_preflight_failure,
                "execute_pay_sui",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "dry_run": preflight,
            "result": result,
            "summary": summary
        }))?;

        self.write_audit_log(
            "execute_pay_sui",
            json!({
                "sender": request.sender,
                "recipients": request.recipients,
                "amounts": request.amounts,
                "signer": signer.to_string(),
                "digest": result.digest
            }),
        );

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a stake transaction using local keystore
    #[tool(description = "Execute a stake transaction using local keystore")]
    async fn execute_add_stake(
        &self,
        Parameters(request): Parameters<ExecuteAddStakeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, _) = self
            .build_add_stake_data(
                &request.sender,
                &request.validator,
                &request.coins,
                request.amount,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        if !request.confirm.unwrap_or(false) {
            let tx_bytes_b64 = Self::encode_tx_bytes(&tx_data)?;
            let tx_bytes = Self::decode_base64("tx_bytes", &tx_bytes_b64)?;

            let created = crate::utils::evm_confirm_store::now_ms();
            let ttl = crate::utils::sui_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::sui_confirm_store::tx_summary_hash(&tx_bytes);

            let seed = format!(
                "{}:{}:{}:{}",
                created,
                request.sender,
                request.validator,
                hash
            );
            let id_suffix = hex::encode(ethers::utils::keccak256(seed.as_bytes()));
            let confirmation_id = format!("sui_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "sender": request.sender,
                "validator": request.validator,
                "coins": request.coins,
                "amount": request.amount
            });

            crate::utils::sui_confirm_store::insert_pending(
                &confirmation_id,
                &tx_bytes_b64,
                created,
                expires,
                &hash,
                "execute_add_stake",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "tool_context": json!({
                    "tool": "execute_add_stake"
                }),
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call sui_confirm_execution to sign+broadcast (requires keystore_path).",
                "next": {
                    "how_to_confirm": if self.sui_is_mainnet_rpc_url() { let t = crate::utils::sui_confirm_store::make_confirm_token(&confirmation_id, &hash); format!("sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>", confirmation_id, hash, t) } else { format!("sui_confirm_execution id:{} tx_summary_hash:{} keystore_path:<path>", confirmation_id, hash) }
                }
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(signer) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            Self::parse_address(&request.sender)?
        };

        let (result, preflight) = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data,
                request.allow_sender_mismatch,
                request.preflight,
                request.allow_preflight_failure,
                "execute_add_stake",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "dry_run": preflight,
            "result": result,
            "summary": summary
        }))?;

        self.write_audit_log(
            "execute_add_stake",
            json!({
                "sender": request.sender,
                "validator": request.validator,
                "amount": request.amount,
                "signer": signer.to_string(),
                "digest": result.digest
            }),
        );

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a withdraw stake transaction using local keystore
    #[tool(description = "Execute a withdraw stake transaction using local keystore")]
    async fn execute_withdraw_stake(
        &self,
        Parameters(request): Parameters<ExecuteWithdrawStakeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, _) = self
            .build_withdraw_stake_data(
                &request.sender,
                &request.staked_sui,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        if !request.confirm.unwrap_or(false) {
            let tx_bytes_b64 = Self::encode_tx_bytes(&tx_data)?;
            let tx_bytes = Self::decode_base64("tx_bytes", &tx_bytes_b64)?;

            let created = crate::utils::evm_confirm_store::now_ms();
            let ttl = crate::utils::sui_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::sui_confirm_store::tx_summary_hash(&tx_bytes);

            let seed = format!(
                "{}:{}:{}:{}",
                created,
                request.sender,
                request.staked_sui,
                hash
            );
            let id_suffix = hex::encode(ethers::utils::keccak256(seed.as_bytes()));
            let confirmation_id = format!("sui_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "sender": request.sender,
                "staked_sui": request.staked_sui
            });

            crate::utils::sui_confirm_store::insert_pending(
                &confirmation_id,
                &tx_bytes_b64,
                created,
                expires,
                &hash,
                "execute_withdraw_stake",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "tool_context": json!({
                    "tool": "execute_withdraw_stake"
                }),
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call sui_confirm_execution to sign+broadcast (requires keystore_path).",
                "next": {
                    "how_to_confirm": if self.sui_is_mainnet_rpc_url() { let t = crate::utils::sui_confirm_store::make_confirm_token(&confirmation_id, &hash); format!("sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>", confirmation_id, hash, t) } else { format!("sui_confirm_execution id:{} tx_summary_hash:{} keystore_path:<path>", confirmation_id, hash) }
                }
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(signer) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            Self::parse_address(&request.sender)?
        };

        let (result, preflight) = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data,
                request.allow_sender_mismatch,
                request.preflight,
                request.allow_preflight_failure,
                "execute_withdraw_stake",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "dry_run": preflight,
            "result": result,
            "summary": summary
        }))?;

        self.write_audit_log(
            "execute_withdraw_stake",
            json!({
                "sender": request.sender,
                "staked_sui": request.staked_sui,
                "signer": signer.to_string(),
                "digest": result.digest
            }),
        );

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    async fn build_transfer_sui_data(
        &self,
        sender: &str,
        recipient: &str,
        amount: Option<u64>,
        gas_budget: Option<u64>,
        input_coins: &[String],
        auto_select_coins: Option<bool>,
        confirm_large_transfer: Option<bool>,
        large_transfer_threshold: Option<u64>,
    ) -> Result<(TransactionData, Vec<String>, u64), ErrorData> {
        let sender = Self::parse_address(sender)?;
        let recipient = Self::parse_address(recipient)?;
        if let Some(amount) = amount {
            let threshold = large_transfer_threshold.unwrap_or(1_000_000_000);
            let confirmed = confirm_large_transfer.unwrap_or(false);
            if amount >= threshold && !confirmed {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Transfer amount {} exceeds threshold {}. Set confirm_large_transfer=true to proceed",
                        amount, threshold
                    )),
                    data: None,
                });
            }
        }

        let mut resolved_gas_budget = gas_budget.unwrap_or(1_000_000);
        let auto_select = auto_select_coins.unwrap_or(true);
        let mut selected_total_balance: Option<u128> = None;
        let input_coin_ids = if input_coins.is_empty() && auto_select {
            let coins = self
                .client
                .coin_read_api()
                .get_coins(sender, None, None, None)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_sui", e))?;
            let mut coin_list = coins.data;
            if coin_list.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("No SUI coins found for sender"),
                    data: None,
                });
            }

            coin_list.sort_by(|a, b| b.balance.cmp(&a.balance));

            if amount.is_none() {
                selected_total_balance = Some(coin_list[0].balance as u128);
                vec![coin_list[0].coin_object_id.to_string()]
            } else {
                let required = amount.unwrap_or(0) as u128 + resolved_gas_budget as u128;
                let mut total: u128 = 0;
                let mut selected = Vec::new();
                for coin in coin_list {
                    selected.push(coin.coin_object_id.to_string());
                    total += coin.balance as u128;
                    if total >= required {
                        break;
                    }
                }
                if total < required {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("Insufficient SUI balance to cover amount and gas"),
                        data: None,
                    });
                }
                selected_total_balance = Some(total);
                selected
            }
        } else {
            input_coins.to_vec()
        };

        let input_coins = Self::parse_object_ids(&input_coin_ids)?;
        let tx_data = if let Some(amount) = amount {
            self.client
                .transaction_builder()
                .pay_sui(sender, input_coins.clone(), vec![recipient], vec![amount], resolved_gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_sui", e))?
        } else {
            self.client
                .transaction_builder()
                .pay_all_sui(sender, input_coins.clone(), recipient, resolved_gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_sui", e))?
        };

        if gas_budget.is_none() {
            let estimated = self.estimate_gas_budget(&tx_data).await?;
            resolved_gas_budget = Self::gas_budget_with_buffer(estimated);
            if let (Some(amount), Some(total)) = (amount, selected_total_balance) {
                let required = amount as u128 + resolved_gas_budget as u128;
                if total < required {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("Insufficient SUI balance to cover amount and estimated gas"),
                        data: None,
                    });
                }
            }
            let rebuilt = if let Some(amount) = amount {
                self.client
                    .transaction_builder()
                    .pay_sui(sender, input_coins, vec![recipient], vec![amount], resolved_gas_budget)
                    .await
                    .map_err(|e| Self::sdk_error("build_transfer_sui", e))?
            } else {
                self.client
                    .transaction_builder()
                    .pay_all_sui(sender, input_coins, recipient, resolved_gas_budget)
                    .await
                    .map_err(|e| Self::sdk_error("build_transfer_sui", e))?
            };
            return Ok((rebuilt, input_coin_ids, resolved_gas_budget));
        }

        Ok((tx_data, input_coin_ids, resolved_gas_budget))
    }

    async fn build_transfer_object_data(
        &self,
        sender: &str,
        object_id: &str,
        recipient: &str,
        gas_budget: Option<u64>,
        gas_object_id: Option<&str>,
    ) -> Result<(TransactionData, u64), ErrorData> {
        let sender = Self::parse_address(sender)?;
        let object_id = Self::parse_object_id(object_id)?;
        let recipient = Self::parse_address(recipient)?;
        let gas = match gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(gas_id)?),
            None => None,
        };

        let mut resolved_gas_budget = gas_budget.unwrap_or(1_000_000);
        let tx_data = self
            .client
            .transaction_builder()
            .transfer_object(sender, object_id, gas, resolved_gas_budget, recipient)
            .await
            .map_err(|e| Self::sdk_error("build_transfer_object", e))?;

        if gas_budget.is_none() {
            let estimated = self.estimate_gas_budget(&tx_data).await?;
            resolved_gas_budget = Self::gas_budget_with_buffer(estimated);
            let rebuilt = self
                .client
                .transaction_builder()
                .transfer_object(sender, object_id, gas, resolved_gas_budget, recipient)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_object", e))?;
            return Ok((rebuilt, resolved_gas_budget));
        }

        Ok((tx_data, resolved_gas_budget))
    }

    async fn build_batch_transaction_data(
        &self,
        sender: &str,
        requests: Vec<Value>,
        gas_budget: Option<u64>,
        gas_object_id: Option<&str>,
    ) -> Result<(TransactionData, u64), ErrorData> {
        let sender = Self::parse_address(sender)?;
        let gas = match gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(gas_id)?),
            None => None,
        };

        let requests = requests
            .into_iter()
            .map(|value| {
                serde_json::from_value::<RPCTransactionRequestParams>(value).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid batch request: {}", e)),
                    data: None,
                })
            })
            .collect::<Result<Vec<_>, _>>()?;

        let mut resolved_gas_budget = gas_budget.unwrap_or(1_000_000);
        let tx_data = self
            .client
            .transaction_builder()
            .batch_transaction(sender, requests.clone(), gas, resolved_gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_batch_transaction", e))?;

        if gas_budget.is_none() {
            let estimated = self.estimate_gas_budget(&tx_data).await?;
            resolved_gas_budget = Self::gas_budget_with_buffer(estimated);
            let rebuilt = self
                .client
                .transaction_builder()
                .batch_transaction(sender, requests, gas, resolved_gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_batch_transaction", e))?;
            return Ok((rebuilt, resolved_gas_budget));
        }

        Ok((tx_data, resolved_gas_budget))
    }

    async fn merge_small_sui_coins(
        &self,
        sender: &str,
        threshold: usize,
        max_inputs: usize,
        keystore_path: Option<&str>,
        signer: Option<&str>,
    ) -> Result<Value, ErrorData> {
        let sender_addr = Self::parse_address(sender)?;
        let coins = self
            .client
            .coin_read_api()
            .get_coins(sender_addr, None, None, None)
            .await
            .map_err(|e| Self::sdk_error("merge_small_sui_coins", e))?;

        if coins.data.len() <= threshold {
            return Ok(json!({
                "merged": false,
                "reason": "below_threshold",
                "coin_count": coins.data.len()
            }));
        }

        let mut coin_list = coins.data;
        coin_list.sort_by(|a, b| b.balance.cmp(&a.balance));
        let target = coin_list[0].coin_object_id;
        let merge_candidates = coin_list
            .into_iter()
            .skip(1)
            .take(max_inputs)
            .map(|coin| coin.coin_object_id)
            .collect::<Vec<_>>();

        if merge_candidates.is_empty() {
            return Ok(json!({
                "merged": false,
                "reason": "no_merge_candidates"
            }));
        }

        let keystore = self.load_file_keystore(keystore_path)?;
        let signer = if let Some(signer) = signer {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            sender_addr
        };

        let mut digests = Vec::new();
        for coin_to_merge in merge_candidates.iter() {
            let tx_data = self
                .client
                .transaction_builder()
                .merge_coins(sender_addr, target, *coin_to_merge, None, 1_000_000)
                .await
                .map_err(|e| Self::sdk_error("merge_small_sui_coins", e))?;

            let (result, _preflight) = self
                .sign_and_execute_tx_data(
                    &keystore,
                    signer,
                    tx_data,
                    Some(false),
                    Some(false),
                    Some(true),
                    "merge_small_sui_coins",
                )
                .await?;
            digests.push(result.digest);
        }

        Ok(json!({
            "merged": true,
            "target": target.to_string(),
            "merged_coins": merge_candidates.iter().map(|id| id.to_string()).collect::<Vec<_>>(),
            "digests": digests
        }))
    }

    async fn build_pay_sui_data(
        &self,
        sender: &str,
        recipients: &[String],
        amounts: &[u64],
        input_coins: &[String],
        gas_budget: Option<u64>,
    ) -> Result<(TransactionData, u64), ErrorData> {
        if recipients.len() != amounts.len() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Recipients and amounts length mismatch"),
                data: None,
            });
        }

        let sender = Self::parse_address(sender)?;
        let recipients = Self::parse_addresses(recipients)?;
        let input_coins = Self::parse_object_ids(input_coins)?;

        let mut resolved_gas_budget = gas_budget.unwrap_or(1_000_000);
        let tx_data = self
            .client
            .transaction_builder()
            .pay_sui(
                sender,
                input_coins.clone(),
                recipients.clone(),
                amounts.to_vec(),
                resolved_gas_budget,
            )
            .await
            .map_err(|e| Self::sdk_error("build_pay_sui", e))?;

        if gas_budget.is_none() {
            let estimated = self.estimate_gas_budget(&tx_data).await?;
            resolved_gas_budget = Self::gas_budget_with_buffer(estimated);
            let rebuilt = self
                .client
                .transaction_builder()
                .pay_sui(sender, input_coins, recipients, amounts.to_vec(), resolved_gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_pay_sui", e))?;
            return Ok((rebuilt, resolved_gas_budget));
        }

        Ok((tx_data, resolved_gas_budget))
    }

    async fn build_add_stake_data(
        &self,
        sender: &str,
        validator: &str,
        coins: &[String],
        amount: Option<u64>,
        gas_budget: Option<u64>,
        gas_object_id: Option<&str>,
    ) -> Result<(TransactionData, u64), ErrorData> {
        let sender = Self::parse_address(sender)?;
        let validator = Self::parse_address(validator)?;
        let coins = Self::parse_object_ids(coins)?;
        let gas = match gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(gas_id)?),
            None => None,
        };

        let mut resolved_gas_budget = gas_budget.unwrap_or(1_000_000);
        let tx_data = self
            .client
            .transaction_builder()
            .request_add_stake(sender, coins.clone(), amount, validator, gas, resolved_gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_add_stake", e))?;

        if gas_budget.is_none() {
            let estimated = self.estimate_gas_budget(&tx_data).await?;
            resolved_gas_budget = Self::gas_budget_with_buffer(estimated);
            let rebuilt = self
                .client
                .transaction_builder()
                .request_add_stake(sender, coins, amount, validator, gas, resolved_gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_add_stake", e))?;
            return Ok((rebuilt, resolved_gas_budget));
        }

        Ok((tx_data, resolved_gas_budget))
    }

    async fn build_withdraw_stake_data(
        &self,
        sender: &str,
        staked_sui: &str,
        gas_budget: Option<u64>,
        gas_object_id: Option<&str>,
    ) -> Result<(TransactionData, u64), ErrorData> {
        let sender = Self::parse_address(sender)?;
        let staked_sui = Self::parse_object_id(staked_sui)?;
        let gas = match gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(gas_id)?),
            None => None,
        };

        let mut resolved_gas_budget = gas_budget.unwrap_or(1_000_000);
        let tx_data = self
            .client
            .transaction_builder()
            .request_withdraw_stake(sender, staked_sui, gas, resolved_gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_withdraw_stake", e))?;

        if gas_budget.is_none() {
            let estimated = self.estimate_gas_budget(&tx_data).await?;
            resolved_gas_budget = Self::gas_budget_with_buffer(estimated);
            let rebuilt = self
                .client
                .transaction_builder()
                .request_withdraw_stake(sender, staked_sui, gas, resolved_gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_withdraw_stake", e))?;
            return Ok((rebuilt, resolved_gas_budget));
        }

        Ok((tx_data, resolved_gas_budget))
    }

    async fn estimate_gas_budget(
        &self,
        tx_data: &TransactionData,
    ) -> Result<u64, ErrorData> {
        let result = self
            .client
            .read_api()
            .dry_run_transaction_block(tx_data.clone())
            .await
            .map_err(|e| Self::sdk_error("estimate_gas_budget", e))?;
        let summary = result.effects.gas_cost_summary();
        Ok(summary.gas_used())
    }

    fn gas_budget_with_buffer(estimate: u64) -> u64 {
        estimate
            .saturating_add(estimate / 5)
            .saturating_add(1_000)
    }

    async fn sign_and_execute_tx_data(
        &self,
        keystore: &sui_keys::keystore::FileBasedKeystore,
        signer: SuiAddress,
        tx_data: TransactionData,
        allow_sender_mismatch: Option<bool>,
        preflight: Option<bool>,
        allow_preflight_failure: Option<bool>,
        context: &str,
    ) -> Result<(SuiTransactionBlockResponse, Option<DryRunTransactionBlockResponse>), ErrorData> {
        let tx_sender = tx_data.sender();
        if tx_sender != signer && !allow_sender_mismatch.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Signer {} does not match transaction sender {}. Set allow_sender_mismatch=true to proceed",
                    signer, tx_sender
                )),
                data: None,
            });
        }

        let preflight_result = if preflight.unwrap_or(false) {
            let result = self.preflight_tx_data(&tx_data).await?;
            if result.execution_error_source.is_some()
                && !allow_preflight_failure.unwrap_or(false)
            {
                let msg = result
                    .execution_error_source
                    .as_deref()
                    .unwrap_or("dry-run failed (missing execution_error_source)");
                self.write_audit_log(
                    context,
                    json!({
                        "event": "dry_run_failed",
                        "message": msg,
                        "allow_preflight_failure": allow_preflight_failure.unwrap_or(false),
                        "sender": signer.to_string(),
                    }),
                );
                return Err(ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Dry-run failed: {}", msg)),
                    data: Some(json!({
                        "dry_run": result,
                        "note": "Set allow_preflight_failure=true to proceed anyway"
                    })),
                });
            }
            Some(result)
        } else {
            None
        };

        let signature = keystore
            .sign_secure(&signer, &tx_data, shared_crypto::intent::Intent::sui_transaction())
            .await
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to sign transaction: {}", e)),
                data: None,
            })?;

        let tx = Transaction::from_generic_sig_data(
            tx_data,
            vec![GenericSignature::Signature(signature)],
        );

        let options = SuiTransactionBlockResponseOptions::new()
            .with_input()
            .with_effects()
            .with_events()
            .with_object_changes()
            .with_balance_changes();

        let result = self
            .client
            .quorum_driver_api()
            .execute_transaction_block(tx, options, None)
            .await
            .map_err(|e| Self::sdk_error(context, e))?;

        Ok((result, preflight_result))
    }

    /// Build a pay SUI transaction
    #[tool(description = "Build a transaction to pay SUI to multiple recipients")]
    async fn build_pay_sui(
        &self,
        Parameters(request): Parameters<BuildPaySuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, gas_budget) = self
            .build_pay_sui_data(
                &request.sender,
                &request.recipients,
                &request.amounts,
                &request.input_coins,
                request.gas_budget,
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "gas_budget": gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a pay-all SUI transaction
    #[tool(description = "Build a transaction to transfer all SUI to a recipient")]
    async fn build_pay_all_sui(
        &self,
        Parameters(request): Parameters<BuildPayAllSuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let recipient = Self::parse_address(&request.recipient)?;
        let input_coins = Self::parse_object_ids(&request.input_coins)?;

        let tx_data = self
            .client
            .transaction_builder()
            .pay_all_sui(sender, input_coins, recipient, request.gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_pay_all_sui", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a Move call transaction
    #[tool(description = "Build a transaction to call a Move function")]
    async fn build_move_call(
        &self,
        Parameters(request): Parameters<BuildMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let package = Self::parse_object_id(&request.package)?;
        let type_args = request
            .type_args
            .into_iter()
            .map(SuiTypeTag::new)
            .collect::<Vec<_>>();
        let call_args = Self::parse_json_args(&request.arguments)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .move_call(
                sender,
                package,
                &request.module,
                &request.function,
                type_args,
                call_args,
                gas,
                request.gas_budget,
                request.gas_price,
            )
            .await
            .map_err(|e| Self::sdk_error("build_move_call", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a publish transaction
    #[tool(description = "Build a transaction to publish Move modules")]
    async fn build_publish(
        &self,
        Parameters(request): Parameters<BuildPublishRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let dependencies = Self::parse_object_ids(&request.dependencies)?;
        let modules = request
            .compiled_modules
            .iter()
            .map(|module| Self::decode_base64("compiled_module", module))
            .collect::<Result<Vec<_>, _>>()?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .publish(sender, modules, dependencies, gas, request.gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_publish", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a split coin transaction
    #[tool(description = "Build a transaction to split a coin into multiple amounts")]
    async fn build_split_coin(
        &self,
        Parameters(request): Parameters<BuildSplitCoinRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let coin_object_id = Self::parse_object_id(&request.coin_object_id)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .split_coin(
                sender,
                coin_object_id,
                request.split_amounts,
                gas,
                request.gas_budget,
            )
            .await
            .map_err(|e| Self::sdk_error("build_split_coin", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a merge coins transaction
    #[tool(description = "Build a transaction to merge two coins")]
    async fn build_merge_coins(
        &self,
        Parameters(request): Parameters<BuildMergeCoinsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let primary_coin = Self::parse_object_id(&request.primary_coin)?;
        let coin_to_merge = Self::parse_object_id(&request.coin_to_merge)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .merge_coins(
                sender,
                primary_coin,
                coin_to_merge,
                gas,
                request.gas_budget,
            )
            .await
            .map_err(|e| Self::sdk_error("build_merge_coins", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a batch transaction
    #[tool(description = "Build a batch transaction from multiple transfer or move-call requests")]
    async fn build_batch_transaction(
        &self,
        Parameters(request): Parameters<BuildBatchTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, gas_budget) = self
            .build_batch_transaction_data(
                &request.sender,
                request.requests,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "gas_budget": gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a batch transaction using local keystore
    #[tool(description = "Execute a batch transaction using local keystore")]
    async fn execute_batch_transaction(
        &self,
        Parameters(request): Parameters<ExecuteBatchTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let requests_count = request.requests.len();

        let (tx_data, _) = self
            .build_batch_transaction_data(
                &request.sender,
                request.requests,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        if !request.confirm.unwrap_or(false) {
            let tx_bytes_b64 = Self::encode_tx_bytes(&tx_data)?;
            let tx_bytes = Self::decode_base64("tx_bytes", &tx_bytes_b64)?;

            let created = crate::utils::evm_confirm_store::now_ms();
            let ttl = crate::utils::sui_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::sui_confirm_store::tx_summary_hash(&tx_bytes);

            let seed = format!("{}:{}:{}", created, request.sender, hash);
            let id_suffix = hex::encode(ethers::utils::keccak256(seed.as_bytes()));
            let confirmation_id = format!("sui_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "sender": request.sender,
                "requests_count": requests_count,
            });

            crate::utils::sui_confirm_store::insert_pending(
                &confirmation_id,
                &tx_bytes_b64,
                created,
                expires,
                &hash,
                "execute_batch_transaction",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "tool_context": json!({
                    "tool": "execute_batch_transaction"
                }),
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call sui_confirm_execution to sign+broadcast (requires keystore_path).",
                "next": {
                    "how_to_confirm": if self.sui_is_mainnet_rpc_url() { let t = crate::utils::sui_confirm_store::make_confirm_token(&confirmation_id, &hash); format!("sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>", confirmation_id, hash, t) } else { format!("sui_confirm_execution id:{} tx_summary_hash:{} keystore_path:<path>", confirmation_id, hash) }
                }
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(signer) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(signer))?
        } else {
            Self::parse_address(&request.sender)?
        };

        let (result, preflight) = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data,
                request.allow_sender_mismatch,
                request.preflight,
                request.allow_preflight_failure,
                "execute_batch_transaction",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "dry_run": preflight,
            "result": result,
            "summary": summary
        }))?;

        self.write_audit_log(
            "execute_batch_transaction",
            json!({
                "sender": request.sender,
                "signer": signer.to_string(),
                "digest": result.digest
            }),
        );
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn sui_is_mainnet_rpc_url(&self) -> bool {
        let url = self.rpc_url.to_lowercase();
        url.contains("mainnet") && !url.contains("testnet") && !url.contains("devnet")
    }

    #[tool(description = "Sui: create a pending confirmation from tx_bytes_b64 (BCS TransactionData). Does not broadcast.")]
    async fn sui_create_pending_confirmation(
        &self,
        Parameters(request): Parameters<SuiCreatePendingConfirmationRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let tx_bytes = Self::decode_base64("tx_bytes_b64", &request.tx_bytes_b64)?;

        // Validate BCS TransactionData
        let _tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid tx bytes (expected BCS TransactionData): {}", e)),
            data: None,
        })?;

        let hash = crate::utils::sui_confirm_store::tx_summary_hash(&tx_bytes);

        let created = crate::utils::evm_confirm_store::now_ms();
        let ttl_ms = request.ttl_ms.unwrap_or(crate::utils::sui_confirm_store::default_ttl_ms() as u64);
        let expires = created.saturating_add(ttl_ms as u128);

        let label = request.label.clone().unwrap_or_else(|| "tx".to_string());
        let label_s = label
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
            .take(16)
            .collect::<String>();
        let confirmation_id = format!("sui_confirm_{}_{}", created, label_s);

        let tool_context = request.tool_context.clone().unwrap_or_else(|| "sui_create_pending_confirmation".to_string());

        crate::utils::sui_confirm_store::insert_pending(
            &confirmation_id,
            request.tx_bytes_b64.trim(),
            created,
            expires,
            &hash,
            &tool_context,
            request.summary.clone(),
        )?;

        let confirm_token = crate::utils::sui_confirm_store::make_confirm_token(&confirmation_id, &hash);

        let response = Self::pretty_json(&json!({
            "status": "pending",
            "confirmation_id": confirmation_id,
            "tx_summary_hash": hash,
            "confirm_token": confirm_token,
            "expires_in_ms": ttl_ms,
            "note": "Not broadcast. Call sui_confirm_execution to sign+broadcast (mainnet requires confirm_token).",
            "next": {
                "how_to_confirm": if self.sui_is_mainnet_rpc_url() {
                    format!(
                        "sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>",
                        confirmation_id, hash, confirm_token
                    )
                } else {
                    format!(
                        "sui_confirm_execution id:{} tx_summary_hash:{} keystore_path:<path>",
                        confirmation_id, hash
                    )
                }
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Confirm and execute a previously prepared Sui transaction.
    #[tool(description = "Sui: confirm and execute a pending transaction created by a safe-default tool (e.g. execute_pay_sui without confirm)")]
    async fn sui_confirm_execution(
        &self,
        Parameters(request): Parameters<SuiConfirmExecutionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::sui_confirm_store::connect()?;
        crate::utils::sui_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let row = match crate::utils::sui_confirm_store::get_row(&conn, &request.id)? {
            Some(r) => r,
            None => {
                return Self::guard_result(
                    "sui_confirm_execution",
                    "UNKNOWN_CONFIRMATION_ID",
                    "Unknown or expired confirmation_id",
                    false,
                    Some("Re-run the build step to create a new pending confirmation"),
                    Some(json!({
                        "how_to": "Re-run your build tool with confirm=false (or sui_create_pending_confirmation) to get a new confirmation_id"
                    })),
                    Some(json!({"id": request.id})),
                );
            }
        };

        if row.status != "pending" {
            return Self::guard_result(
                "sui_confirm_execution",
                "UNSUPPORTED_STATUS",
                "Confirmation not pending",
                false,
                Some("This confirmation is not pending; create a new pending confirmation if you need to execute again"),
                Some(json!({
                    "how_to": "If you want to send again, rebuild and create a new pending confirmation_id"
                })),
                Some(json!({
                    "status": row.status,
                    "digest": row.digest,
                    "last_error": row.last_error,
                    "tool_context": row.tool_context,
                    "summary": row
                        .summary_json
                        .as_deref()
                        .and_then(|s| serde_json::from_str::<Value>(s).ok()),
                })),
            );
        }

        if row.tx_summary_hash != request.tx_summary_hash {
            return Self::guard_result(
                "sui_confirm_execution",
                "TX_SUMMARY_HASH_MISMATCH",
                "tx_summary_hash mismatch; rebuild and confirm again",
                false,
                Some("Use the tx_summary_hash from the pending confirmation record (or rebuild to create a new confirmation)"),
                Some(json!({
                    "tool": "sui_confirm_execution",
                    "args": {
                        "id": request.id.clone(),
                        "tx_summary_hash": row.tx_summary_hash.clone(),
                        "confirm_token": request.confirm_token.clone(),
                        "keystore_path": request.keystore_path.clone(),
                        "signer": request.signer.clone(),
                        "allow_sender_mismatch": request.allow_sender_mismatch,
                        "preflight": request.preflight,
                        "allow_preflight_failure": request.allow_preflight_failure
                    }
                })),
                Some(json!({
                    "expected": row.tx_summary_hash,
                    "provided": request.tx_summary_hash,
                    "confirmation_id": row.id
                })),
            );
        }

        // Mainnet safety: require confirm_token.
        if self.sui_is_mainnet_rpc_url() {
            let expected = crate::utils::sui_confirm_store::make_confirm_token(
                &request.id,
                &request.tx_summary_hash,
            );
            if request.confirm_token.as_deref() != Some(expected.as_str()) {
                return Self::guard_result(
                    "sui_confirm_execution",
                    "CONFIRM_TOKEN_REQUIRED",
                    "Mainnet confirmation requires confirm_token",
                    false,
                    Some("Re-run sui_confirm_execution with the expected confirm_token"),
                    Some(json!({
                        "tool": "sui_confirm_execution",
                        "args": {
                            "id": request.id,
                            "tx_summary_hash": request.tx_summary_hash,
                            "confirm_token": expected,
                            "keystore_path": "<PATH_TO_SUI_KEYSTORE>"
                        }
                    })),
                    Some(json!({
                        "expected_confirm_token": expected,
                        "how_to_confirm": format!(
                            "sui_confirm_execution id:{} tx_summary_hash:{} confirm_token:{} keystore_path:<path>",
                            request.id, request.tx_summary_hash, expected
                        )
                    })),
                );
            }
        }

        let tx_bytes = Self::decode_base64("tx_bytes", &row.tx_bytes_b64)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(s) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(s))?
        } else {
            tx_data.sender()
        };

        // Mark as consumed before signing/broadcast (best-effort).
        crate::utils::sui_confirm_store::mark_consumed(&conn, &row.id)?;

        let preflight_enabled = request.preflight.unwrap_or(true);

        let tx_data_for_send = tx_data.clone();

        let sent = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data_for_send,
                request.allow_sender_mismatch,
                Some(preflight_enabled),
                request.allow_preflight_failure,
                "sui_confirm_execution",
            )
            .await;

        match sent {
            Ok((result, preflight)) => {
                if let Some(ref dr) = preflight {
                    let err = dr.execution_error_source.as_deref();
                    let _ = crate::utils::sui_confirm_store::set_last_dry_run(
                        &conn,
                        &row.id,
                        &json!({"dry_run": dr}),
                        err,
                    );
                }

                let digest = result.digest.to_string();
                let _ = crate::utils::sui_confirm_store::mark_sent(&conn, &row.id, &digest);

                self.write_audit_log(
                    "sui_confirm_execution",
                    json!({
                        "event": "sent",
                        "confirmation_id": row.id,
                        "digest": result.digest,
                        "signer": signer.to_string(),
                    }),
                );

                let execution_summary = Self::summarize_transaction(&result);
                let stored_summary = row
                    .summary_json
                    .as_deref()
                    .and_then(|s| serde_json::from_str::<Value>(s).ok());

                let response = Self::pretty_json(&json!({
                    "status": "sent",
                    "confirmation_id": row.id,
                    "digest": result.digest,
                    "tool_context": row.tool_context,
                    "summary": stored_summary,
                    "dry_run": preflight,
                    "result": result,
                    "execution_summary": execution_summary
                }))?;
                Ok(CallToolResult::success(vec![Content::text(response)]))
            }
            Err(e) => {
                // If confirm-time preflight was enabled, try a best-effort dry-run to capture details.
                if preflight_enabled {
                    if let Ok(dr) = self.preflight_tx_data(&tx_data).await {
                        let err = dr.execution_error_source.as_deref();
                        let _ = crate::utils::sui_confirm_store::set_last_dry_run(
                            &conn,
                            &row.id,
                            &json!({"dry_run": dr}),
                            err,
                        );
                    }
                }

                let _ = crate::utils::sui_confirm_store::mark_failed(&conn, &row.id, &e.message);
                self.write_audit_log(
                    "sui_confirm_execution",
                    json!({
                        "event": "failed",
                        "confirmation_id": row.id,
                        "error": e.message,
                    }),
                );

                Err(ErrorData {
                    code: e.code,
                    message: e.message,
                    data: Some(json!({
                        "confirmation_id": row.id,
                        "tool_context": row.tool_context,
                        "summary": row
                            .summary_json
                            .as_deref()
                            .and_then(|s| serde_json::from_str::<Value>(s).ok()),
                        "note": "Confirm-time execution failed. Check last_dry_run_* fields in DB or re-run with preflight=true for more context."
                    })),
                })
            }
        }
    }

    #[tool(description = "Sui aggregator: raw HTTP call to a swap aggregator (quote/route APIs).")]
    async fn sui_aggregator_call(
        &self,
        Parameters(request): Parameters<SuiAggregatorCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = request
            .base_url
            .or_else(|| std::env::var("SUI_AGGREGATOR_BASE_URL").ok())
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "Missing aggregator base URL. Provide base_url or set env SUI_AGGREGATOR_BASE_URL",
                ),
                data: None,
            })?;

        let method = request
            .method
            .as_deref()
            .unwrap_or("POST")
            .trim()
            .to_uppercase();
        let path = request.path.trim();
        if path.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("path is required"),
                data: None,
            });
        }

        let base = base_url.trim_end_matches('/');
        let path = if path.starts_with('/') { path } else { &format!("/{path}") };
        let mut url = format!("{}{}", base, path);

        // query params
        if let Some(q) = request.query.as_ref() {
            if let Some(map) = q.as_object() {
                let mut first = true;
                for (k, v) in map.iter() {
                    let vs = if v.is_string() {
                        v.as_str().unwrap_or("").to_string()
                    } else {
                        v.to_string()
                    };
                    url.push(if first { '?' } else { '&' });
                    first = false;
                    url.push_str(&format!("{}={}", urlencoding::encode(k), urlencoding::encode(&vs)));
                }
            }
        }

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(timeout_ms))
            .build()
            .map_err(|e| Self::sdk_error("sui_aggregator_call:client", e))?;

        let resp = match method.as_str() {
            "GET" => client.get(&url).send().await,
            "POST" => {
                let mut r = client.post(&url);
                if let Some(b) = request.body.as_ref() {
                    r = r.json(b);
                }
                r.send().await
            }
            other => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Unsupported method: {} (use GET or POST)", other)),
                    data: None,
                })
            }
        }
        .map_err(|e| Self::sdk_error("sui_aggregator_call:request", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| Self::sdk_error("sui_aggregator_call:read_body", e))?;

        let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({ "raw": text }));

        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from aggregator"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
            });
        }

        if request.result_only.unwrap_or(true) {
            let response = Self::pretty_json(&parsed)?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let response = Self::pretty_json(&json!({"url": url, "status": status.as_u16(), "body": parsed}))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Sui: list pending confirmations (sqlite-backed)")]
    async fn sui_list_pending_confirmations(
        &self,
        Parameters(request): Parameters<SuiListPendingConfirmationsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::sui_confirm_store::connect()?;
        crate::utils::sui_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let now_ms = crate::utils::evm_confirm_store::now_ms() as i64;
        let limit = request.limit.unwrap_or(20).min(200) as i64;
        let include_tx_bytes = request.include_tx_bytes.unwrap_or(false);

        let status = request.status.as_deref().map(|s| s.trim().to_lowercase());
        if let Some(st) = status.as_deref() {
            let allowed = ["pending", "consumed", "sent", "failed"];
            if !allowed.contains(&st) {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("status must be one of: pending|consumed|sent|failed"),
                    data: None,
                });
            }
        }

        let mut items: Vec<Value> = Vec::new();

        let mut sql = "SELECT id, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, digest, last_error, tool_context, summary_json, last_dry_run_error, tx_bytes_b64 FROM sui_pending_confirmations".to_string();
        let mut params: Vec<rusqlite::types::Value> = Vec::new();
        if let Some(st) = status {
            sql.push_str(&format!(" WHERE status = ?{}", params.len() + 1));
            params.push(rusqlite::types::Value::Text(st));
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
                let created_at_ms: i64 = row.get(1)?;
                let updated_at_ms: i64 = row.get(2)?;
                let expires_at_ms: i64 = row.get(3)?;
                let tx_summary_hash: String = row.get(4)?;
                let status: String = row.get(5)?;
                let digest: Option<String> = row.get(6)?;
                let last_error: Option<String> = row.get(7)?;
                let tool_context: Option<String> = row.get(8)?;
                let summary_json: Option<String> = row.get(9)?;
                let last_dry_run_error: Option<String> = row.get(10)?;
                let tx_bytes_b64: Option<String> = row.get(11)?;
                Ok((
                    id,
                    created_at_ms,
                    updated_at_ms,
                    expires_at_ms,
                    tx_summary_hash,
                    status,
                    digest,
                    last_error,
                    tool_context,
                    summary_json,
                    last_dry_run_error,
                    tx_bytes_b64,
                ))
            })
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to query_map: {}", e)),
                data: None,
            })?;

        for r in rows.flatten() {
            let expires_in_ms = (r.3 - now_ms).max(0);
            items.push(json!({
                "id": r.0,
                "created_at_ms": r.1,
                "updated_at_ms": r.2,
                "expires_at_ms": r.3,
                "expires_in_ms": expires_in_ms,
                "tx_summary_hash": r.4,
                "status": r.5,
                "digest": r.6,
                "last_error": r.7,
                "tool_context": r.8,
                "summary": r.9.as_deref().and_then(|s| serde_json::from_str::<Value>(s).ok()),
                "last_dry_run_error": r.10,
                "tx_bytes_b64": if include_tx_bytes { r.11 } else { None },
            }));
        }

        let response = Self::pretty_json(&json!({
            "db_path": crate::utils::evm_confirm_store::pending_db_path_from_cwd()?.to_string_lossy(),
            "count": items.len(),
            "items": items
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Sui: get a pending confirmation by id (sqlite-backed)")]
    async fn sui_get_pending_confirmation(
        &self,
        Parameters(request): Parameters<SuiGetPendingConfirmationRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::sui_confirm_store::connect()?;
        crate::utils::sui_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let include_tx_bytes = request.include_tx_bytes.unwrap_or(true);
        let row = crate::utils::sui_confirm_store::get_row(&conn, request.id.trim())?;

        let response = Self::pretty_json(&json!({
            "db_path": crate::utils::evm_confirm_store::pending_db_path_from_cwd()?.to_string_lossy(),
            "item": row.map(|r| json!({
                "id": r.id,
                "created_at_ms": r.created_at_ms,
                "updated_at_ms": r.updated_at_ms,
                "expires_at_ms": r.expires_at_ms,
                "expires_in_ms": (r.expires_at_ms as i128 - crate::utils::evm_confirm_store::now_ms() as i128).max(0),
                "tx_summary_hash": r.tx_summary_hash,
                "status": r.status,
                "digest": r.digest,
                "last_error": r.last_error,
                "tool_context": r.tool_context,
                "summary": r.summary_json.as_deref().and_then(|s| serde_json::from_str::<Value>(s).ok()),
                "last_dry_run_error": r.last_dry_run_error,
                "last_dry_run": r.last_dry_run_json.as_deref().and_then(|s| serde_json::from_str::<Value>(s).ok()),
                "tx_bytes_b64": if include_tx_bytes { Some(r.tx_bytes_b64) } else { None }
            }))
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Sui: retry executing a pending/failed/consumed confirmation (sqlite-backed). Safe: requires matching tx_summary_hash.")]
    async fn sui_retry_pending_confirmation(
        &self,
        Parameters(request): Parameters<SuiRetryPendingConfirmationRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let conn = crate::utils::sui_confirm_store::connect()?;
        crate::utils::sui_confirm_store::cleanup_expired(
            &conn,
            crate::utils::evm_confirm_store::now_ms(),
        )?;

        let row = match crate::utils::sui_confirm_store::get_row(&conn, request.id.trim())? {
            Some(r) => r,
            None => {
                return Self::guard_result(
                    "sui_retry_pending_confirmation",
                    "UNKNOWN_CONFIRMATION_ID",
                    "Unknown or expired confirmation_id",
                    false,
                    Some("Re-run the build step to create a new pending confirmation"),
                    Some(json!({
                        "how_to": "Re-run your build tool with confirm=false (or sui_create_pending_confirmation) to get a new confirmation_id"
                    })),
                    Some(json!({"id": request.id})),
                );
            }
        };

        if row.tx_summary_hash != request.tx_summary_hash {
            return Self::guard_result(
                "sui_retry_pending_confirmation",
                "TX_SUMMARY_HASH_MISMATCH",
                "tx_summary_hash mismatch; rebuild and confirm again",
                false,
                Some("Use the tx_summary_hash from the pending confirmation record (or rebuild to create a new confirmation)"),
                Some(json!({
                    "tool": "sui_retry_pending_confirmation",
                    "args": {
                        "id": request.id.clone(),
                        "tx_summary_hash": row.tx_summary_hash.clone(),
                        "confirm_token": request.confirm_token.clone()
                    }
                })),
                Some(json!({
                    "expected": row.tx_summary_hash,
                    "provided": request.tx_summary_hash,
                    "confirmation_id": row.id
                })),
            );
        }

        // Mainnet safety: require confirm_token.
        if self.sui_is_mainnet_rpc_url() {
            let expected = crate::utils::sui_confirm_store::make_confirm_token(
                request.id.trim(),
                request.tx_summary_hash.trim(),
            );
            if request.confirm_token.as_deref() != Some(expected.as_str()) {
                return Self::guard_result(
                    "sui_retry_pending_confirmation",
                    "CONFIRM_TOKEN_REQUIRED",
                    "Mainnet retry requires confirm_token",
                    false,
                    Some("Re-run sui_retry_pending_confirmation with the expected confirm_token"),
                    Some(json!({
                        "tool": "sui_retry_pending_confirmation",
                        "args": {
                            "id": request.id,
                            "tx_summary_hash": request.tx_summary_hash,
                            "confirm_token": expected
                        }
                    })),
                    Some(json!({
                        "expected_confirm_token": expected,
                        "how_to_retry": format!(
                            "sui_retry_pending_confirmation id:{} tx_summary_hash:{} confirm_token:{}",
                            request.id, request.tx_summary_hash, expected
                        )
                    })),
                );
            }
        }

        let allowed = ["pending", "failed", "consumed"];
        if !allowed.contains(&row.status.as_str()) {
            return Self::guard_result(
                "sui_retry_pending_confirmation",
                "UNSUPPORTED_STATUS",
                "Cannot retry this status",
                false,
                Some("Create a new pending confirmation (rebuild) instead of retrying"),
                Some(json!({
                    "how_to": "Rebuild and create a new pending confirmation_id"
                })),
                Some(json!({
                    "status": row.status,
                    "digest": row.digest,
                    "last_error": row.last_error,
                    "tool_context": row.tool_context,
                    "summary": row
                        .summary_json
                        .as_deref()
                        .and_then(|s| serde_json::from_str::<Value>(s).ok()),
                })),
            );
        }

        // Reset to pending before retry.
        let _ = crate::utils::sui_confirm_store::mark_pending(&conn, &row.id);

        // Execute using same logic as sui_confirm_execution.
        let tx_bytes = Self::decode_base64("tx_bytes", &row.tx_bytes_b64)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;

        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = if let Some(s) = request.signer.as_deref() {
            self.resolve_keystore_signer(&keystore, Some(s))?
        } else {
            tx_data.sender()
        };

        crate::utils::sui_confirm_store::mark_consumed(&conn, &row.id)?;

        let preflight_enabled = request.preflight.unwrap_or(true);
        let tx_data_for_send = tx_data.clone();

        let sent = self
            .sign_and_execute_tx_data(
                &keystore,
                signer,
                tx_data_for_send,
                request.allow_sender_mismatch,
                Some(preflight_enabled),
                request.allow_preflight_failure,
                "sui_retry_pending_confirmation",
            )
            .await;

        match sent {
            Ok((result, preflight)) => {
                if let Some(ref dr) = preflight {
                    let err = dr.execution_error_source.as_deref();
                    let _ = crate::utils::sui_confirm_store::set_last_dry_run(
                        &conn,
                        &row.id,
                        &json!({"dry_run": dr}),
                        err,
                    );
                }

                let digest = result.digest.to_string();
                let _ = crate::utils::sui_confirm_store::mark_sent(&conn, &row.id, &digest);

                self.write_audit_log(
                    "sui_retry_pending_confirmation",
                    json!({
                        "event": "sent",
                        "confirmation_id": row.id,
                        "digest": result.digest,
                        "signer": signer.to_string(),
                    }),
                );

                let execution_summary = Self::summarize_transaction(&result);
                let stored_summary = row
                    .summary_json
                    .as_deref()
                    .and_then(|s| serde_json::from_str::<Value>(s).ok());

                let response = Self::pretty_json(&json!({
                    "status": "sent",
                    "confirmation_id": row.id,
                    "digest": result.digest,
                    "tool_context": row.tool_context,
                    "summary": stored_summary,
                    "dry_run": preflight,
                    "result": result,
                    "execution_summary": execution_summary
                }))?;
                Ok(CallToolResult::success(vec![Content::text(response)]))
            }
            Err(e) => {
                if preflight_enabled {
                    if let Ok(dr) = self.preflight_tx_data(&tx_data).await {
                        let err = dr.execution_error_source.as_deref();
                        let _ = crate::utils::sui_confirm_store::set_last_dry_run(
                            &conn,
                            &row.id,
                            &json!({"dry_run": dr}),
                            err,
                        );
                    }
                }

                let _ = crate::utils::sui_confirm_store::mark_failed(&conn, &row.id, &e.message);

                self.write_audit_log(
                    "sui_retry_pending_confirmation",
                    json!({
                        "event": "failed",
                        "confirmation_id": row.id,
                        "error": e.message,
                    }),
                );

                Err(ErrorData {
                    code: e.code,
                    message: e.message,
                    data: Some(json!({
                        "confirmation_id": row.id,
                        "tool_context": row.tool_context,
                        "summary": row
                            .summary_json
                            .as_deref()
                            .and_then(|s| serde_json::from_str::<Value>(s).ok()),
                        "note": "Retry execution failed. Check last_dry_run_* fields in DB or re-run with preflight=true for more context."
                    })),
                })
            }
        }
    }

    /// Build a stake transaction
    #[tool(description = "Build a transaction to add stake")]
    async fn build_add_stake(
        &self,
        Parameters(request): Parameters<BuildAddStakeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, gas_budget) = self
            .build_add_stake_data(
                &request.sender,
                &request.validator,
                &request.coins,
                request.amount,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "gas_budget": gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a withdraw stake transaction
    #[tool(description = "Build a transaction to withdraw stake")]
    async fn build_withdraw_stake(
        &self,
        Parameters(request): Parameters<BuildWithdrawStakeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let (tx_data, gas_budget) = self
            .build_withdraw_stake_data(
                &request.sender,
                &request.staked_sui,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "gas_budget": gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build an upgrade transaction
    #[tool(description = "Build a transaction to upgrade a Move package")]
    async fn build_upgrade(
        &self,
        Parameters(request): Parameters<BuildUpgradeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let package_id = Self::parse_object_id(&request.package_id)?;
        let dependencies = Self::parse_object_ids(&request.dependencies)?;
        let upgrade_capability = Self::parse_object_id(&request.upgrade_capability)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };
        let compiled_modules = request
            .compiled_modules
            .iter()
            .map(|module| Self::decode_base64("compiled_module", module))
            .collect::<Result<Vec<_>, _>>()?;
        let digest = Self::decode_base64("digest", &request.digest)?;

        let tx_data = self
            .client
            .transaction_builder()
            .upgrade(
                sender,
                package_id,
                compiled_modules,
                dependencies,
                upgrade_capability,
                request.upgrade_policy,
                digest,
                gas,
                request.gas_budget,
            )
            .await
            .map_err(|e| Self::sdk_error("build_upgrade", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn get_7k_base_url(override_url: Option<&str>) -> Result<String, ErrorData> {
        if let Some(url) = override_url {
            return Ok(url.to_string());
        }
        if let Ok(url) = std::env::var("SUI_7K_BASE_URL") {
            return Ok(url);
        }
        if let Ok(url) = std::env::var("SUI_AGGREGATOR_BASE_URL") {
            return Ok(url);
        }
        Ok("https://api.7k.ag".to_string())
    }

    #[tool(description = "Sui 7K aggregator: get swap quote for token pair. Returns routing info and expected output amount.")]
    async fn sui_7k_quote(
        &self,
        Parameters(request): Parameters<Sui7kQuoteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = Self::get_7k_base_url(request.base_url.as_deref())?;

        let default_sources = "suiswap,turbos,cetus,bluemove,kriya,kriya_v3,aftermath,deepbook_v3,flowx,flowx_v3,bluefin,springsui,obric,stsui,steamm,magma,haedal_pmm,momentum,sevenk_v1,fullsail,cetus_dlmm,ferra_dlmm,ferra_clmm";
        let sources = request.sources.as_deref().unwrap_or(default_sources);

        let mut url = format!(
            "{}/quote?amount={}&from={}&to={}&sources={}",
            base_url.trim_end_matches('/'),
            urlencoding::encode(&request.amount_in),
            urlencoding::encode(&request.from_coin_type),
            urlencoding::encode(&request.to_coin_type),
            urlencoding::encode(sources)
        );

        if let Some(sender) = request.sender.as_deref() {
            url.push_str(&format!("&taker={}", urlencoding::encode(sender)));
        }

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(timeout_ms))
            .build()
            .map_err(|e| Self::sdk_error("sui_7k_quote:client", e))?;

        let resp = client
            .get(&url)
            .send()
            .await
            .map_err(|e| Self::sdk_error("sui_7k_quote:request", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| Self::sdk_error("sui_7k_quote:read_body", e))?;

        let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({ "raw": text }));

        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from 7K aggregator"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
            });
        }

        let slippage_bps = request.slippage_bps.unwrap_or(100);
        let return_amount = parsed
            .get("returnAmountWithDecimal")
            .and_then(|v| v.as_str())
            .unwrap_or("0");
        let return_amount_num: u128 = return_amount.parse().unwrap_or(0);
        let min_received = return_amount_num * (10000 - slippage_bps as u128) / 10000;

        let response = Self::pretty_json(&json!({
            "quote": parsed,
            "from_coin_type": request.from_coin_type,
            "to_coin_type": request.to_coin_type,
            "amount_in": request.amount_in,
            "return_amount": return_amount,
            "min_received": min_received.to_string(),
            "slippage_bps": slippage_bps,
            "sources": sources,
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Sui 7K aggregator: build swap transaction from quote. Returns tx_bytes_b64 for signing/execution. NOTE: This is a simplified builder that creates a basic swap transaction. For complex routes, consider using sui_aggregator_call with custom transaction building.")]
    async fn sui_7k_build_swap_tx(
        &self,
        Parameters(request): Parameters<Sui7kBuildSwapTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let slippage_bps = request.slippage_bps.unwrap_or(100);
        let commission_bps = request.commission_bps.unwrap_or(0);

        let token_in = request
            .quote
            .get("tokenIn")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("quote.tokenIn is required"),
                data: None,
            })?;

        let token_out = request
            .quote
            .get("tokenOut")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("quote.tokenOut is required"),
                data: None,
            })?;

        let swap_amount = request
            .quote
            .get("swapAmountWithDecimal")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("quote.swapAmountWithDecimal is required"),
                data: None,
            })?;

        let return_amount = request
            .quote
            .get("returnAmountWithDecimal")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("quote.returnAmountWithDecimal is required"),
                data: None,
            })?;

        let return_amount_num: u128 = return_amount.parse().map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Invalid returnAmountWithDecimal"),
            data: None,
        })?;

        let return_after_commission =
            return_amount_num * (10000 - commission_bps as u128) / 10000;
        let min_received = return_after_commission * (10000 - slippage_bps as u128) / 10000;

        let routes = request.quote.get("routes");

        let response = Self::pretty_json(&json!({
            "status": "quote_processed",
            "sender": request.sender,
            "token_in": token_in,
            "token_out": token_out,
            "swap_amount": swap_amount,
            "expected_return": return_amount,
            "min_received": min_received.to_string(),
            "slippage_bps": slippage_bps,
            "commission_bps": commission_bps,
            "routes": routes,
            "note": "7K aggregator uses complex on-chain routing. For full swap execution, use sui_7k_swap_exact_in which handles the complete flow, or use sui_aggregator_call for custom API interactions.",
            "next_step": "Use sui_7k_swap_exact_in with the original parameters, or build a custom transaction using the routing info."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Sui 7K aggregator: execute swap (exact input). Gets quote, creates pending confirmation (mainnet safety), and optionally executes with keystore signing.")]
    async fn sui_7k_swap_exact_in(
        &self,
        Parameters(request): Parameters<Sui7kSwapExactInRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = Self::get_7k_base_url(request.base_url.as_deref())?;
        let sender_addr = Self::parse_address(&request.sender)?;
        let slippage_bps = request.slippage_bps.unwrap_or(100);
        let commission_bps = request.commission_bps.unwrap_or(0);

        let default_sources = "suiswap,turbos,cetus,bluemove,kriya,kriya_v3,aftermath,deepbook_v3,flowx,flowx_v3,bluefin,springsui,obric,stsui,steamm,magma,haedal_pmm,momentum,sevenk_v1,fullsail,cetus_dlmm,ferra_dlmm,ferra_clmm";
        let sources = request.sources.as_deref().unwrap_or(default_sources);

        let url = format!(
            "{}/quote?amount={}&from={}&to={}&sources={}&taker={}",
            base_url.trim_end_matches('/'),
            urlencoding::encode(&request.amount_in),
            urlencoding::encode(&request.from_coin_type),
            urlencoding::encode(&request.to_coin_type),
            urlencoding::encode(sources),
            urlencoding::encode(&request.sender)
        );

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(timeout_ms))
            .build()
            .map_err(|e| Self::sdk_error("sui_7k_swap:client", e))?;

        let resp = client
            .get(&url)
            .send()
            .await
            .map_err(|e| Self::sdk_error("sui_7k_swap:quote_request", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| Self::sdk_error("sui_7k_swap:read_body", e))?;

        let quote: Value = serde_json::from_str(&text).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to parse quote response: {}", e)),
            data: Some(json!({"raw": text})),
        })?;

        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from 7K aggregator"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": quote})),
            });
        }

        let return_amount = quote
            .get("returnAmountWithDecimal")
            .and_then(|v| v.as_str())
            .unwrap_or("0");
        let return_amount_num: u128 = return_amount.parse().unwrap_or(0);
        let return_after_commission =
            return_amount_num * (10000 - commission_bps as u128) / 10000;
        let min_received = return_after_commission * (10000 - slippage_bps as u128) / 10000;

        let swap_summary = json!({
            "tool": "sui_7k_swap_exact_in",
            "from_coin_type": request.from_coin_type,
            "to_coin_type": request.to_coin_type,
            "amount_in": request.amount_in,
            "expected_return": return_amount,
            "min_received": min_received.to_string(),
            "slippage_bps": slippage_bps,
            "commission_bps": commission_bps,
            "sender": request.sender,
            "partner": request.partner,
            "quote": quote,
        });

        let summary_str = serde_json::to_string(&swap_summary).unwrap_or_default();
        let summary_hash = format!("0x{:x}", md5::compute(&summary_str));

        let is_mainnet = self.resolve_network_kind() == "mainnet";
        let skip_confirmation = request.skip_confirmation.unwrap_or(false);

        if is_mainnet && !skip_confirmation {
            let conn = crate::utils::sui_confirm_store::connect()?;
            let now_ms = crate::utils::evm_confirm_store::now_ms();
            let expires_at_ms = now_ms + 600_000;
            let confirm_token = format!("sui7k_{}", uuid::Uuid::new_v4());
            let id = format!("sui_7k_swap_{}", uuid::Uuid::new_v4());

            conn.execute(
                "INSERT INTO sui_pending_confirmations (id, created_at_ms, updated_at_ms, expires_at_ms, tx_summary_hash, status, tool_context, summary_json, confirm_token)
                 VALUES (?1, ?2, ?3, ?4, ?5, 'pending', ?6, ?7, ?8)",
                rusqlite::params![
                    id,
                    now_ms as i64,
                    now_ms as i64,
                    expires_at_ms as i64,
                    summary_hash,
                    "sui_7k_swap_exact_in",
                    summary_str,
                    confirm_token,
                ],
            )
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to create pending confirmation: {}", e)),
                data: None,
            })?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "message": "7K swap pending confirmation (mainnet safety). Use sui_confirm_execution to broadcast.",
                "confirmation_id": id,
                "tx_summary_hash": summary_hash,
                "confirm_token": confirm_token,
                "expires_at_ms": expires_at_ms,
                "swap_summary": swap_summary,
                "next": {
                    "tool": "sui_confirm_execution",
                    "args": {
                        "id": id,
                        "tx_summary_hash": summary_hash,
                        "confirm_token": confirm_token,
                    }
                },
                "note": "7K aggregator swaps require on-chain transaction building. The pending confirmation stores the quote; actual execution will use the routing info to build and sign the transaction."
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let response = Self::pretty_json(&json!({
            "status": "quote_ready",
            "message": "Quote obtained. For mainnet execution with safety, set skip_confirmation=false (default). For testnet/devnet, the quote is ready for manual transaction building.",
            "swap_summary": swap_summary,
            "note": "7K aggregator uses complex DEX routing. Full programmatic execution requires building transactions based on the routing paths in the quote. Use sui_aggregator_call for custom API interactions."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
