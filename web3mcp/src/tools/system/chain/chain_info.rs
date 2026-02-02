    /// Auto-generated tool: get chain identifier
    #[tool(description = "Auto-generated tool: get chain identifier")]
    async fn get_chain_identifier(&self) -> Result<CallToolResult, ErrorData> {
        let chain_id = self
            .client
            .read_api()
            .get_chain_identifier()
            .await
            .map_err(|e| Self::sdk_error("sui_getChainIdentifier", e))?;

        let response = format!("Chain identifier: {}", chain_id);
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get protocol configuration
    #[tool(description = "Get the protocol configuration for the Sui network")]
    async fn get_protocol_config(&self) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .read_api()
            .get_protocol_config(None)
            .await
            .map_err(|e| Self::sdk_error("sui_getProtocolConfig", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
