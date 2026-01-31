    /// Auto-generated tool: cetus get config
    #[tool(description = "Auto-generated tool: cetus get config")]
    async fn cetus_get_config(
        &self,
        Parameters(request): Parameters<CetusConfigRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let config = Self::load_cetus_config(request.path.clone())?;
        let response = Self::pretty_json(&json!({
            "config": config,
            "example": "config/cetus.example.json",
            "path": request.path
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get Cetus config example
    #[tool(description = "Get an example Cetus config template")]
    async fn cetus_get_config_template(&self) -> Result<CallToolResult, ErrorData> {
        let template = fs::read_to_string("config/cetus.example.json").map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read template: {}", e)),
            data: None,
        })?;
        let response = Self::pretty_json(&json!({
            "template": serde_json::from_str::<Value>(&template).unwrap_or(Value::String(template))
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Generate a Cetus config for a network
    #[tool(description = "Generate a Cetus config snippet for a network")]
    async fn cetus_generate_config(
        &self,
        Parameters(request): Parameters<CetusGenerateConfigRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let snippet = json!({
            "networks": {
                request.network.clone(): {
                    "package_id": request.package_id,
                    "actions": {
                        "swap": { "module": "pool", "function": "swap" },
                        "swap_exact_in": { "module": "pool", "function": "swap_exact_in" },
                        "swap_exact_out": { "module": "pool", "function": "swap_exact_out" },
                        "add_liquidity": { "module": "pool", "function": "add_liquidity" },
                        "remove_liquidity": { "module": "pool", "function": "remove_liquidity" },
                        "open_position": { "module": "position", "function": "open_position" },
                        "close_position": { "module": "position", "function": "close_position" },
                        "increase_liquidity": { "module": "position", "function": "increase_liquidity" },
                        "decrease_liquidity": { "module": "position", "function": "decrease_liquidity" },
                        "collect_fees": { "module": "position", "function": "collect_fees" },
                        "quote": { "module": "pool", "function": "quote" }
                    }
                }
            }
        });
        let response = Self::pretty_json(&json!({
            "snippet": snippet
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Generate a Cetus action payload template
    #[tool(description = "Generate a Cetus action payload template")]
    async fn cetus_generate_payload(
        &self,
        Parameters(request): Parameters<CetusGeneratePayloadRequest>,
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

        let payload_request = GenerateMoveCallPayloadRequest {
            sender: request.sender,
            package: package_id,
            module,
            function,
            gas_budget: request.gas_budget,
            gas_price: request.gas_price,
        };

        let response = self
            .generate_move_call_payload(Parameters(payload_request))
            .await?;
        Ok(response)
    }

    /// Validate a Cetus payload against Move function signature
    #[tool(description = "Validate a Cetus action payload")]
    async fn cetus_validate_payload(
        &self,
        Parameters(request): Parameters<CetusValidatePayloadRequest>,
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

        let resolve_request = ResolveMoveCallArgsRequest {
            package: package_id,
            module,
            function,
            type_args: request.type_args.unwrap_or_default(),
            arguments: request.arguments,
        };

        self.resolve_move_call_args(Parameters(resolve_request)).await
    }

    /// Provide Cetus action parameter hints
    #[tool(description = "Get parameter hints for a Cetus action")]
    async fn cetus_action_params(
        &self,
        Parameters(request): Parameters<CetusActionParamsRequest>,
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

        let package = Self::parse_object_id(&package_id)?;
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("cetus_action_params", e))?;
        let module_def = modules.get(&module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Module not found: {}", module)),
            data: None,
        })?;
        let function_def = module_def
            .exposed_functions
            .get(&function)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Function not found: {}", function)),
                data: None,
            })?;

        let parameters = function_def
            .parameters
            .iter()
            .enumerate()
            .map(|(index, ty)| {
                let (kind, _, is_object) = Self::move_param_hint(ty);
                let (requires_mutable, owner_kinds) = Self::param_requirements(ty);
                json!({
                    "index": index,
                    "type": Self::format_move_type(ty),
                    "kind": kind,
                    "is_object": is_object,
                    "requires_mutable": requires_mutable,
                    "expected_owner_kinds": owner_kinds
                })
            })
            .collect::<Vec<_>>();

        let template = Self::build_move_call_template(&package_id, &module, &function, function_def);
        let form_schema = Self::move_call_form_schema(&package_id, &module, &function, function_def, &modules, 2);

        let response = Self::pretty_json(&json!({
            "package": package_id,
            "module": module,
            "function": function,
            "action": request.action,
            "parameters": parameters,
            "template": template,
            "form_schema": form_schema
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
