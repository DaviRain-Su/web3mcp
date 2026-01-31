    /// Auto-generated tool: get reference gas price
    #[tool(description = "Auto-generated tool: get reference gas price")]
    async fn get_reference_gas_price(&self) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .read_api()
            .get_reference_gas_price()
            .await
            .map_err(|e| Self::sdk_error("suix_getReferenceGasPrice", e))?;

        let response = format!("Reference gas price: {}", result);
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
