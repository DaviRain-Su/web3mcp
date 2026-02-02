    /// Auto-generated tool: get stakes
    #[tool(description = "Auto-generated tool: get stakes")]
    async fn get_stakes(
        &self,
        Parameters(request): Parameters<GetStakesRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let owner = Self::parse_address(&request.owner)?;
        let result = self
            .client
            .governance_api()
            .get_stakes(owner)
            .await
            .map_err(|e| Self::sdk_error("get_stakes", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get committee info
    #[tool(description = "Get committee info for a given epoch")]
    async fn get_committee_info(
        &self,
        Parameters(request): Parameters<GetCommitteeInfoRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let epoch = request.epoch.map(BigInt::from);
        let result = self
            .client
            .governance_api()
            .get_committee_info(epoch)
            .await
            .map_err(|e| Self::sdk_error("get_committee_info", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get latest Sui system state
    #[tool(description = "Get the latest Sui system state summary")]
    async fn get_latest_sui_system_state(&self) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .governance_api()
            .get_latest_sui_system_state()
            .await
            .map_err(|e| Self::sdk_error("get_latest_sui_system_state", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
