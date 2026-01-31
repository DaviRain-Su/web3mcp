    /// Auto-generated tool: auto fill move call
    #[tool(description = "Auto-generated tool: auto fill move call")]
    async fn auto_fill_move_call(
        &self,
        Parameters(request): Parameters<AutoFillMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let filled = self.auto_fill_move_call_internal(&request).await?;

        let payload = json!({
            "sender": request.sender,
            "package": request.package,
            "module": request.module,
            "function": request.function,
            "type_args": filled.type_args,
            "arguments": filled.arguments,
            "gas_budget": filled.gas_budget,
            "gas_object_id": filled.gas_object_id,
            "gas_price": filled.gas_price
        });

        let response = Self::pretty_json(&json!({
            "payload": payload,
            "warnings": filled.warnings,
            "gas": filled.gas
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Auto prepare a Move call (auto-fill + build tx bytes)
    #[tool(description = "Auto-fill a Move call and return tx bytes for signing")]
    async fn auto_prepare_move_call(
        &self,
        Parameters(request): Parameters<AutoPrepareMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let fill_request = AutoFillMoveCallRequest {
            sender: request.sender.clone(),
            package: request.package.clone(),
            module: request.module.clone(),
            function: request.function.clone(),
            type_args: request.type_args.clone(),
            arguments: request.arguments.clone(),
            gas_budget: request.gas_budget,
            gas_object_id: request.gas_object_id.clone(),
            gas_price: request.gas_price,
        };

        let filled = self.auto_fill_move_call_internal(&fill_request).await?;
        let gas_budget = filled.gas_budget.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("gas_budget is required for auto_prepare_move_call"),
            data: None,
        })?;

        let prepare_request = PrepareMoveCallRequest {
            sender: request.sender.clone(),
            package: request.package.clone(),
            module: request.module.clone(),
            function: request.function.clone(),
            type_args: filled.type_args,
            arguments: filled.arguments,
            gas_budget,
            gas_object_id: filled.gas_object_id,
            gas_price: filled.gas_price,
        };

        let response = self.prepare_move_call(Parameters(prepare_request)).await?;
        Ok(response)
    }

    /// Auto execute a Move call with zkLogin signature
    #[tool(description = "Build and execute a Move call with zkLogin signature")]
    async fn auto_execute_move_call(
        &self,
        Parameters(request): Parameters<AutoExecuteMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let package = Self::parse_object_id(&request.package)?;
        let gas = request
            .gas_object_id
            .as_deref()
            .map(Self::parse_object_id)
            .transpose()?;

        let type_args = Self::parse_type_args(request.type_args)?;
        let call_args = Self::parse_json_args(&request.arguments)?;

        let tx_data = self
            .build_move_call_tx_data(
                sender,
                package,
                &request.module,
                &request.function,
                type_args,
                call_args,
                gas,
                request.gas_budget,
                request.gas_price,
                "auto_execute_move_call",
            )
            .await?;

        let (tx_bytes, result) = self
            .execute_tx_with_zklogin(
                tx_data,
                &request.user_signature,
                &request.zk_login_inputs_json,
                &request.address_seed,
                request.max_epoch,
                "auto_execute_move_call",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "tx_bytes": tx_bytes,
            "result": result,
            "summary": summary
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Auto execute a Move call using auto-fill for missing args
    #[tool(description = "Auto-fill a Move call and execute it with zkLogin signature")]
    async fn auto_execute_move_call_filled(
        &self,
        Parameters(request): Parameters<AutoExecuteMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let fill_request = AutoFillMoveCallRequest {
            sender: request.sender.clone(),
            package: request.package.clone(),
            module: request.module.clone(),
            function: request.function.clone(),
            type_args: Some(request.type_args.clone()),
            arguments: request.arguments.clone(),
            gas_budget: Some(request.gas_budget),
            gas_object_id: request.gas_object_id.clone(),
            gas_price: request.gas_price,
        };

        let filled = self.auto_fill_move_call_internal(&fill_request).await?;
        let payload = json!({
            "sender": request.sender,
            "package": request.package,
            "module": request.module,
            "function": request.function,
            "type_args": filled.type_args,
            "arguments": filled.arguments,
            "gas_budget": filled.gas_budget.unwrap_or(request.gas_budget),
            "gas_object_id": filled.gas_object_id,
            "gas_price": filled.gas_price.or(request.gas_price)
        });

        let sender = Self::parse_address(&request.sender)?;
        let package = Self::parse_object_id(&request.package)?;

        let (type_args, call_args, gas_budget, gas, gas_price) =
            Self::parse_execute_payload(&payload, request.gas_budget)?;

        let tx_data = self
            .build_move_call_tx_data(
                sender,
                package,
                &request.module,
                &request.function,
                type_args,
                call_args,
                gas,
                gas_budget,
                gas_price,
                "auto_execute_move_call_filled",
            )
            .await?;

        let (tx_bytes, result) = self
            .execute_tx_with_zklogin(
                tx_data,
                &request.user_signature,
                &request.zk_login_inputs_json,
                &request.address_seed,
                request.max_epoch,
                "auto_execute_move_call_filled",
            )
            .await?;

        let summary = Self::summarize_transaction(&result);
        let form_schema = self
            .build_move_call_form_schema(
                package,
                &request.package,
                &request.module,
                &request.function,
                2,
                "auto_execute_move_call_filled",
            )
            .await?;

        let response = Self::pretty_json(&json!({
            "payload": payload,
            "warnings": filled.warnings,
            "form_schema": form_schema,
            "result": result,
            "summary": summary,
            "tx_bytes": tx_bytes
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // Move automation helper methods moved to src/tools/move/automation/move_auto_helpers.rs

