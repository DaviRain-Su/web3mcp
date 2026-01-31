    /// Auto-generated tool: suggest move call inputs
    #[tool(description = "Auto-generated tool: suggest move call inputs")]
    async fn suggest_move_call_inputs(
        &self,
        Parameters(request): Parameters<SuggestMoveCallInputsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let package = Self::parse_object_id(&request.package)?;
        let limit = request.limit.unwrap_or(200).min(200);

        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error("suggest_move_call_inputs", e))?;
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

        let options = SuiObjectDataOptions::new().with_type().with_owner();
        let query = SuiObjectResponseQuery::new(None, Some(options));
        let owned = self
            .client
            .read_api()
            .get_owned_objects(sender, Some(query), None, Some(limit))
            .await
            .map_err(|e| Self::sdk_error("suggest_move_call_inputs", e))?;

        let mut owned_metadata: Vec<(ObjectID, StructTag, Owner)> = Vec::new();
        for item in owned.data {
            if let Some(data) = item.data {
                if let Some(object_type) = data.type_ {
                    if let Ok(struct_tag) = object_type.try_into() {
                        if let Some(owner) = data.owner.clone() {
                            owned_metadata.push((data.object_id, struct_tag, owner));
                        }
                    }
                }
            }
        }

        let mut type_mapping: HashMap<usize, TypeTag> = HashMap::new();
        let mut type_conflicts = Vec::new();
        let mut parameters = Vec::new();
        let mut warnings = Vec::new();

        for (index, param) in function_def.parameters.iter().enumerate() {
            let mut candidates: Vec<Value> = Vec::new();
            for (object_id, struct_tag, owner) in owned_metadata.iter() {
                if Self::match_type_param(
                    param,
                    &TypeTag::Struct(Box::new(struct_tag.clone())),
                    &mut HashMap::<usize, TypeTag>::new(),
                ) {
                    let owner_kind = match owner {
                        Owner::AddressOwner(_) => "owned",
                        Owner::ObjectOwner(_) => "object_owner",
                        Owner::Shared { .. } => "shared",
                        Owner::Immutable => "immutable",
                        Owner::ConsensusAddressOwner { .. } => "consensus",
                    };
                    candidates.push(json!({
                        "object_id": object_id.to_string(),
                        "object_type": struct_tag.to_string(),
                        "owner_kind": owner_kind,
                    }));

                    if let Some(mapping) = Self::infer_type_args(param, struct_tag) {
                        if !Self::merge_type_args(&mut type_mapping, mapping) {
                            type_conflicts.push(json!({
                                "index": index,
                                "type": Self::format_move_type(param),
                                "object_id": object_id.to_string(),
                                "object_type": struct_tag.to_string(),
                                "reason": "type argument conflict"
                            }));
                        }
                    }
                }
            }

            let (kind, _, is_object) = Self::move_param_hint(param);
            let (requires_mutable, owner_kinds) = Self::param_requirements(param);

            let preferred_order = if requires_mutable {
                vec!["owned", "shared", "object_owner", "consensus"]
            } else {
                vec!["owned", "immutable", "shared", "object_owner", "consensus"]
            };
            let recommended_object = preferred_order
                .iter()
                .find_map(|kind| {
                    candidates.iter().find_map(|candidate| {
                        candidate
                            .get("owner_kind")
                            .and_then(|value| value.as_str())
                            .filter(|value| value == kind)
                            .map(|_| candidate.clone())
                    })
                });

            if is_object && candidates.is_empty() {
                warnings.push(json!({
                    "index": index,
                    "type": Self::format_move_type(param),
                    "message": "No matching owned objects found for this parameter"
                }));
            }

            parameters.push(json!({
                "index": index,
                "type": Self::format_move_type(param),
                "kind": kind,
                "is_object": is_object,
                "requires_mutable": requires_mutable,
                "expected_owner_kinds": owner_kinds,
                "object_candidates": candidates,
                "recommended_object": recommended_object,
            }));
        }

        let type_args = Self::type_args_from_mapping(&type_mapping, function_def.type_parameters.len());
        let gas = if let Some(gas_budget) = request.gas_budget {
            let gas_price = self
                .client
                .read_api()
                .get_reference_gas_price()
                .await
                .map_err(|e| Self::sdk_error("suggest_move_call_inputs", e))?;
            let gas_object = self
                .client
                .transaction_builder()
                .select_gas(sender, None, gas_budget, vec![], gas_price)
                .await
                .map_err(|e| Self::sdk_error("suggest_move_call_inputs", e))?;
            Some(json!({
                "gas_budget": gas_budget,
                "gas_price": gas_price,
                "gas_object": {
                    "object_id": gas_object.0,
                    "version": gas_object.1,
                    "digest": gas_object.2
                }
            }))
        } else {
            None
        };

        let response = json!({
            "package": request.package,
            "module": request.module,
            "function": request.function,
            "type_args": type_args,
            "parameters": parameters,
            "type_conflicts": type_conflicts,
            "warnings": warnings,
            "gas": gas
        });
        let response = Self::pretty_json(&response)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
