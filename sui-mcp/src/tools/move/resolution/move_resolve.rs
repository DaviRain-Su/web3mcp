    /// Auto-generated tool: resolve move call args
    #[tool(description = "Auto-generated tool: resolve move call args")]
    async fn resolve_move_call_args(
        &self,
        Parameters(request): Parameters<ResolveMoveCallArgsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let package = Self::parse_object_id(&request.package)?;
        let module = Identifier::from_str(&request.module).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid module: {}", e)),
            data: None,
        })?;
        let function = Identifier::from_str(&request.function).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid function: {}", e)),
            data: None,
        })?;

        let type_args = Self::parse_type_args_to_typetag(request.type_args)?;

        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("resolve_move_call_args", e))?;
        let module_def = modules.get(&request.module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Module not found: {}", request.module)),
            data: None,
        })?;
        let function_def = module_def
            .exposed_functions
            .get(&request.function)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Function not found: {}", request.function)),
                data: None,
            })?;

        if request.arguments.len() > function_def.parameters.len() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Too many arguments for function"),
                data: None,
            });
        }

        for (index, (value, param)) in request
            .arguments
            .iter()
            .zip(function_def.parameters.iter())
            .enumerate()
        {
            if let Err(_) = Self::validate_pure_arg(param, value) {
                let value_str = serde_json::to_string(value).unwrap_or_else(|_| "<unprintable>".to_string());
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Invalid argument at index {}: expected {}, got {}",
                        index,
                        Self::format_move_type(param),
                        value_str
                    )),
                    data: None,
                });
            }
        }

        let call_args = Self::parse_json_args(&request.arguments)?;

        let mut builder = ProgrammableTransactionBuilder::new();
        self
            .client
            .transaction_builder()
            .resolve_and_checks_json_args(&mut builder, package, &module, &function, &type_args, call_args)
            .await
            .map_err(|e| Self::sdk_error("resolve_move_call_args", e))?;

        let pt = builder.finish();
        let resolved = pt
            .inputs
            .into_iter()
            .map(|arg| match arg {
                CallArg::Pure(bytes) => json!({
                    "kind": "pure",
                    "bcs_base64": Base64Engine.encode(bytes)
                }),
                CallArg::Object(object_arg) => match object_arg {
                    ObjectArg::ImmOrOwnedObject((object_id, version, digest)) => json!({
                        "kind": "object",
                        "object_id": object_id.to_string(),
                        "version": version,
                        "digest": digest
                    }),
                    ObjectArg::Receiving((object_id, version, digest)) => json!({
                        "kind": "receiving",
                        "object_id": object_id.to_string(),
                        "version": version,
                        "digest": digest
                    }),
                    ObjectArg::SharedObject {
                        id,
                        initial_shared_version,
                        mutability,
                    } => json!({
                        "kind": "shared",
                        "object_id": id.to_string(),
                        "initial_shared_version": initial_shared_version,
                        "mutability": format!("{:?}", mutability)
                    }),
                },
                CallArg::FundsWithdrawal(withdrawal) => json!({
                    "kind": "funds_withdrawal",
                    "withdrawal": format!("{:?}", withdrawal)
                }),
            })
            .collect::<Vec<_>>();

        let response = Self::pretty_json(&json!({"inputs": resolved}))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Prepare a Move call for zkLogin signing
    #[tool(description = "Build a Move call transaction and return tx bytes for signing")]
    async fn prepare_move_call(
        &self,
        Parameters(request): Parameters<PrepareMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let package = Self::parse_object_id(&request.package)?;
        let gas = match request.gas_object_id {
            Some(gas_id) => Some(Self::parse_object_id(&gas_id)?),
            None => None,
        };

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
                "prepare_move_call",
            )
            .await?;

        let tx_bytes = Self::encode_tx_bytes(&tx_data)?;
        let response = Self::pretty_json(&json!({
            "tx_bytes": tx_bytes,
            "intent_scope": "transaction",
            "signer": request.sender,
            "gas_budget": request.gas_budget
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Generate a Move call payload template
    #[tool(description = "Generate a Move call payload with default arguments and <auto> placeholders")]
    async fn generate_move_call_payload(
        &self,
        Parameters(request): Parameters<GenerateMoveCallPayloadRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let package = Self::parse_object_id(&request.package)?;
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("generate_move_call_payload", e))?;
        let module = modules.get(&request.module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Module not found: {}", request.module)),
            data: None,
        })?;
        let function_def = module
            .exposed_functions
            .get(&request.function)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Function not found: {}", request.function)),
                data: None,
            })?;

        let type_args = (0..function_def.type_parameters.len())
            .map(|index| format!("<T{}>", index))
            .collect::<Vec<_>>();
        let arguments = function_def
            .parameters
            .iter()
            .map(|param| {
                let (_kind, placeholder, is_object) = Self::move_param_hint(param);
                if is_object {
                    json!("<auto>")
                } else {
                    placeholder
                }
            })
            .collect::<Vec<_>>();

        let form_schema = self
            .build_move_call_form_schema(
                package,
                &request.package,
                &request.module,
                &request.function,
                2,
                "generate_move_call_payload",
            )
            .await?;

        let payload = json!({
            "sender": request.sender,
            "package": request.package,
            "module": request.module,
            "function": request.function,
            "type_args": type_args,
            "arguments": arguments,
            "gas_budget": request.gas_budget,
            "gas_price": request.gas_price,
            "gas_object_id": null
        });

        let response = Self::pretty_json(&json!({
            "payload": payload,
            "form_schema": form_schema
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
