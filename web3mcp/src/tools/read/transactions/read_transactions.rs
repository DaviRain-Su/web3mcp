    /// Auto-generated tool: get transaction
    #[tool(description = "Auto-generated tool: get transaction")]
    async fn get_transaction(
        &self,
        Parameters(request): Parameters<GetTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let digest = Self::parse_digest(&request.digest)?;
        let options = SuiTransactionBlockResponseOptions::new()
            .with_input()
            .with_effects()
            .with_events()
            .with_object_changes()
            .with_balance_changes();

        let result = self
            .client
            .read_api()
            .get_transaction_with_options(digest, options)
            .await
            .map_err(|e| Self::sdk_error("sui_getTransactionBlock", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
