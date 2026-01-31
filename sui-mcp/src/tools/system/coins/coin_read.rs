    /// Auto-generated tool: get coins
    #[tool(description = "Auto-generated tool: get coins")]
    async fn get_coins(
        &self,
        Parameters(request): Parameters<GetCoinsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let address = Self::parse_address(&request.address)?;
        let coin_type = request.coin_type.unwrap_or_else(|| "0x2::sui::SUI".to_string());
        let limit = Self::clamp_limit(request.limit, 50, 50);

        let result = self
            .client
            .coin_read_api()
            .get_coins(address, Some(coin_type), None, Some(limit))
            .await
            .map_err(|e| Self::sdk_error("suix_getCoins", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
