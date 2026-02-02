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

    #[tool(description = "List supported Solana networks and their RPC URLs (mainnet-beta/testnet/devnet).")]
    async fn solana_list_networks(&self) -> Result<CallToolResult, ErrorData> {
        let response = Self::pretty_json(&serde_json::json!({
            "mainnet": {
                "network": "mainnet",
                "aliases": ["mainnet", "mainnet-beta"],
                "rpc_url": Self::solana_rpc_url_for_network(Some("mainnet"))?,
                "mainnet": true
            },
            "testnet": {
                "network": "testnet",
                "aliases": ["testnet"],
                "rpc_url": Self::solana_rpc_url_for_network(Some("testnet"))?,
                "mainnet": false
            },
            "devnet": {
                "network": "devnet",
                "aliases": ["devnet"],
                "rpc_url": Self::solana_rpc_url_for_network(Some("devnet"))?,
                "mainnet": false
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "List supported Sui networks and their default RPC URLs.")]
    async fn sui_list_networks(&self) -> Result<CallToolResult, ErrorData> {
        let response = Self::pretty_json(&serde_json::json!({
            "mainnet": {
                "network": "mainnet",
                "rpc_url": "https://fullnode.mainnet.sui.io:443",
                "mainnet": true
            },
            "testnet": {
                "network": "testnet",
                "rpc_url": "https://fullnode.testnet.sui.io:443",
                "mainnet": false
            },
            "devnet": {
                "network": "devnet",
                "rpc_url": "https://fullnode.devnet.sui.io:443",
                "mainnet": false
            },
            "localnet": {
                "network": "localnet",
                "rpc_url": "http://127.0.0.1:9000",
                "mainnet": false
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Run a quick healthcheck for configured networks and local stores (no secrets).")]
    async fn system_healthcheck(
        &self,
        Parameters(request): Parameters<SystemHealthcheckRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // ---- Sui ----
        let sui_rpc_url = self.rpc_url.clone();
        let sui_ok = self
            .client
            .read_api()
            .get_chain_identifier()
            .await
            .map(|_| true)
            .unwrap_or(false);

        // ---- Solana ----
        let solana_network = request
            .solana_network
            .as_deref()
            .unwrap_or("mainnet")
            .to_string();
        let solana_rpc_url = Self::solana_rpc_url_for_network(Some(&solana_network)).unwrap_or_else(|_| "".to_string());
        let solana_ok = if solana_rpc_url.is_empty() {
            false
        } else {
            let client = Self::solana_rpc(Some(&solana_network))?;
            // getHealth returns "ok" when healthy.
            client.get_health().await.is_ok()
        };

        // ---- EVM ----
        let evm_chain_id = request.evm_chain_id.unwrap_or(Self::evm_default_chain_id()?);
        let evm_rpc_url = Self::evm_rpc_url(evm_chain_id).unwrap_or_else(|_| "".to_string());
        let evm_ok = if evm_rpc_url.is_empty() {
            false
        } else {
            match self.evm_provider(evm_chain_id).await {
                Ok(provider) => {
                    let bn = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_block_number(&provider).await;
                    bn.is_ok()
                }
                Err(_) => false,
            }
        };

        // ---- Stores writability ----
        let solana_store_ok = crate::utils::solana_confirm_store::cleanup_expired().is_ok();
        let evm_store_ok = crate::utils::evm_confirm_store::connect().is_ok();
        let sui_store_ok = crate::utils::sui_confirm_store::connect().is_ok();

        let response = Self::pretty_json(&serde_json::json!({
            "sui": { "rpc_url": sui_rpc_url, "ok": sui_ok },
            "solana": { "network": solana_network, "rpc_url": solana_rpc_url, "ok": solana_ok },
            "evm": { "chain_id": evm_chain_id, "rpc_url": evm_rpc_url, "ok": evm_ok },
            "stores": {
                "solana_store_ok": solana_store_ok,
                "evm_store_ok": evm_store_ok,
                "sui_store_ok": sui_store_ok
            },
            "next": {
                "debug_bundle": "system_debug_bundle out_path=./debug_bundle.json"
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Show a safe, mainnet-oriented demo flow (2-phase + confirm_token). Does not broadcast.")]
    async fn system_demo_safe_mainnet_flow(
        &self,
        Parameters(request): Parameters<SystemDemoSafeMainnetFlowRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let evm_chain_id = request.evm_chain_id.unwrap_or(8453);
        let solana_network = request
            .solana_network
            .clone()
            .unwrap_or_else(|| "mainnet".to_string());
        let sui_rpc_url = request.sui_rpc_url.unwrap_or_else(|| self.rpc_url.clone());

        let response = Self::pretty_json(&serde_json::json!({
            "note": "This demo prints a safe 2-phase mainnet flow. It does NOT broadcast any transaction.",
            "evm": {
                "chain_id": evm_chain_id,
                "flow": [
                    "evm_build_transfer_native",
                    "evm_preflight",
                    "evm_create_pending_confirmation",
                    "(then) evm_retry_pending_confirmation with confirm_token"
                ]
            },
            "solana": {
                "network": solana_network,
                "flow": [
                    "solana_send_transaction (confirm=false)",
                    "(then) solana_confirm_transaction with confirm_token"
                ]
            },
            "sui": {
                "rpc_url": sui_rpc_url,
                "flow": [
                    "run a safe-default Sui tx tool with confirm=false to get pending",
                    "(then) sui_confirm_execution with confirm_token"
                ]
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Write a diagnostic bundle (JSON) with network context and pending confirmation summaries. Optionally writes to out_path.")]
    async fn system_debug_bundle(
        &self,
        Parameters(request): Parameters<SystemDebugBundleRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let include_evm_rpc_defaults = request.include_evm_rpc_defaults.unwrap_or(true);
        let include_pending_samples = request.include_pending_samples.unwrap_or(true);

        // ---- Network context ----
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

        // Solana defaults
        let solana_networks = serde_json::json!({
            "mainnet": Self::solana_rpc_url_for_network(Some("mainnet")).ok(),
            "testnet": Self::solana_rpc_url_for_network(Some("testnet")).ok(),
            "devnet": Self::solana_rpc_url_for_network(Some("devnet")).ok(),
        });

        // ---- Pending stores ----
        // Solana (json file)
        let solana_pending = crate::utils::solana_confirm_store::list_pending().unwrap_or_default();
        let solana_pending_count = solana_pending.len();
        let solana_pending_sample = if include_pending_samples {
            solana_pending
                .iter()
                .take(5)
                .map(|p| serde_json::json!({
                    "id": p.id,
                    "created_ms": p.created_ms,
                    "expires_ms": p.expires_ms,
                    "tx_summary_hash": p.tx_summary_hash,
                    "source_tool": p.source_tool,
                }))
                .collect::<Vec<_>>()
        } else {
            vec![]
        };

        // EVM (sqlite)
        let evm_db_path = crate::utils::evm_confirm_store::pending_db_path_from_cwd()
            .ok()
            .map(|p| p.to_string_lossy().to_string());
        let (evm_pending_count, evm_pending_sample) = (|| -> Result<(i64, Vec<serde_json::Value>), ErrorData> {
            let conn = crate::utils::evm_confirm_store::connect()?;
            let count: i64 = conn
                .query_row("SELECT COUNT(*) FROM evm_pending_confirmations", [], |row| row.get(0))
                .unwrap_or(0);

            let mut sample: Vec<serde_json::Value> = Vec::new();
            if include_pending_samples {
                let mut stmt = conn
                    .prepare(
                        "SELECT id, chain_id, status, updated_at_ms, tx_hash FROM evm_pending_confirmations ORDER BY updated_at_ms DESC LIMIT 5",
                    )
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to prepare EVM pending sample query: {}", e)),
                        data: None,
                    })?;

                let rows = stmt
                    .query_map([], |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            row.get::<_, i64>(1)?,
                            row.get::<_, Option<String>>(2)?,
                            row.get::<_, Option<i64>>(3)?,
                            row.get::<_, Option<String>>(4)?,
                        ))
                    })
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to query EVM pending sample: {}", e)),
                        data: None,
                    })?;
                for r in rows.flatten() {
                    sample.push(serde_json::json!({
                        "id": r.0,
                        "chain_id": r.1,
                        "status": r.2,
                        "updated_at_ms": r.3,
                        "tx_hash": r.4,
                    }));
                }
            }

            Ok((count, sample))
        })().unwrap_or((0, vec![]));

        // Sui (sqlite). DB lives at cwd/.data/pending.sqlite
        let sui_db_path = std::env::current_dir()
            .ok()
            .map(|cwd| cwd.join(".data").join("pending.sqlite").to_string_lossy().to_string());
        let (sui_pending_count, sui_pending_sample) = (|| -> Result<(i64, Vec<serde_json::Value>), ErrorData> {
            let conn = crate::utils::sui_confirm_store::connect()?;
            let count: i64 = conn
                .query_row("SELECT COUNT(*) FROM sui_pending_confirmations", [], |row| row.get(0))
                .unwrap_or(0);

            let mut sample: Vec<serde_json::Value> = Vec::new();
            if include_pending_samples {
                let mut stmt = conn
                    .prepare(
                        "SELECT id, status, updated_at_ms, digest FROM sui_pending_confirmations ORDER BY updated_at_ms DESC LIMIT 5",
                    )
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to prepare Sui pending sample query: {}", e)),
                        data: None,
                    })?;

                let rows = stmt
                    .query_map([], |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            row.get::<_, Option<String>>(1)?,
                            row.get::<_, Option<i64>>(2)?,
                            row.get::<_, Option<String>>(3)?,
                        ))
                    })
                    .map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to query Sui pending sample: {}", e)),
                        data: None,
                    })?;
                for r in rows.flatten() {
                    sample.push(serde_json::json!({
                        "id": r.0,
                        "status": r.1,
                        "updated_at_ms": r.2,
                        "digest": r.3,
                    }));
                }
            }

            Ok((count, sample))
        })().unwrap_or((0, vec![]));

        // EVM RPC defaults (optional)
        let evm_rpc_defaults = if include_evm_rpc_defaults {
            // Keep this list in sync with `evm_rpc_url()`.
            let chain_ids: Vec<u64> = vec![
                1, 11155111, 8453, 84532, 42161, 421614, 10, 11155420, 137, 80002, 56, 97, 43114,
                43113, 42220, 44787, 2222, 2221, 480, 4801, 143, 10143, 8217, 1001, 998,
            ];
            let mut out = serde_json::Map::new();
            for chain_id in chain_ids {
                if let Ok(url) = Self::evm_rpc_url(chain_id) {
                    out.insert(chain_id.to_string(), serde_json::Value::String(url));
                }
            }
            serde_json::Value::Object(out)
        } else {
            serde_json::Value::Null
        };

        let bundle = serde_json::json!({
            "generated_at_ms": crate::utils::solana_confirm_store::now_ms(),
            "network": {
                "sui": { "rpc_url": sui_rpc_url, "network": sui_network, "mainnet": sui_network == "mainnet" },
                "solana": { "supported": solana_networks },
            },
            "stores": {
                "solana": {
                    "store_path": crate::utils::solana_confirm_store::store_path().to_string_lossy(),
                    "pending_count": solana_pending_count,
                    "pending_sample": solana_pending_sample,
                },
                "evm": {
                    "db_path": evm_db_path,
                    "pending_count": evm_pending_count,
                    "pending_sample": evm_pending_sample,
                },
                "sui": {
                    "db_path": sui_db_path,
                    "pending_count": sui_pending_count,
                    "pending_sample": sui_pending_sample,
                }
            },
            "evm": {
                "rpc_defaults": evm_rpc_defaults
            }
        });

        if let Some(path) = request.out_path.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            std::fs::write(path, serde_json::to_string_pretty(&bundle).unwrap_or_default()).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to write debug bundle: {}", e)),
                data: Some(serde_json::json!({"out_path": path})),
            })?;
        }

        let response = Self::pretty_json(&bundle)?;
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
