    /// List addresses in the local Sui keystore
    #[tool(description = "List addresses from the local Sui keystore")]
    async fn get_keystore_accounts(
        &self,
        Parameters(request): Parameters<KeystoreAccountsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let entries = keystore
            .addresses_with_alias()
            .into_iter()
            .map(|(address, alias)| {
                json!({
                    "address": address.to_string(),
                    "alias": alias.alias
                })
            })
            .collect::<Vec<_>>();

        let response = Self::pretty_json(&json!({
            "count": entries.len(),
            "accounts": entries
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Sign transaction bytes using a local Sui keystore
    #[tool(description = "Sign transaction bytes using the local Sui keystore")]
    async fn sign_transaction_with_keystore(
        &self,
        Parameters(request): Parameters<KeystoreSignTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = self.resolve_keystore_signer(&keystore, request.signer.as_deref())?;

        let tx_bytes = Self::decode_base64("tx_bytes", &request.tx_bytes)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;

        let signature = keystore
            .sign_secure(&signer, &tx_data, shared_crypto::intent::Intent::sui_transaction())
            .await
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to sign transaction: {}", e)),
                data: None,
            })?;

        let signature_base64 = Base64Engine.encode(signature.as_ref());
        let response = Self::pretty_json(&json!({
            "signer": signer.to_string(),
            "signature_base64": signature_base64
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a transaction using a local Sui keystore
    #[tool(description = "Execute a transaction using the local Sui keystore")]
    async fn execute_transaction_with_keystore(
        &self,
        Parameters(request): Parameters<KeystoreExecuteTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let keystore = self.load_file_keystore(request.keystore_path.as_deref())?;
        let signer = self.resolve_keystore_signer(&keystore, request.signer.as_deref())?;

        let tx_bytes = Self::decode_base64("tx_bytes", &request.tx_bytes)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;

        let signature = keystore
            .sign_secure(&signer, &tx_data, shared_crypto::intent::Intent::sui_transaction())
            .await
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to sign transaction: {}", e)),
                data: None,
            })?;

        let tx = Transaction::from_generic_sig_data(
            tx_data,
            vec![GenericSignature::Signature(signature)],
        );

        let options = SuiTransactionBlockResponseOptions::new()
            .with_input()
            .with_effects()
            .with_events()
            .with_object_changes()
            .with_balance_changes();

        let result = self
            .client
            .quorum_driver_api()
            .execute_transaction_block(tx, options, None)
            .await
            .map_err(|e| Self::sdk_error("execute_transaction_with_keystore", e))?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "result": result,
            "summary": summary
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn load_file_keystore(
        &self,
        keystore_path: Option<&str>,
    ) -> Result<sui_keys::keystore::FileBasedKeystore, ErrorData> {
        let path = if let Some(path) = keystore_path {
            std::path::PathBuf::from(path)
        } else if let Ok(path) = std::env::var("SUI_KEYSTORE_PATH") {
            std::path::PathBuf::from(path)
        } else {
            let home = std::env::var("HOME").map_err(|_| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("HOME not set; provide keystore_path"),
                data: None,
            })?;
            std::path::PathBuf::from(home)
                .join(".sui")
                .join("sui_config")
                .join("sui.keystore")
        };

        if !path.exists() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Keystore not found at {}", path.display())),
                data: None,
            });
        }

        sui_keys::keystore::FileBasedKeystore::load_or_create(&path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to load keystore: {}", e)),
            data: None,
        })
    }

    fn resolve_keystore_signer(
        &self,
        keystore: &sui_keys::keystore::FileBasedKeystore,
        signer: Option<&str>,
    ) -> Result<SuiAddress, ErrorData> {
        if let Some(signer) = signer {
            let identity = signer
                .parse::<sui_keys::key_identity::KeyIdentity>()
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid signer: {}", e)),
                    data: None,
                })?;
            return keystore.get_by_identity(&identity).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Unable to resolve signer: {}", e)),
                data: None,
            });
        }

        let addresses = keystore.addresses();
        if addresses.len() == 1 {
            return Ok(addresses[0]);
        }

        Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Multiple keystore accounts found; provide signer"),
            data: None,
        })
    }
