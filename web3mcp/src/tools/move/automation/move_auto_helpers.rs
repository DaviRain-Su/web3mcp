// Shared helper methods for Move automation tools.
//
// This file is stitched into `router_impl.rs` by build.rs in a plain `impl Web3McpServer { ... }`
// block (NOT the #[tool_router] impl), so it can freely define helper methods.

    async fn build_move_call_form_schema(
        &self,
        package_id: ObjectID,
        package_str: &str,
        module: &str,
        function: &str,
        max_depth: usize,
        context: &str,
    ) -> Result<Value, ErrorData> {
        let modules = self
            .client
            .read_api()
            .get_normalized_move_modules_by_package(package_id)
            .await
            .map_err(|e| Self::sdk_error(context, e))?;

        let module_def = modules.get(module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Unable to load module schema"),
            data: None,
        })?;

        let function_def = module_def.exposed_functions.get(function).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Unable to load function schema"),
            data: None,
        })?;

        Ok(Self::move_call_form_schema(
            package_str,
            module,
            function,
            function_def,
            &modules,
            max_depth,
        ))
    }

    async fn build_move_call_tx_data(
        &self,
        sender: SuiAddress,
        package: ObjectID,
        module: &str,
        function: &str,
        type_args: Vec<SuiTypeTag>,
        call_args: Vec<SuiJsonValue>,
        gas: Option<ObjectID>,
        gas_budget: u64,
        gas_price: Option<u64>,
        context: &str,
    ) -> Result<TransactionData, ErrorData> {
        self.client
            .transaction_builder()
            .move_call(
                sender,
                package,
                module,
                function,
                type_args,
                call_args,
                gas,
                gas_budget,
                gas_price,
            )
            .await
            .map_err(|e| Self::sdk_error(context, e))
    }

    fn parse_type_args(type_args: Vec<String>) -> Result<Vec<SuiTypeTag>, ErrorData> {
        type_args
            .into_iter()
            .enumerate()
            .map(|(index, arg)| {
                let tag = SuiTypeTag::new(arg);
                if let Err(error) = tag.clone().try_into() as Result<TypeTag, _> {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Invalid type arg at index {}: {}",
                            index, error
                        )),
                        data: None,
                    });
                }
                Ok(tag)
            })
            .collect::<Result<Vec<_>, _>>()
    }

    fn json_string_array(obj: &Value, key: &str) -> Vec<String> {
        obj.get(key)
            .and_then(|value| value.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default()
    }

    fn parse_execute_payload(
        payload: &Value,
        default_gas_budget: u64,
    ) -> Result<(Vec<SuiTypeTag>, Vec<SuiJsonValue>, u64, Option<ObjectID>, Option<u64>), ErrorData>
    {
        let type_args_strings = Self::json_string_array(payload, "type_args");
        let arguments = payload
            .get("arguments")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();

        let gas_budget = payload
            .get("gas_budget")
            .and_then(|value| value.as_u64())
            .unwrap_or(default_gas_budget);

        let gas_object_id = payload
            .get("gas_object_id")
            .and_then(|value| value.as_str())
            .map(|s| s.to_string());

        let gas = gas_object_id
            .as_deref()
            .map(Self::parse_object_id)
            .transpose()?;

        let gas_price = payload.get("gas_price").and_then(|value| value.as_u64());

        let type_args = Self::parse_type_args(type_args_strings)?;
        let call_args = Self::parse_json_args(&arguments)?;

        Ok((type_args, call_args, gas_budget, gas, gas_price))
    }

    async fn execute_tx_with_zklogin(
        &self,
        tx_data: TransactionData,
        user_signature_base64: &str,
        zk_login_inputs_json: &str,
        address_seed: &str,
        max_epoch: u64,
        context: &str,
    ) -> Result<(String, SuiTransactionBlockResponse), ErrorData> {
        let tx_bytes = Self::encode_tx_bytes(&tx_data)?;

        let signature_bytes = Self::decode_base64("user_signature", user_signature_base64)?;
        let user_signature = Signature::from_bytes(&signature_bytes).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid user signature: {}", e)),
            data: None,
        })?;

        let zk_login_inputs = ZkLoginInputs::from_json(zk_login_inputs_json, address_seed)
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid zkLogin inputs: {}", e)),
                data: None,
            })?;

        let zklogin_authenticator =
            ZkLoginAuthenticator::new(zk_login_inputs, max_epoch, user_signature);
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
            .map_err(|e| Self::sdk_error(context, e))?;

        Ok((tx_bytes, result))
    }
