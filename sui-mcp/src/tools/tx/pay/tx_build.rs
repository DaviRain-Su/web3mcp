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
        if !request.confirm.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("transfer_object requires confirm=true"),
                data: None,
            });
        }
        let (tx_data, _) = self
            .build_transfer_object_data(
                &request.sender,
                &request.object_id,
                &request.recipient,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

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
        if !request.confirm.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("pay_sui requires confirm=true"),
                data: None,
            });
        }
        let (tx_data, _) = self
            .build_pay_sui_data(
                &request.sender,
                &request.recipients,
                &request.amounts,
                &request.input_coins,
                request.gas_budget,
            )
            .await?;

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
        if !request.confirm.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("stake requires confirm=true"),
                data: None,
            });
        }
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
        if !request.confirm.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("withdraw_stake requires confirm=true"),
                data: None,
            });
        }
        let (tx_data, _) = self
            .build_withdraw_stake_data(
                &request.sender,
                &request.staked_sui,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

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
        if !request.confirm.unwrap_or(false) {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("batch transaction requires confirm=true"),
                data: None,
            });
        }
        let (tx_data, _) = self
            .build_batch_transaction_data(
                &request.sender,
                request.requests,
                request.gas_budget,
                request.gas_object_id.as_deref(),
            )
            .await?;

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
