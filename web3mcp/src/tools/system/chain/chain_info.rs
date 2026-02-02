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

    /// List built-in EVM chain_id -> RPC defaults (may be overridden by env vars).
    #[tool(description = "List built-in EVM RPC defaults (chain_id -> rpc_url). Override via EVM_RPC_URL_<chain_id> env var.")]
    async fn evm_list_rpc_defaults(&self) -> Result<CallToolResult, ErrorData> {
        // Keep this list in sync with `evm_rpc_url()`.
        let chain_ids: Vec<u64> = vec![
            // Ethereum
            1, 11155111,
            // Base
            8453, 84532,
            // Arbitrum
            42161, 421614,
            // Optimism
            10, 11155420,
            // Polygon PoS
            137, 80002,
            // Avalanche
            43114, 43113,
            // Celo
            42220, 44787,
            // Kava
            2222, 2221,
            // World Chain
            480, 4801,
            // Monad
            143, 10143,
            // Kaia
            8217, 1001,
            // HyperEVM
            998,
        ];

        let mut out = serde_json::Map::new();
        for chain_id in chain_ids {
            if let Ok(url) = Self::evm_rpc_url(chain_id) {
                out.insert(chain_id.to_string(), serde_json::Value::String(url));
            }
        }

        let response = Self::pretty_json(&serde_json::Value::Object(out))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Report currently configured server network context (Sui rpc_url + mainnet/testnet hints).
    #[tool(description = "Get server network context (Sui rpc_url and inferred network; plus Solana network notes).")]
    async fn system_network_context(&self) -> Result<CallToolResult, ErrorData> {
        let sui_rpc_url = self.rpc_url.clone();
        let sui_rpc_lc = sui_rpc_url.to_lowercase();
        let sui_network = if sui_rpc_lc.contains("testnet") {
            "testnet"
        } else if sui_rpc_lc.contains("devnet") {
            "devnet"
        } else if sui_rpc_lc.contains("mainnet") {
            "mainnet"
        } else if sui_rpc_lc.contains("127.0.0.1") || sui_rpc_lc.contains("localhost") {
            "local"
        } else {
            "unknown"
        };

        // Solana tools accept a `network` param on each call; default is mainnet.
        let solana_default_network = "mainnet";

        let response = Self::pretty_json(&serde_json::json!({
            "sui": {
                "rpc_url": sui_rpc_url,
                "network": sui_network,
                "mainnet": sui_network == "mainnet"
            },
            "solana": {
                "default_network": solana_default_network,
                "note": "Solana tools accept network=mainnet|mainnet-beta|testnet|devnet per call; default is mainnet. Mainnet broadcasts require confirm_token."
            },
            "evm": {
                "note": "EVM tools use chain_id; mainnet chain_ids require confirm_token and will not broadcast from one-step transfer. Use pending confirmations."
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
