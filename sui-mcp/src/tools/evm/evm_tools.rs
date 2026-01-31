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

    fn u256_from_u64(v: u64) -> ethers::types::U256 {
        ethers::types::U256::from(v)
    }

    fn encode_erc20_call(sig: &str, args: Vec<ethers::abi::Token>) -> ethers::types::Bytes {
        let selector = &ethers::utils::keccak256(sig)[0..4];
        let mut out = Vec::with_capacity(4 + 32 * args.len());
        out.extend_from_slice(selector);
        out.extend_from_slice(&ethers::abi::encode(&args));
        ethers::types::Bytes::from(out)
    }

    fn tx_request_to_evm_tx(tx: &ethers::types::TransactionRequest, chain_id: u64) -> EvmTxRequest {
        let from = tx
            .from
            .as_ref()
            .map(|a| format!("0x{}", hex::encode(a.as_bytes())))
            .unwrap_or_default();
        let to = match &tx.to {
            Some(ethers::types::NameOrAddress::Address(a)) => {
                format!("0x{}", hex::encode(a.as_bytes()))
            }
            Some(_) => "".to_string(),
            None => "".to_string(),
        };
        let value = tx.value.unwrap_or_else(|| ethers::types::U256::from(0));
        let data_hex = tx.data.as_ref().map(|b| format!("0x{}", hex::encode(b.as_ref())));

        // TransactionRequest does not include EIP-1559 fields; those are filled during evm_preflight.
        EvmTxRequest {
            chain_id,
            from,
            to,
            value_wei: value.to_string(),
            data_hex,
            nonce: tx.nonce.as_ref().map(|n| n.as_u64()),
            gas_limit: tx.gas.as_ref().map(|g| g.as_u64()),
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
        }
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

    #[tool(description = "EVM ERC20: balanceOf(token, owner)")]
    async fn evm_erc20_balance_of(
        &self,
        Parameters(request): Parameters<EvmErc20BalanceOfRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let token = Self::parse_evm_address(&request.token)?;
        let owner = Self::parse_evm_address(&request.owner)?;

        let data = Self::encode_erc20_call(
            "balanceOf(address)",
            vec![ethers::abi::Token::Address(owner)],
        );

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
        .map_err(|e| Self::sdk_error("evm_erc20_balance_of:eth_call", e))?;

        let bytes: Vec<u8> = raw.to_vec();
        if bytes.len() < 32 {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("ERC20 balanceOf returned unexpected length"),
                data: None,
            });
        }
        let balance = ethers::types::U256::from_big_endian(&bytes[bytes.len() - 32..]);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "token": request.token,
            "owner": request.owner,
            "balance_raw": balance.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ERC20: allowance(token, owner, spender)")]
    async fn evm_erc20_allowance(
        &self,
        Parameters(request): Parameters<EvmErc20AllowanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);
        let provider = self.evm_provider(chain_id).await?;

        let token = Self::parse_evm_address(&request.token)?;
        let owner = Self::parse_evm_address(&request.owner)?;
        let spender = Self::parse_evm_address(&request.spender)?;

        let data = Self::encode_erc20_call(
            "allowance(address,address)",
            vec![
                ethers::abi::Token::Address(owner),
                ethers::abi::Token::Address(spender),
            ],
        );

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
        .map_err(|e| Self::sdk_error("evm_erc20_allowance:eth_call", e))?;

        let bytes: Vec<u8> = raw.to_vec();
        if bytes.len() < 32 {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("ERC20 allowance returned unexpected length"),
                data: None,
            });
        }
        let allowance = ethers::types::U256::from_big_endian(&bytes[bytes.len() - 32..]);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "token": request.token,
            "owner": request.owner,
            "spender": request.spender,
            "allowance_raw": allowance.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM ERC20: one-step transfer(token, to, amount_raw) with local signing")]
    async fn evm_execute_erc20_transfer(
        &self,
        Parameters(request): Parameters<EvmExecuteErc20TransferRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let from = Self::parse_evm_address(&request.sender)?;
        let token = Self::parse_evm_address(&request.token)?;
        let to = Self::parse_evm_address(&request.recipient)?;
        let amount = Self::parse_evm_u256("amount_raw", &request.amount_raw)?;

        let data = Self::encode_erc20_call(
            "transfer(address,uint256)",
            vec![
                ethers::abi::Token::Address(to),
                ethers::abi::Token::Uint(amount),
            ],
        );

        let tx_request = ethers::types::TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(token)),
            value: Some(ethers::types::U256::from(0)),
            data: Some(data),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        self.evm_execute_tx_request(
            chain_id,
            tx_request,
            request.allow_sender_mismatch.unwrap_or(false),
        )
        .await
    }

    #[tool(description = "EVM ERC20: one-step approve(token, spender, amount_raw) with local signing")]
    async fn evm_execute_erc20_approve(
        &self,
        Parameters(request): Parameters<EvmExecuteErc20ApproveRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let from = Self::parse_evm_address(&request.sender)?;
        let token = Self::parse_evm_address(&request.token)?;
        let spender = Self::parse_evm_address(&request.spender)?;
        let amount = Self::parse_evm_u256("amount_raw", &request.amount_raw)?;

        let data = Self::encode_erc20_call(
            "approve(address,uint256)",
            vec![
                ethers::abi::Token::Address(spender),
                ethers::abi::Token::Uint(amount),
            ],
        );

        let tx_request = ethers::types::TransactionRequest {
            from: Some(from),
            to: Some(ethers::types::NameOrAddress::Address(token)),
            value: Some(ethers::types::U256::from(0)),
            data: Some(data),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        self.evm_execute_tx_request(
            chain_id,
            tx_request,
            request.allow_sender_mismatch.unwrap_or(false),
        )
        .await
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

    fn evm_extract_first_json(result: &CallToolResult) -> Option<Value> {
        let content = result.content.first()?;
        let text = match &content.raw {
            RawContent::Text(text) => Some(text.text.clone()),
            RawContent::Resource(resource) => match &resource.resource {
                ResourceContents::TextResourceContents { text, .. } => Some(text.clone()),
                _ => None,
            },
            _ => None,
        }?;
        serde_json::from_str::<Value>(&text).ok()
    }

    fn evm_explorer_tx_url(chain_id: u64, tx_hash: &str) -> Option<String> {
        let base = match chain_id {
            8453 => "https://basescan.org/tx/",
            84532 => "https://sepolia.basescan.org/tx/",
            1 => "https://etherscan.io/tx/",
            11155111 => "https://sepolia.etherscan.io/tx/",
            42161 => "https://arbiscan.io/tx/",
            421614 => "https://sepolia.arbiscan.io/tx/",
            56 => "https://bscscan.com/tx/",
            97 => "https://testnet.bscscan.com/tx/",
            _ => return None,
        };
        Some(format!("{}{}", base, tx_hash))
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

        let tx_hash = format!("0x{}", hex::encode(pending.tx_hash().as_bytes()));
        let explorer_url = Self::evm_explorer_tx_url(chain_id, &tx_hash);

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_hash": tx_hash,
            "explorer_url": explorer_url
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    async fn evm_execute_tx_request(
        &self,
        chain_id: u64,
        tx_request: ethers::types::TransactionRequest,
        allow_sender_mismatch: bool,
    ) -> Result<CallToolResult, ErrorData> {
        let built_json_for_return = serde_json::to_value(Self::tx_request_to_evm_tx(&tx_request, chain_id))
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to serialize tx_request: {}", e)),
                data: None,
            })?;

        let tx: EvmTxRequest = serde_json::from_value(built_json_for_return.clone()).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode EVM tx: {}", e)),
            data: None,
        })?;

        let preflight = self
            .evm_preflight(Parameters(EvmPreflightRequest { tx: tx.clone() }))
            .await?;

        let pre_json = Self::evm_extract_first_json(&preflight).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_preflight result"),
            data: None,
        })?;
        let pre_json_for_return = pre_json.clone();

        let tx_val = pre_json.get("tx").cloned().unwrap_or_else(|| pre_json.clone());
        let tx: EvmTxRequest = serde_json::from_value(tx_val).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode preflight tx: {}", e)),
            data: None,
        })?;

        let signed = self
            .evm_sign_transaction_local(Parameters(EvmSignLocalRequest {
                tx: tx.clone(),
                allow_sender_mismatch: Some(allow_sender_mismatch),
            }))
            .await?;

        let signed_json = Self::evm_extract_first_json(&signed).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_sign_transaction_local result"),
            data: None,
        })?;

        let raw_tx = signed_json
            .get("raw_tx")
            .and_then(Value::as_str)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Missing raw_tx from signer"),
                data: None,
            })?
            .to_string();
        let raw_tx_prefix = raw_tx.chars().take(18).collect::<String>();

        let sent = self
            .evm_send_raw_transaction(Parameters(EvmSendRawTransactionRequest {
                raw_tx,
                chain_id: Some(chain_id),
            }))
            .await?;

        let sent_json = Self::evm_extract_first_json(&sent).ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Failed to parse evm_send_raw_transaction result"),
            data: None,
        })?;

        let response = Self::pretty_json(&json!({
            "chain_id": chain_id,
            "tx_built": built_json_for_return,
            "tx_preflight": pre_json_for_return,
            "raw_tx_prefix": raw_tx_prefix,
            "send": sent_json
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "EVM: one-step native transfer (build -> preflight -> sign -> send). Amount is in ETH (18 decimals).")]
    async fn evm_execute_transfer_native(
        &self,
        Parameters(request): Parameters<EvmExecuteTransferNativeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let chain_id = request
            .chain_id
            .unwrap_or(Self::evm_default_chain_id()?);

        let amount_wei = ethers::utils::parse_units(&request.amount, 18).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid amount (expected ETH units): {}", e)),
            data: None,
        })?;

        let tx_request = ethers::types::TransactionRequest {
            from: Some(Self::parse_evm_address(&request.sender)?),
            to: Some(ethers::types::NameOrAddress::Address(Self::parse_evm_address(
                &request.recipient,
            )?)),
            value: Some(amount_wei.into()),
            gas: request.gas_limit.map(Self::u256_from_u64),
            ..Default::default()
        };

        self.evm_execute_tx_request(chain_id, tx_request, false).await
    }
