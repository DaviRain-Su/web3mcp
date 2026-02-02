    /// Auto-generated tool: get latest checkpoint sequence
    #[tool(description = "Auto-generated tool: get latest checkpoint sequence")]
    async fn get_latest_checkpoint_sequence(&self) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .read_api()
            .get_latest_checkpoint_sequence_number()
            .await
            .map_err(|e| Self::sdk_error("sui_getLatestCheckpointSequenceNumber", e))?;

        let response = format!("Latest checkpoint sequence: {}", result);
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get total transaction count
    #[tool(description = "Get the total number of transactions on the Sui network")]
    async fn get_total_transactions(&self) -> Result<CallToolResult, ErrorData> {
        let result = self
            .client
            .read_api()
            .get_total_transaction_blocks()
            .await
            .map_err(|e| Self::sdk_error("sui_getTotalTransactionBlocks", e))?;

        let response = format!("Total transactions: {}", result);
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
