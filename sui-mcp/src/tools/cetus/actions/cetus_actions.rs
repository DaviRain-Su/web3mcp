    /// Auto-generated tool: cetus prepare
    #[tool(description = "Auto-generated tool: cetus prepare")]
    async fn cetus_prepare(
        &self,
        Parameters(request): Parameters<CetusPrepareRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = Self::resolve_network(request.network);
        let config = Self::load_cetus_config(None)?;
        let (package_id, module, function) = Self::resolve_cetus_action(
            config,
            &network,
            &request.action,
            request.package_id.clone(),
            request.module.clone(),
            request.function.clone(),
        )?;

        let fill_request = AutoFillMoveCallRequest {
            sender: request.sender.clone(),
            package: package_id.clone(),
            module: module.clone(),
            function: function.clone(),
            type_args: request.type_args.clone(),
            arguments: request.arguments.clone(),
            gas_budget: Some(request.gas_budget),
            gas_object_id: request.gas_object_id.clone(),
            gas_price: request.gas_price,
        };
        let filled = self.auto_fill_move_call_internal(&fill_request).await?;

        let prepare_request = PrepareMoveCallRequest {
            sender: request.sender,
            package: package_id,
            module,
            function,
            type_args: filled.type_args,
            arguments: filled.arguments,
            gas_budget: filled.gas_budget.unwrap_or(request.gas_budget),
            gas_object_id: filled.gas_object_id,
            gas_price: filled.gas_price,
        };

        let response = self.prepare_move_call(Parameters(prepare_request)).await?;
        let payload = json!({
            "warnings": filled.warnings,
            "gas": filled.gas,
            "result": response
        });
        let response = Self::pretty_json(&payload)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a Cetus transaction
    #[tool(description = "Execute a Cetus action transaction with zkLogin")]
    async fn cetus_execute(
        &self,
        Parameters(request): Parameters<CetusExecuteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = Self::resolve_network(request.network);
        let config = Self::load_cetus_config(None)?;
        let (package_id, module, function) = Self::resolve_cetus_action(
            config,
            &network,
            &request.action,
            request.package_id.clone(),
            request.module.clone(),
            request.function.clone(),
        )?;

        let execute_request = AutoExecuteMoveCallRequest {
            sender: request.sender,
            package: package_id,
            module,
            function,
            type_args: request.type_args.unwrap_or_default(),
            arguments: request.arguments,
            gas_budget: request.gas_budget,
            gas_object_id: request.gas_object_id,
            gas_price: request.gas_price,
            zk_login_inputs_json: request.zk_login_inputs_json,
            address_seed: request.address_seed,
            max_epoch: request.max_epoch,
            user_signature: request.user_signature,
        };

        self.auto_execute_move_call_filled(Parameters(execute_request)).await
    }

    /// Quote a Cetus action with dev inspect
    #[tool(description = "Simulate a Cetus quote using dev inspect")]
    async fn cetus_quote(
        &self,
        Parameters(request): Parameters<CetusQuoteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = Self::resolve_network(request.network);
        let config = Self::load_cetus_config(None)?;
        let (package_id, module, function) = Self::resolve_cetus_action(
            config,
            &network,
            &request.action,
            request.package_id.clone(),
            request.module.clone(),
            request.function.clone(),
        )?;

        let payload = AutoFillMoveCallRequest {
            sender: request.sender.clone(),
            package: package_id.clone(),
            module: module.clone(),
            function: function.clone(),
            type_args: request.type_args.clone(),
            arguments: request.arguments.clone(),
            gas_budget: Some(1_000_000),
            gas_object_id: None,
            gas_price: None,
        };
        let filled = self.auto_fill_move_call_internal(&payload).await?;
        let tx_data = self
            .client
            .transaction_builder()
            .move_call(
                Self::parse_address(&request.sender)?,
                Self::parse_object_id(&package_id)?,
                &module,
                &function,
                filled
                    .type_args
                    .into_iter()
                    .map(SuiTypeTag::new)
                    .collect::<Vec<_>>(),
                Self::parse_json_args(&filled.arguments)?,
                None,
                1_000_000,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("cetus_quote", e))?;

        let tx_kind = tx_data.as_v1().kind.clone();
        let dev_inspect_result = self
            .client
            .read_api()
            .dev_inspect_transaction_block(
                Self::parse_address(&request.sender)?,
                tx_kind,
                None,
                None,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("cetus_quote", e))?;

        let summary = json!({
            "effects": dev_inspect_result.effects.status().to_string(),
            "results": dev_inspect_result.results.as_ref().map(|items| items.len()),
            "events": dev_inspect_result.events.data.len(),
            "error": dev_inspect_result.error
        });

        let response = Self::pretty_json(&json!({
            "summary": summary,
            "result": dev_inspect_result
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
