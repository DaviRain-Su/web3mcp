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
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

        let type_args = request
            .type_args
            .into_iter()
            .enumerate()
            .map(|(index, arg)| {
                let tag = SuiTypeTag::new(arg);
                if let Err(error) = tag.clone().try_into() as Result<TypeTag, _> {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Invalid type arg at index {}: {}",
                            index, error
                        )),
                        data: None,
                    });
                }
                Ok(tag)
            })
            .collect::<Result<Vec<_>, _>>()?;
        let call_args = Self::parse_json_args(&request.arguments)?;

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
            .map_err(|e| Self::sdk_error("auto_execute_move_call", e))?;

        let tx_bytes = Self::encode_tx_bytes(&tx_data)?;
        let signature_bytes = Self::decode_base64("user_signature", &request.user_signature)?;
        let user_signature = Signature::from_bytes(&signature_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid user signature: {}", e)),
            data: None,
        })?;

        let zk_login_inputs =
            ZkLoginInputs::from_json(&request.zk_login_inputs_json, &request.address_seed)
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid zkLogin inputs: {}", e)),
                    data: None,
                })?;

        let zklogin_authenticator =
            ZkLoginAuthenticator::new(zk_login_inputs, request.max_epoch, user_signature);
        let tx = Transaction::from_generic_sig_data(
            tx_data,
            vec![GenericSignature::ZkLoginAuthenticator(zklogin_authenticator)],
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
            .map_err(|e| Self::sdk_error("auto_execute_move_call", e))?;

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

        let type_args_strings = payload
            .get("type_args")
            .and_then(|value| value.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let arguments = payload
            .get("arguments")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();
        let gas_budget = payload
            .get("gas_budget")
            .and_then(|value| value.as_u64())
            .unwrap_or(request.gas_budget);
        let gas_object_id = payload
            .get("gas_object_id")
            .and_then(|value| value.as_str())
            .map(|s| s.to_string());
        let gas_price = payload
            .get("gas_price")
            .and_then(|value| value.as_u64());

        let type_args = type_args_strings
            .into_iter()
            .enumerate()
            .map(|(index, arg)| {
                let tag = SuiTypeTag::new(arg);
                if let Err(error) = tag.clone().try_into() as Result<TypeTag, _> {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Invalid type arg at index {}: {}",
                            index, error
                        )),
                        data: None,
                    });
                }
                Ok(tag)
            })
            .collect::<Result<Vec<_>, _>>()?;
        let call_args = Self::parse_json_args(&arguments)?;
        let gas = match gas_object_id {
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
                gas_budget,
                gas_price,
            )
            .await
            .map_err(|e| Self::sdk_error("auto_execute_move_call_filled", e))?;

        let tx_bytes = Self::encode_tx_bytes(&tx_data)?;
        let signature_bytes = Self::decode_base64("user_signature", &request.user_signature)?;
        let user_signature = Signature::from_bytes(&signature_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid user signature: {}", e)),
            data: None,
        })?;
        let zk_login_inputs =
            ZkLoginInputs::from_json(&request.zk_login_inputs_json, &request.address_seed)
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid zkLogin inputs: {}", e)),
                    data: None,
                })?;

        let zklogin_authenticator =
            ZkLoginAuthenticator::new(zk_login_inputs, request.max_epoch, user_signature);
        let tx = Transaction::from_generic_sig_data(
            tx_data,
            vec![GenericSignature::ZkLoginAuthenticator(zklogin_authenticator)],
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
            .map_err(|e| Self::sdk_error("auto_execute_move_call_filled", e))?;

        let summary = Self::summarize_transaction(&result);
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("auto_execute_move_call_filled", e))?;
        let module = modules.get(&request.module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Unable to load module schema"),
            data: None,
        })?;
        let function_def = module.exposed_functions.get(&request.function).ok_or_else(|| {
            ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Unable to load function schema"),
                data: None,
            }
        })?;
        let form_schema = Self::move_call_form_schema(
            &request.package,
            &request.module,
            &request.function,
            function_def,
            &modules,
            2,
        );

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
