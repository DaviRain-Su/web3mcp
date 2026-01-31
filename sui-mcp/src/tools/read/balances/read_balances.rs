    /// Auto-generated tool: get balance
    #[tool(description = "Auto-generated tool: get balance")]
    async fn get_balance(
        &self,
        Parameters(request): Parameters<GetBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let address = Self::parse_address(&request.address)?;
        let coin_type = request.coin_type.unwrap_or_else(|| "0x2::sui::SUI".to_string());
        let result = self
            .client
            .coin_read_api()
            .get_balance(address, Some(coin_type))
            .await
            .map_err(|e| Self::sdk_error("suix_getBalance", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get all balances for an address
    #[tool(description = "Get all coin balances for a Sui address")]
    async fn get_all_balances(
        &self,
        Parameters(request): Parameters<GetAllBalancesRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let address = Self::parse_address(&request.address)?;
        let result = self
            .client
            .coin_read_api()
            .get_all_balances(address)
            .await
            .map_err(|e| Self::sdk_error("suix_getAllBalances", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
