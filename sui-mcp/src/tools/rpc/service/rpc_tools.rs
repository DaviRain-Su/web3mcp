    /// Auto-generated tool: rpc service info
    #[tool(description = "Auto-generated tool: rpc service info")]
    async fn rpc_service_info(
        &self,
        Parameters(request): Parameters<RpcServiceInfoRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let endpoint = request
            .endpoint
            .or_else(|| std::env::var("SUI_GRPC_URL").ok())
            .unwrap_or_else(|| RpcClient::MAINNET_FULLNODE.to_string());
        let mut client = RpcClient::new(endpoint.clone()).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("gRPC client error: {}", e)),
            data: None,
        })?;
        let mut ledger = client.ledger_client();
        let response = ledger
            .get_service_info(RpcGetServiceInfoRequest::default())
            .await
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("gRPC request failed: {}", e)),
                data: None,
            })?
            .into_inner();

        let payload = json!({
            "endpoint": endpoint,
            "chain_id": response.chain_id,
            "chain": response.chain,
            "epoch": response.epoch,
            "checkpoint_height": response.checkpoint_height,
            "timestamp": response.timestamp.map(|ts| ts.seconds),
            "lowest_available_checkpoint": response.lowest_available_checkpoint,
            "lowest_available_checkpoint_objects": response.lowest_available_checkpoint_objects,
            "server": response.server
        });
        let response = Self::pretty_json(&payload)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
