/// EVM tools (Base / EVM-compatible chains)
    ///
    /// NOTE: This server is currently named `sui-mcp`, but we’re gradually expanding it into a
    /// multi-chain MCP server. These EVM tools are the first step.

    fn evm_default_chain_id() -> Result<u64, ErrorData> {
        if let Ok(v) = std::env::var("EVM_DEFAULT_CHAIN_ID") {
            return v.parse::<u64>().map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid EVM_DEFAULT_CHAIN_ID: {}", e)),
                data: None,
            });
        }
        Ok(84532) // Base Sepolia
    }

    fn evm_rpc_url(chain_id: u64) -> Result<String, ErrorData> {
        let key = format!("EVM_RPC_URL_{}", chain_id);
        if let Ok(url) = std::env::var(&key) {
            return Ok(url);
        }

        // Convenience defaults for Base.
        match chain_id {
            8453 => Ok("https://mainnet.base.org".to_string()),
            84532 => Ok("https://sepolia.base.org".to_string()),
            _ => Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Missing RPC URL for chain_id={}. Set {} env var.",
                    chain_id, key
                )),
                data: None,
            }),
        }
    }

    async fn evm_provider(
        &self,
        chain_id: u64,
    ) -> Result<ethers::providers::Provider<ethers::providers::Http>, ErrorData> {
        let url = Self::evm_rpc_url(chain_id)?;
        ethers::providers::Provider::<ethers::providers::Http>::try_from(url.as_str()).map_err(
            |e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to create EVM provider: {}", e)),
                data: None,
            },
        )
    }

    fn parse_evm_address(address: &str) -> Result<ethers::types::Address, ErrorData> {
        address
            .parse::<ethers::types::Address>()
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid EVM address: {}", e)),
                data: None,
            })
    }

    fn parse_evm_u256(label: &str, value: &str) -> Result<ethers::types::U256, ErrorData> {
        // Allow decimal strings or 0x-prefixed hex.
        if let Some(hex) = value.strip_prefix("0x") {
            return ethers::types::U256::from_str_radix(hex, 16).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid {} (hex): {}", label, e)),
                data: None,
            });
        }
        ethers::types::U256::from_dec_str(value).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid {} (decimal): {}", label, e)),
            data: None,
        })
    }

    fn parse_evm_h256(value: &str) -> Result<ethers::types::H256, ErrorData> {
        value.parse::<ethers::types::H256>().map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid tx hash: {}", e)),
            data: None,
        })
    }

    #[tool(description = "EVM: get balance (native ETH by default; ERC20 if token_address is provided)")]
    async fn evm_get_balance(
        &self,
        Parameters(request): Parameters<EvmGetBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;
        let address = Self::parse_evm_address(&request.address)?;

        let balance = if let Some(token_address) = request.token_address.as_deref() {
            // ERC20 balanceOf(address)
            let token = Self::parse_evm_address(token_address)?;
            let selector = &ethers::utils::keccak256("balanceOf(address)")[0..4];
            let data = {
                let mut out = Vec::with_capacity(4 + 32);
                out.extend_from_slice(selector);
                out.extend_from_slice(&ethers::abi::encode(&[ethers::abi::Token::Address(address)]));
                ethers::types::Bytes::from(out)
            };

            let call = ethers::types::TransactionRequest {
                to: Some(ethers::types::NameOrAddress::Address(token)),
                data: Some(data),
                ..Default::default()
            };
            let typed: ethers::types::transaction::eip2718::TypedTransaction = call.clone().into();

            let raw = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::call(
                &provider,
                &typed,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_get_balance:eth_call", e))?;

            // Decode as U256 (32 bytes)
            let bytes: Vec<u8> = raw.to_vec();
            if bytes.len() < 32 {
                return Err(ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("ERC20 balanceOf returned unexpected length"),
                    data: None,
                });
            }
            ethers::types::U256::from_big_endian(&bytes[bytes.len() - 32..])
        } else {
            <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_balance(
                &provider,
                address,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_get_balance:get_balance", e))?
        };

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "address": request.address,
            "token_address": request.token_address,
            "balance_wei": balance.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: get transaction by hash")]
    async fn evm_get_transaction(
        &self,
        Parameters(request): Parameters<EvmGetTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;
        let hash = Self::parse_evm_h256(&request.tx_hash)?;

        let tx = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction(
            &provider,
            hash,
        )
        .await
        .map_err(|e| Self::sdk_error("evm_get_transaction", e))?;

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": request.tx_hash,
            "transaction": tx
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: build a native transfer tx (fills to/value; optional data). Use evm_preflight to fill nonce/gas/fees.")]
    async fn evm_build_transfer_native(
        &self,
        Parameters(request): Parameters<EvmBuildTransferNativeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let from = Self::parse_evm_address(&request.sender)?;
        let to = Self::parse_evm_address(&request.recipient)?;
        let value = Self::parse_evm_u256("amount_wei", &request.amount_wei)?;

        let tx = EvmTxRequest {
            chain_id,
            from: request.sender,
            to: request.recipient,
            value_wei: value.to_string(),
            data_hex: request.data_hex,
            nonce: None,
            gas_limit: request.gas_limit,
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
        };

        // Basic safety: optional large transfer confirmation.
        let confirm_large = request.confirm_large_transfer.unwrap_or(false);
        let threshold = request
            .large_transfer_threshold_wei
            .as_deref()
            .unwrap_or("100000000000000000"); // 0.1 ETH default
        let threshold_u256 = Self::parse_evm_u256("large_transfer_threshold_wei", threshold)?;
        if value >= threshold_u256 && !confirm_large {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!(
                    "Large transfer: amount_wei={} >= threshold_wei={}. Set confirm_large_transfer=true to proceed.",
                    value, threshold_u256
                )),
                data: None,
            });
        }

        // Avoid unused warnings (we only parse to validate)
        let _ = (from, to);

        let response = Self::pretty_json(&tx)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: preflight a tx (fills nonce, gas_limit, max_fee_per_gas, max_priority_fee_per_gas).")]
    async fn evm_preflight(
        &self,
        Parameters(request): Parameters<EvmPreflightRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let mut tx = request.tx.clone();
        let chain_id = tx.chain_id;
        let provider = self.evm_provider(chain_id).await?;

        let from = Self::parse_evm_address(&tx.from)?;
        let to = Self::parse_evm_address(&tx.to)?;
        let value = Self::parse_evm_u256("value_wei", &tx.value_wei)?;
        let data = if let Some(hex) = tx.data_hex.as_deref() {
            let hex = hex.strip_prefix("0x").unwrap_or(hex);
            let bytes = hex::decode(hex).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid data_hex: {}", e)),
                data: None,
            })?;
            ethers::types::Bytes::from(bytes)
        } else {
            ethers::types::Bytes::from(Vec::<u8>::new())
        };

        // Nonce
        if tx.nonce.is_none() {
            let nonce = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_transaction_count(
                &provider,
                from,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_preflight:get_transaction_count", e))?;
            tx.nonce = Some(nonce.as_u64());
        }

        // Fee data (EIP-1559 where available)
        if tx.max_fee_per_gas_wei.is_none() || tx.max_priority_fee_per_gas_wei.is_none() {
            // Prefer EIP-1559 fee estimation.
            let fees = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::estimate_eip1559_fees(
                &provider,
                None,
            )
            .await;

            match fees {
                Ok((max_fee, max_prio)) => {
                    if tx.max_fee_per_gas_wei.is_none() {
                        tx.max_fee_per_gas_wei = Some(max_fee.to_string());
                    }
                    if tx.max_priority_fee_per_gas_wei.is_none() {
                        tx.max_priority_fee_per_gas_wei = Some(max_prio.to_string());
                    }
                }
                Err(_) => {
                    // Fallback: legacy gas price.
                    let gas_price = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::get_gas_price(
                        &provider,
                    )
                    .await
                    .map_err(|e| Self::sdk_error("evm_preflight:get_gas_price", e))?;

                    if tx.max_fee_per_gas_wei.is_none() {
                        tx.max_fee_per_gas_wei = Some(gas_price.to_string());
                    }
                    if tx.max_priority_fee_per_gas_wei.is_none() {
                        tx.max_priority_fee_per_gas_wei = Some("0".to_string());
                    }
                }
            }
        }

        // Gas limit
        if tx.gas_limit.is_none() {
            let estimate_req = ethers::types::TransactionRequest {
                from: Some(from),
                to: Some(ethers::types::NameOrAddress::Address(to)),
                value: Some(value),
                data: Some(data.clone()),
                ..Default::default()
            };
            let typed: ethers::types::transaction::eip2718::TypedTransaction =
                estimate_req.clone().into();

            let est = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::estimate_gas(
                &provider,
                &typed,
                None,
            )
            .await
            .map_err(|e| Self::sdk_error("evm_preflight:estimate_gas", e))?;

            // buffer 20%
            let buffered = est
                .checked_mul(ethers::types::U256::from(12))
                .unwrap_or(est)
                / ethers::types::U256::from(10);
            tx.gas_limit = Some(buffered.as_u64());
        }

        let response = Self::pretty_json(&json!({
            "tx": tx,
            "note": "Use evm_sign_transaction_local to sign, then evm_send_raw_transaction to broadcast."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: sign a tx using a local private key (EVM_PRIVATE_KEY env). Returns raw_tx hex.")]
    async fn evm_sign_transaction_local(
        &self,
        Parameters(request): Parameters<EvmSignLocalRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request.tx.chain_id;
        let pk = std::env::var("EVM_PRIVATE_KEY").map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Missing EVM_PRIVATE_KEY env var"),
            data: None,
        })?;
        let wallet: ethers::signers::LocalWallet = pk.parse().map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid EVM_PRIVATE_KEY: {}", e)),
            data: None,
        })?;
        let wallet = ethers::signers::Signer::with_chain_id(wallet, chain_id);

        let from = Self::parse_evm_address(&request.tx.from)?;
        let to = Self::parse_evm_address(&request.tx.to)?;
        let value = Self::parse_evm_u256("value_wei", &request.tx.value_wei)?;
        let nonce = request.tx.nonce.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("tx.nonce is required; run evm_preflight first"),
            data: None,
        })?;
        let gas_limit = request.tx.gas_limit.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("tx.gas_limit is required; run evm_preflight first"),
            data: None,
        })?;

        let max_fee = request
            .tx
            .max_fee_per_gas_wei
            .as_deref()
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "tx.max_fee_per_gas_wei is required; run evm_preflight first",
                ),
                data: None,
            })?;
        let max_fee = Self::parse_evm_u256("max_fee_per_gas_wei", max_fee)?;

        let max_prio = request
            .tx
            .max_priority_fee_per_gas_wei
            .as_deref()
            .unwrap_or("0");
        let max_prio = Self::parse_evm_u256("max_priority_fee_per_gas_wei", max_prio)?;

        let data = if let Some(hex) = request.tx.data_hex.as_deref() {
            let hex = hex.strip_prefix("0x").unwrap_or(hex);
            let bytes = hex::decode(hex).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid data_hex: {}", e)),
                data: None,
            })?;
            ethers::types::Bytes::from(bytes)
        } else {
            ethers::types::Bytes::from(Vec::<u8>::new())
        };

        // Basic sender mismatch protection.
        if request.allow_sender_mismatch.unwrap_or(false) == false {
            let wallet_addr = ethers::signers::Signer::address(&wallet);
            if wallet_addr != from {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Signer mismatch: wallet={} tx.from={}. Set allow_sender_mismatch=true if intentional.",
                        wallet_addr, from
                    )),
                    data: None,
                });
            }
        }

        let tx1559 = ethers::types::transaction::eip1559::Eip1559TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(to)),
            value: Some(value),
            data: Some(data),
            nonce: Some(nonce.into()),
            gas: Some(gas_limit.into()),
            max_fee_per_gas: Some(max_fee),
            max_priority_fee_per_gas: Some(max_prio),
            chain_id: Some(chain_id.into()),
            ..Default::default()
        };

        let mut typed: ethers::types::transaction::eip2718::TypedTransaction = tx1559.into();
        // Ensure chain id is set
        typed.set_chain_id(chain_id);

        let sig = ethers::signers::Signer::sign_transaction(&wallet, &typed)
            .await
            .map_err(|e| Self::sdk_error("evm_sign_transaction_local", e))?;

        let raw = typed.rlp_signed(&sig);
        let raw_hex = format!("0x{}", hex::encode(raw.as_ref()));

        // Optional audit log.
        self.write_audit_log(
            "evm_sign_transaction_local",
            json!({
                "chain_id": chain_id,
                "from": request.tx.from,
                "to": request.tx.to,
                "value_wei": request.tx.value_wei,
                "nonce": nonce,
                "gas_limit": gas_limit,
                "max_fee_per_gas_wei": max_fee.to_string(),
                "max_priority_fee_per_gas_wei": max_prio.to_string(),
                "raw_tx_prefix": &raw_hex.chars().take(18).collect::<String>()
            }),
        );

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "raw_tx": raw_hex
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: broadcast a raw signed transaction")]
    async fn evm_send_raw_transaction(
        &self,
        Parameters(request): Parameters<EvmSendRawTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let raw_hex = request.raw_tx.strip_prefix("0x").unwrap_or(&request.raw_tx);
        let raw = hex::decode(raw_hex).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid raw_tx hex: {}", e)),
            data: None,
        })?;

        let pending = <ethers::providers::Provider<ethers::providers::Http> as ethers::providers::Middleware>::send_raw_transaction(
            &provider,
            ethers::types::Bytes::from(raw),
        )
        .await
        .map_err(|e| Self::sdk_error("evm_send_raw_transaction", e))?;

        let tx_hash = pending.tx_hash();
        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": format!("0x{}", hex::encode(tx_hash.as_bytes()))
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
