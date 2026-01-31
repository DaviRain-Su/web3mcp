    /// Auto-generated tool: build transfer object
    #[tool(description = "Auto-generated tool: build transfer object")]
    async fn build_transfer_object(
        &self,
        Parameters(request): Parameters<BuildTransferObjectRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let object_id = Self::parse_object_id(&request.object_id)?;
        let recipient = Self::parse_address(&request.recipient)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .transfer_object(sender, object_id, gas, request.gas_budget, recipient)
            .await
            .map_err(|e| Self::sdk_error("build_transfer_object", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a transfer SUI transaction
    #[tool(description = "Build a transaction to transfer SUI")]
    async fn build_transfer_sui(
        &self,
        Parameters(request): Parameters<BuildTransferSuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let recipient = Self::parse_address(&request.recipient)?;
        if let Some(amount) = request.amount {
            let threshold = request.large_transfer_threshold.unwrap_or(1_000_000_000);
            let confirmed = request.confirm_large_transfer.unwrap_or(false);
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
        let auto_select = request.auto_select_coins.unwrap_or(true);
        let input_coin_ids = if request.input_coins.is_empty() && auto_select {
            let coins = self
                .client
                .coin_read_api()
                .get_coins(sender, None, None, None)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_sui", e))?;
            let coin_ids = coins
                .data
                .iter()
                .map(|coin| coin.coin_object_id.to_string())
                .collect::<Vec<_>>();
            if coin_ids.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("No SUI coins found for sender"),
                    data: None,
                });
            }
            coin_ids
        } else {
            request.input_coins.clone()
        };
        let input_coins = Self::parse_object_ids(&input_coin_ids)?;

        let tx_data = if let Some(amount) = request.amount {
            self.client
                .transaction_builder()
                .pay_sui(sender, input_coins, vec![recipient], vec![amount], request.gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_sui", e))?
        } else {
            self.client
                .transaction_builder()
                .pay_all_sui(sender, input_coins, recipient, request.gas_budget)
                .await
                .map_err(|e| Self::sdk_error("build_transfer_sui", e))?
        };

        let response = Self::pretty_json(&json!({
            "tx_bytes": Self::encode_tx_bytes(&tx_data)?,
            "input_coins": input_coin_ids
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a pay SUI transaction
    #[tool(description = "Build a transaction to pay SUI to multiple recipients")]
    async fn build_pay_sui(
        &self,
        Parameters(request): Parameters<BuildPaySuiRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        if request.recipients.len() != request.amounts.len() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Recipients and amounts length mismatch"),
                data: None,
            });
        }

        let sender = Self::parse_address(&request.sender)?;
        let recipients = Self::parse_addresses(&request.recipients)?;
        let input_coins = Self::parse_object_ids(&request.input_coins)?;

        let tx_data = self
            .client
            .transaction_builder()
            .pay_sui(
                sender,
                input_coins,
                recipients,
                request.amounts,
                request.gas_budget,
            )
            .await
            .map_err(|e| Self::sdk_error("build_pay_sui", e))?;

        let response = Self::tx_response(&tx_data)?;
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
        let sender = Self::parse_address(&request.sender)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let requests = request
            .requests
            .into_iter()
            .map(|value| {
                serde_json::from_value::<RPCTransactionRequestParams>(value).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid batch request: {}", e)),
                    data: None,
                })
            })
            .collect::<Result<Vec<_>, _>>()?;

        let tx_data = self
            .client
            .transaction_builder()
            .batch_transaction(sender, requests, gas, request.gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_batch_transaction", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a stake transaction
    #[tool(description = "Build a transaction to add stake")]
    async fn build_add_stake(
        &self,
        Parameters(request): Parameters<BuildAddStakeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let validator = Self::parse_address(&request.validator)?;
        let coins = Self::parse_object_ids(&request.coins)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .request_add_stake(
                sender,
                coins,
                request.amount,
                validator,
                gas,
                request.gas_budget,
            )
            .await
            .map_err(|e| Self::sdk_error("build_add_stake", e))?;

        let response = Self::tx_response(&tx_data)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Build a withdraw stake transaction
    #[tool(description = "Build a transaction to withdraw stake")]
    async fn build_withdraw_stake(
        &self,
        Parameters(request): Parameters<BuildWithdrawStakeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let staked_sui = Self::parse_object_id(&request.staked_sui)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let tx_data = self
            .client
            .transaction_builder()
            .request_withdraw_stake(sender, staked_sui, gas, request.gas_budget)
            .await
            .map_err(|e| Self::sdk_error("build_withdraw_stake", e))?;

        let response = Self::tx_response(&tx_data)?;
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
