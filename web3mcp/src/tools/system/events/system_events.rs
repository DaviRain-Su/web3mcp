    /// Auto-generated tool: query transaction events
    #[tool(description = "Auto-generated tool: query transaction events")]
    async fn query_transaction_events(
        &self,
        Parameters(request): Parameters<QueryEventsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let digest = Self::parse_digest(&request.digest)?;
        let filter = EventFilter::Transaction(digest);

        let result = self
            .client
            .event_api()
            .query_events(filter, None, None, false)
            .await
            .map_err(|e| Self::sdk_error("suix_queryEvents", e))?;

        let response = Self::pretty_json(&result)?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
