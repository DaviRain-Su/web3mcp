    /// Auto-generated tool: query transaction blocks
    #[tool(description = "Auto-generated tool: query transaction blocks")]
    async fn query_transaction_blocks(
        &self,
        Parameters(request): Parameters<QueryTransactionBlocksRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let filter = match request.filter {
            Some(value) => Some(
                serde_json::from_value::<TransactionFilter>(value).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid transaction filter: {}", e)),
                    data: None,
                })?,
            ),
            None => None,
        };
        let options = Self::tx_options_from_request(request.options);
        let query = SuiTransactionBlockResponseQuery::new(filter, Some(options));
        let cursor = match request.cursor {
            Some(cursor) => Some(Self::parse_digest(&cursor)?),
            None => None,
        };
        let limit = request.limit.map(|limit| Self::clamp_limit(Some(limit), limit, 50));
        let descending = request.descending_order.unwrap_or(false);

        let result = self
            .client
            .read_api()
            .query_transaction_blocks(query, cursor, limit, descending)
            .await
            .map_err(|e| Self::sdk_error("query_transaction_blocks", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Multi-get transaction blocks
    #[tool(description = "Fetch multiple transaction blocks by digest")]
    async fn multi_get_transactions(
        &self,
        Parameters(request): Parameters<MultiGetTransactionsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let digests = request
            .digests
            .iter()
            .map(|digest| Self::parse_digest(digest))
            .collect::<Result<Vec<_>, _>>()?;
        let options = Self::tx_options_from_request(request.options);

        let result = self
            .client
            .read_api()
            .multi_get_transactions_with_options(digests, options)
            .await
            .map_err(|e| Self::sdk_error("multi_get_transactions", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
