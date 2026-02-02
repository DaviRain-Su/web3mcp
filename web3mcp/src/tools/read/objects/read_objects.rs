    /// Auto-generated tool: get object
    #[tool(description = "Auto-generated tool: get object")]
    async fn get_object(
        &self,
        Parameters(request): Parameters<GetObjectRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let object_id = Self::parse_object_id(&request.object_id)?;
        let mut options = SuiObjectDataOptions::new()
            .with_type()
            .with_owner()
            .with_previous_transaction();

        options.show_storage_rebate = true;

        if request.show_content.unwrap_or(true) {
            options = options.with_content();
        }

        let result = self
            .client
            .read_api()
            .get_object_with_options(object_id, options)
            .await
            .map_err(|e| Self::sdk_error("sui_getObject", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get objects owned by an address
    #[tool(description = "Get all objects owned by a Sui address")]
    async fn get_owned_objects(
        &self,
        Parameters(request): Parameters<GetOwnedObjectsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let address = Self::parse_address(&request.address)?;
        let options = SuiObjectDataOptions::new().with_type().with_owner();
        let query = SuiObjectResponseQuery::new(None, Some(options));
        let limit = Self::clamp_limit(request.limit, 50, 50);

        let result = self
            .client
            .read_api()
            .get_owned_objects(address, Some(query), None, Some(limit))
            .await
            .map_err(|e| Self::sdk_error("suix_getOwnedObjects", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
