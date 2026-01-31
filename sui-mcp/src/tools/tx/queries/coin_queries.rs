    /// Auto-generated tool: select coins
    #[tool(description = "Auto-generated tool: select coins")]
    async fn select_coins(
        &self,
        Parameters(request): Parameters<SelectCoinsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let owner = Self::parse_address(&request.owner)?;
        let exclude = Self::parse_object_ids(&request.exclude)?;

        let result = self
            .client
            .coin_read_api()
            .select_coins(owner, request.coin_type, request.amount, exclude)
            .await
            .map_err(|e| Self::sdk_error("select_coins", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get coin metadata
    #[tool(description = "Get metadata for a coin type")]
    async fn get_coin_metadata(
        &self,
        Parameters(request): Parameters<GetCoinMetadataRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .coin_read_api()
            .get_coin_metadata(request.coin_type)
            .await
            .map_err(|e| Self::sdk_error("get_coin_metadata", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get total supply
    #[tool(description = "Get total supply for a coin type")]
    async fn get_total_supply(
        &self,
        Parameters(request): Parameters<GetTotalSupplyRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .coin_read_api()
            .get_total_supply(request.coin_type)
            .await
            .map_err(|e| Self::sdk_error("get_total_supply", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
