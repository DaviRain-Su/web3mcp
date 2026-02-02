    /// Auto-generated tool: get dynamic fields
    #[tool(description = "Auto-generated tool: get dynamic fields")]
    async fn get_dynamic_fields(
        &self,
        Parameters(request): Parameters<GetDynamicFieldsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let object_id = Self::parse_object_id(&request.object_id)?;
        let cursor = match request.cursor {
            Some(cursor) => Some(Self::parse_object_id(&cursor)?),
            None => None,
        };
        let limit = request.limit.map(|limit| Self::clamp_limit(Some(limit), limit, 50));

        let result = self
            .client
            .read_api()
            .get_dynamic_fields(object_id, cursor, limit)
            .await
            .map_err(|e| Self::sdk_error("get_dynamic_fields", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Recursively resolve dynamic fields
    #[tool(description = "Recursively resolve dynamic fields")]
    async fn get_dynamic_field_tree(
        &self,
        Parameters(request): Parameters<GetDynamicFieldTreeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let object_id = Self::parse_object_id(&request.object_id)?;
        let max_depth = request.max_depth.unwrap_or(2);
        let limit = request.limit.unwrap_or(50).min(50);

        let tree = self
            .fetch_dynamic_field_tree(object_id, 0, max_depth, limit)
            .await?;

        let response = Self::pretty_json(&tree)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get a dynamic field object
    #[tool(description = "Get a dynamic field object by name")]
    async fn get_dynamic_field_object(
        &self,
        Parameters(request): Parameters<GetDynamicFieldObjectRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let parent_object_id = Self::parse_object_id(&request.parent_object_id)?;
        let name = Self::parse_dynamic_field_name(&request.name_type, request.name_value)?;

        let result = self
            .client
            .read_api()
            .get_dynamic_field_object(parent_object_id, name)
            .await
            .map_err(|e| Self::sdk_error("get_dynamic_field_object", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get Move object BCS
    #[tool(description = "Get Move object BCS bytes")]
    async fn get_move_object_bcs(
        &self,
        Parameters(request): Parameters<GetMoveObjectBcsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let object_id = Self::parse_object_id(&request.object_id)?;
        let result = self
            .client
            .read_api()
            .get_move_object_bcs(object_id)
            .await
            .map_err(|e| Self::sdk_error("get_move_object_bcs", e))?;

        let response = json!({
            "bcs_base64": Base64Engine.encode(result),
        });
        let response = Self::pretty_json(&response)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get past object data
    #[tool(description = "Get a past version of an object")]
    async fn get_past_object(
        &self,
        Parameters(request): Parameters<GetPastObjectRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let object_id = Self::parse_object_id(&request.object_id)?;
        let version = SequenceNumber::from(request.version);
        let options = Self::object_options_from_request(request.options);

        let result = self
            .client
            .read_api()
            .try_get_parsed_past_object(object_id, version, options)
            .await
            .map_err(|e| Self::sdk_error("get_past_object", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Multi-get past object data
    #[tool(description = "Get past versions of multiple objects")]
    async fn multi_get_past_objects(
        &self,
        Parameters(request): Parameters<MultiGetPastObjectsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let options = Self::object_options_from_request(request.options);
        let objects = request
            .objects
            .into_iter()
            .map(|item| {
                let object_id = Self::parse_object_id(&item.object_id)?;
                let version = SequenceNumber::from(item.version);
                Ok(sui_json_rpc_types::SuiGetPastObjectRequest { object_id, version })
            })
            .collect::<Result<Vec<_>, ErrorData>>()?;

        let result = self
            .client
            .read_api()
            .try_multi_get_parsed_past_object(objects, options)
            .await
            .map_err(|e| Self::sdk_error("multi_get_past_objects", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get all coins for an owner
    #[tool(description = "Get all coins for an owner")]
    async fn get_all_coins(
        &self,
        Parameters(request): Parameters<GetAllCoinsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let owner = Self::parse_address(&request.owner)?;
        let limit = request.limit.map(|limit| Self::clamp_limit(Some(limit), limit, 200));

        let result = self
            .client
            .coin_read_api()
            .get_all_coins(owner, request.cursor, limit)
            .await
            .map_err(|e| Self::sdk_error("get_all_coins", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
