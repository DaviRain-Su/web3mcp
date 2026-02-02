    /// Execute a transaction using zkLogin signature inputs
    #[tool(description = "Execute a transaction using zkLogin inputs and an ephemeral user signature")]
    async fn execute_zklogin_transaction(
        &self,
        Parameters(request): Parameters<ZkLoginExecuteTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let tx_bytes = Self::decode_base64("tx_bytes", &request.tx_bytes)?;
        let tx_data: TransactionData = bcs::from_bytes(&tx_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid transaction bytes: {}", e)),
            data: None,
        })?;

        let signature_bytes = Self::decode_base64("user_signature", &request.user_signature)?;
        let user_signature = Signature::from_bytes(&signature_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid user signature: {}", e)),
            data: None,
        })?;

        let zk_login_inputs =
            ZkLoginInputs::from_json(&request.zk_login_inputs_json, &request.address_seed)
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid zkLogin inputs: {}", e)),
                    data: None,
                })?;

        let zklogin_authenticator =
            ZkLoginAuthenticator::new(zk_login_inputs, request.max_epoch, user_signature);
        let tx = Transaction::from_generic_sig_data(
            tx_data,
            vec![GenericSignature::ZkLoginAuthenticator(zklogin_authenticator)],
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
            .map_err(|e| Self::sdk_error("execute_zklogin_transaction", e))?;

        let summary = Self::summarize_transaction(&result);
        let response = Self::pretty_json(&json!({
            "result": result,
            "summary": summary
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Verify a zkLogin signature against transaction bytes or a message
    #[tool(description = "Verify a zkLogin signature against bytes and address")]
    async fn verify_zklogin_signature(
        &self,
        Parameters(request): Parameters<VerifyZkLoginSignatureRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let address = Self::parse_address(&request.address)?;
        let intent_scope = match request
            .intent_scope
            .as_deref()
            .unwrap_or("transaction")
            .to_lowercase()
            .as_str()
        {
            "transaction" => ZkLoginIntentScope::TransactionData,
            "personal_message" => ZkLoginIntentScope::PersonalMessage,
            other => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Invalid intent scope '{}', expected 'transaction' or 'personal_message'",
                        other
                    )),
                    data: None,
                })
            }
        };

        let result = self
            .client
            .read_api()
            .verify_zklogin_signature(
                request.bytes,
                request.signature,
                intent_scope,
                address,
            )
            .await
            .map_err(|e| Self::sdk_error("verify_zklogin_signature", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
