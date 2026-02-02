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

    /// Get a wallet overview with balances and optional coins
    #[tool(description = "Get wallet overview with balances and optional coin objects")]
    async fn get_wallet_overview(
        &self,
        Parameters(request): Parameters<WalletOverviewRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let address = if let Some(address) = request.address.as_deref() {
            Self::parse_address(address)?
        } else {
            let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
            self.resolve_keystore_signer(&keystore, request.signer.as_deref())?
        };

        let coin_type = request
            .coin_type
            .unwrap_or_else(|| "0x2::sui::SUI".to_string());
        let sui_balance = self
            .client
            .coin_read_api()
            .get_balance(address, Some(coin_type.clone()))
            .await
            .map_err(|e| Self::sdk_error("get_wallet_overview", e))?;
        let all_balances = self
            .client
            .coin_read_api()
            .get_all_balances(address)
            .await
            .map_err(|e| Self::sdk_error("get_wallet_overview", e))?;

        let include_coins = request.include_coins.unwrap_or(false);
        let coins = if include_coins {
            let limit = Self::clamp_limit(request.coins_limit, 20, 50);
            Some(
                self.client
                    .coin_read_api()
                    .get_coins(address, Some(coin_type.clone()), None, Some(limit))
                    .await
                    .map_err(|e| Self::sdk_error("get_wallet_overview", e))?,
            )
        } else {
            None
        };

        let response = Self::pretty_json(&json!({
            "address": address.to_string(),
            "coin_type": coin_type,
            "sui_balance": sui_balance,
            "balances": all_balances,
            "coins": coins
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
