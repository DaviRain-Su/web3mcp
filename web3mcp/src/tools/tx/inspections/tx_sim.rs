    /// Auto-generated tool: dry run transaction
    #[tool(description = "Auto-generated tool: dry run transaction")]
    async fn dry_run_transaction(
        &self,
        Parameters(request): Parameters<DryRunTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let tx_bytes = Self::decode_base64("tx_bytes", &request.tx_bytes)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;

        let result = self
            .client
            .read_api()
            .dry_run_transaction_block(tx_data)
            .await
            .map_err(|e| Self::sdk_error("dry_run_transaction", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Dev inspect a transaction
    #[tool(description = "Dev inspect a transaction without enforcing checks")]
    async fn dev_inspect_transaction(
        &self,
        Parameters(request): Parameters<DevInspectTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = Self::parse_address(&request.sender)?;
        let tx_bytes = Self::decode_base64("tx_bytes", &request.tx_bytes)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;
        let tx_kind = tx_data.as_v1().kind.clone();
        let gas_price = request.gas_price.map(BigInt::from);
        let epoch = request.epoch.map(BigInt::from);

        let result = self
            .client
            .read_api()
            .dev_inspect_transaction_block(sender, tx_kind, gas_price, epoch, None)
            .await
            .map_err(|e| Self::sdk_error("dev_inspect_transaction", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
