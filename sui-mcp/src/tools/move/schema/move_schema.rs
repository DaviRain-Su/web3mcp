    /// Auto-generated tool: get normalized move modules
    #[tool(description = "Auto-generated tool: get normalized move modules")]
    async fn get_normalized_move_modules(
        &self,
        Parameters(request): Parameters<GetNormalizedMoveModulesRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let package = Self::parse_object_id(&request.package)?;
        let result = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("get_normalized_move_modules", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Describe a Move function and build a call template
    #[tool(description = "Describe a Move function and generate a move_call template")]
    async fn describe_move_function(
        &self,
        Parameters(request): Parameters<DescribeMoveFunctionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let package = Self::parse_object_id(&request.package)?;
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("describe_move_function", e))?;

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

        let template = Self::build_move_call_template(
            &request.package,
            &request.module,
            &request.function,
            function_def,
        );
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
                    "expected_owner_kinds": owner_kinds,
                })
            })
            .collect::<Vec<_>>();

        let form_schema = Self::move_call_form_schema(
            &request.package,
            &request.module,
            &request.function,
            function_def,
            &modules,
            2,
        );

        let response = json!({
            "package": request.package,
            "module": request.module,
            "function": request.function,
            "is_entry": function_def.is_entry,
            "visibility": format!("{:?}", function_def.visibility),
            "type_parameters": function_def.type_parameters.len(),
            "parameters": parameters,
            "template": template,
            "form_schema": form_schema
        });
        let response = Self::pretty_json(&response)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Generate call templates for entry functions in a module or package
    #[tool(description = "Generate move_call templates from normalized modules")]
    async fn generate_module_templates(
        &self,
        Parameters(request): Parameters<GenerateModuleTemplatesRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let package = Self::parse_object_id(&request.package)?;
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("generate_module_templates", e))?;
        let entry_only = request.entry_only.unwrap_or(true);

        let mut templates = Vec::new();
        for (module_name, module) in modules.iter() {
            if let Some(filter_module) = &request.module {
                if filter_module != module_name {
                    continue;
                }
            }

            for (function_name, function_def) in module.exposed_functions.iter() {
                if entry_only && !function_def.is_entry {
                    continue;
                }

                templates.push(json!({
                    "package": request.package,
                    "module": module_name,
                    "function": function_name,
                    "is_entry": function_def.is_entry,
                    "template": Self::build_move_call_template(
                        &request.package,
                        module_name,
                        function_name,
                        function_def,
                    ),
                    "form_schema": Self::move_call_form_schema(
                        &request.package,
                        module_name,
                        function_name,
                        function_def,
                        &modules,
                        2,
                    )
                }));
            }
        }

        let response = Self::pretty_json(&json!({"templates": templates}))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Suggest Move call methods for a given object
    #[tool(description = "Suggest callable entry functions for an object")]
    async fn suggest_object_methods(
        &self,
        Parameters(request): Parameters<SuggestObjectMethodsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let object_id = Self::parse_object_id(&request.object_id)?;
        let options = SuiObjectDataOptions::new().with_type();
        let object = self
            .client
            .read_api()
            .get_object_with_options(object_id, options)
            .await
            .map_err(|e| Self::sdk_error("suggest_object_methods", e))?;

        let object_data = object.data.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Object data not available"),
            data: None,
        })?;

        let object_type = object_data.type_.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Object type not available"),
            data: None,
        })?;

        let struct_tag: StructTag = object_type.try_into().map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Object is not a Move struct: {}", e)),
            data: None,
        })?;

        let package_hex = struct_tag.address.to_hex_literal();
        let package_id = ObjectID::from_hex_literal(&package_hex).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid package id from object type: {}", e)),
            data: None,
        })?;
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package_id)
            .await
            .map_err(|e| Self::sdk_error("suggest_object_methods", e))?;

        let module_name = struct_tag.module.to_string();
        let module = modules.get(&module_name).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Module not found: {}", module_name)),
            data: None,
        })?;

        let mut methods = Vec::new();
        for (function_name, function_def) in module.exposed_functions.iter() {
            if !function_def.is_entry {
                continue;
            }
            let first_param = function_def.parameters.first();
            if let Some(param) = first_param {
                if Self::is_object_param_match(param, &struct_tag) {
                    methods.push(json!({
                        "package": package_hex,
                        "module": module_name,
                        "function": function_name,
                        "template": Self::build_move_call_template(
                            &package_hex,
                            &module_name,
                            function_name,
                            function_def,
                        )
                    }));
                }
            }
        }

        let response = json!({
            "object_id": request.object_id,
            "object_type": struct_tag.to_string(),
            "module": module_name,
            "package": package_hex,
            "methods": methods,
        });
        let response = Self::pretty_json(&response)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Generate a Move call form schema
    #[tool(description = "Generate a JSON schema for a Move call form")]
    async fn generate_move_call_form_schema(
        &self,
        Parameters(request): Parameters<GenerateMoveCallFormSchemaRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let package = Self::parse_object_id(&request.package)?;
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("generate_move_call_form_schema", e))?;
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

        let max_depth = request.max_struct_depth.unwrap_or(2);
        let schema = Self::move_call_form_schema(
            &request.package,
            &request.module,
            &request.function,
            function_def,
            &modules,
            max_depth,
        );
        let response = Self::pretty_json(&schema)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
