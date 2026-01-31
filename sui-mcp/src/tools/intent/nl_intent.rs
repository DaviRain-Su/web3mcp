    /// Interpret natural language intent into tool calls
    #[tool(description = "Interpret natural language intent into tool calls")]
    async fn interpret_intent(
        &self,
        Parameters(request): Parameters<IntentRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let text = request.text.clone();
        let lower = text.to_lowercase();
        let sender = request.sender.clone().unwrap_or_else(|| "<sender>".to_string());
        let network = request.network.clone();

        let (intent, action, entities, confidence, plan) = Self::parse_intent_plan(&text, &lower, sender, network.clone());
        let pipeline = Self::tool_plan_to_pipeline(&plan);

        let response = Self::pretty_json(&json!({
            "text": request.text,
            "intent": intent,
            "action": action,
            "confidence": confidence,
            "entities": entities,
            "tool_plan": plan,
            "pipeline": pipeline,
            "notes": "Fill <...> placeholders using cetus_action_params or generate_move_call_payload before executing."
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute an intent with optional zkLogin inputs
    #[tool(description = "Execute an intent using provided overrides (supports zkLogin)")]
    async fn execute_intent(
        &self,
        Parameters(request): Parameters<IntentExecuteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let text = request.text.clone();
        let lower = text.to_lowercase();
        let sender = request.sender.clone();
        let network = request.network.clone();
        let (intent, action, entities, _confidence, _plan) = Self::parse_intent_plan(&text, &lower, sender.clone(), network.clone());

        let amount = request.amount.or_else(|| entities.get("amount_u64").and_then(|v| v.as_u64()));
        let recipient = request
            .recipient
            .or_else(|| entities.get("recipient").and_then(|v| v.as_str().map(|s| s.to_string())));
        let validator = request
            .validator
            .or_else(|| entities.get("validator").and_then(|v| v.as_str().map(|s| s.to_string())));
        let object_id = request
            .object_id
            .or_else(|| entities.get("object_id").and_then(|v| v.as_str().map(|s| s.to_string())));
        let staked_sui = request
            .staked_sui
            .or_else(|| entities.get("staked_sui").and_then(|v| v.as_str().map(|s| s.to_string())));

        let gas_budget = request.gas_budget.unwrap_or(1_000_000);

        match intent.as_str() {
            "get_balance" => {
                return self
                    .get_balance(Parameters(GetBalanceRequest {
                        address: sender,
                        coin_type: None,
                    }))
                    .await;
            }
            "transfer" => {
                let recipient = recipient.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("recipient is required for transfer"),
                    data: None,
                })?;
                let input_coins = request.input_coins.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("input_coins is required for transfer"),
                    data: None,
                })?;
                let tx = self
                    .build_transfer_sui(Parameters(BuildTransferSuiRequest {
                        sender: sender.clone(),
                        recipient,
                        input_coins,
                        amount,
                        gas_budget,
                    }))
                    .await?;
                let tx_bytes = Self::extract_tx_bytes(&tx).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse tx_bytes from transfer"),
                    data: None,
                })?;

                return self
                    .execute_zklogin_transaction(Parameters(ZkLoginExecuteTransactionRequest {
                        tx_bytes,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await;
            }
            "transfer_object" => {
                let recipient = recipient.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("recipient is required for transfer object"),
                    data: None,
                })?;
                let object_id = object_id.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("object_id is required for transfer object"),
                    data: None,
                })?;
                let tx = self
                    .build_transfer_object(Parameters(BuildTransferObjectRequest {
                        sender: sender.clone(),
                        object_id,
                        recipient,
                        gas_budget,
                        gas_object_id: request.gas_object_id.clone(),
                    }))
                    .await?;
                let tx_bytes = Self::extract_tx_bytes(&tx).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse tx_bytes from transfer object"),
                    data: None,
                })?;

                return self
                    .execute_zklogin_transaction(Parameters(ZkLoginExecuteTransactionRequest {
                        tx_bytes,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await;
            }
            "stake" => {
                let validator = validator.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("validator is required for stake"),
                    data: None,
                })?;
                let coins = request.input_coins.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("input_coins is required for stake"),
                    data: None,
                })?;
                let tx = self
                    .build_add_stake(Parameters(BuildAddStakeRequest {
                        sender: sender.clone(),
                        validator,
                        coins,
                        amount,
                        gas_budget,
                        gas_object_id: request.gas_object_id.clone(),
                    }))
                    .await?;
                let tx_bytes = Self::extract_tx_bytes(&tx).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse tx_bytes from stake"),
                    data: None,
                })?;

                return self
                    .execute_zklogin_transaction(Parameters(ZkLoginExecuteTransactionRequest {
                        tx_bytes,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await;
            }
            "unstake" => {
                let staked_sui = staked_sui.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("staked_sui is required for withdraw"),
                    data: None,
                })?;
                let tx = self
                    .build_withdraw_stake(Parameters(BuildWithdrawStakeRequest {
                        sender: sender.clone(),
                        staked_sui,
                        gas_budget,
                        gas_object_id: request.gas_object_id.clone(),
                    }))
                    .await?;
                let tx_bytes = Self::extract_tx_bytes(&tx).ok_or_else(|| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from("Failed to parse tx_bytes from withdraw"),
                    data: None,
                })?;

                return self
                    .execute_zklogin_transaction(Parameters(ZkLoginExecuteTransactionRequest {
                        tx_bytes,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await;
            }
            "cetus_quote" => {
                let type_args = request.type_args.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("type_args is required for cetus quote"),
                    data: None,
                })?;
                let arguments = request.arguments.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("arguments is required for cetus quote"),
                    data: None,
                })?;

                return self
                    .cetus_quote(Parameters(CetusQuoteRequest {
                        action: action.unwrap_or_else(|| "quote".to_string()),
                        network,
                        sender,
                        package_id: None,
                        module: None,
                        function: None,
                        type_args: Some(type_args),
                        arguments,
                    }))
                    .await;
            }
            "cetus_swap" => {
                let type_args = request.type_args.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("type_args is required for cetus swap"),
                    data: None,
                })?;
                let arguments = request.arguments.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("arguments is required for cetus swap"),
                    data: None,
                })?;

                return self
                    .cetus_execute(Parameters(CetusExecuteRequest {
                        action: action.unwrap_or_else(|| "swap".to_string()),
                        network,
                        sender,
                        package_id: None,
                        module: None,
                        function: None,
                        type_args: Some(type_args),
                        arguments,
                        gas_budget,
                        gas_object_id: request.gas_object_id.clone(),
                        gas_price: request.gas_price,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await;
            }
            "mint" | "borrow" | "lend" => {
                let package = request.package.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("package is required for move call intents"),
                    data: None,
                })?;
                let module = request.module.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("module is required for move call intents"),
                    data: None,
                })?;
                let function = request.function.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("function is required for move call intents"),
                    data: None,
                })?;
                let type_args = request.type_args.unwrap_or_default();
                let arguments = request.arguments.unwrap_or_default();

                return self
                    .auto_execute_move_call_filled(Parameters(AutoExecuteMoveCallRequest {
                        sender,
                        package,
                        module,
                        function,
                        type_args,
                        arguments,
                        gas_budget,
                        gas_object_id: request.gas_object_id.clone(),
                        gas_price: request.gas_price,
                        zk_login_inputs_json: request.zk_login_inputs_json.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("zk_login_inputs_json required"),
                            data: None,
                        })?,
                        address_seed: request.address_seed.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("address_seed required"),
                            data: None,
                        })?,
                        max_epoch: request.max_epoch.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("max_epoch required"),
                            data: None,
                        })?,
                        user_signature: request.user_signature.ok_or_else(|| ErrorData {
                            code: ErrorCode(-32602),
                            message: Cow::from("user_signature required"),
                            data: None,
                        })?,
                    }))
                    .await;
            }
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Unsupported intent: {}", intent)),
                    data: None,
                })
            }
        }
    }

    fn parse_intent_plan(
        text: &str,
        lower: &str,
        sender: String,
        network: Option<String>,
    ) -> (String, Option<String>, Value, f64, Vec<Value>) {
        let amount = Self::extract_amount(text, lower);
        let amount_u64 = amount
            .as_ref()
            .and_then(|value| value.parse::<f64>().ok())
            .map(|value| value as u64);
        let addresses = Self::extract_addresses(text);

        let token_list = ["sui", "usdc", "usdt", "eth", "btc"];
        let mut tokens = Vec::new();
        for token in token_list.iter() {
            if let Some(pos) = lower.find(token) {
                tokens.push((pos, token.to_string()));
            }
        }
        tokens.sort_by_key(|(pos, _)| *pos);
        let from_token = tokens.get(0).map(|(_, token)| token.to_uppercase());
        let to_token = tokens.get(1).map(|(_, token)| token.to_uppercase());

        let mut intent = "unknown".to_string();
        let mut action = None;
        let mut confidence = 0.3;
        let mut plan = Vec::new();
        let mut entities = json!({
            "amount": amount,
            "amount_u64": amount_u64,
            "from_coin": from_token,
            "to_coin": to_token,
            "addresses": addresses
        });

        if lower.contains("swap") || lower.contains("兑换") || lower.contains("换") {
            intent = "cetus_swap".to_string();
            confidence = 0.7;
            if lower.contains("exact out") || lower.contains("精确输出") {
                action = Some("swap_exact_out".to_string());
            } else if lower.contains("exact in") || lower.contains("精确输入") {
                action = Some("swap_exact_in".to_string());
            }

            plan.push(json!({
                "tool": "cetus_action_params",
                "params": {
                    "action": action.clone().unwrap_or_else(|| "swap".to_string()),
                    "network": network
                }
            }));
            plan.push(json!({
                "tool": "cetus_generate_payload",
                "params": {
                    "action": action.clone().unwrap_or_else(|| "swap".to_string()),
                    "network": network,
                    "sender": sender
                }
            }));
            plan.push(json!({
                "tool": "cetus_prepare",
                "params": {
                    "action": action.clone().unwrap_or_else(|| "swap".to_string()),
                    "network": network,
                    "sender": sender,
                    "type_args": ["<from_coin>", "<to_coin>"],
                    "arguments": ["<pool>", "<amount_in>", "<min_amount_out>", "<clock>"] ,
                    "gas_budget": 1000000
                }
            }));
        } else if lower.contains("quote") || lower.contains("报价") {
            intent = "cetus_quote".to_string();
            confidence = 0.65;
            action = Some("quote".to_string());
            plan.push(json!({
                "tool": "cetus_quote",
                "params": {
                    "action": "quote",
                    "network": network,
                    "sender": sender,
                    "type_args": ["<from_coin>", "<to_coin>"],
                    "arguments": ["<pool>", "<amount>", "<by_amount_in>"]
                }
            }));
        } else if lower.contains("balance") || lower.contains("余额") {
            intent = "get_balance".to_string();
            confidence = 0.8;
            plan.push(json!({
                "tool": "get_balance",
                "params": {
                    "address": sender,
                    "coin_type": null
                }
            }));
        } else if lower.contains("transfer") || lower.contains("转账") || lower.contains("发送") {
            intent = "transfer".to_string();
            confidence = 0.6;
            let recipient = addresses.get(0).cloned().unwrap_or_else(|| "<recipient>".to_string());
            entities["recipient"] = json!(recipient);
            plan.push(json!({
                "tool": "build_transfer_sui",
                "params": {
                    "sender": sender,
                    "recipient": recipient,
                    "input_coins": [],
                    "auto_select_coins": true,
                    "amount": amount_u64,
                    "gas_budget": 1000000
                }
            }));
        } else if lower.contains("transfer object") || lower.contains("转对象") || lower.contains("转物") {
            intent = "transfer_object".to_string();
            confidence = 0.55;
            let object_id = addresses.get(0).cloned().unwrap_or_else(|| "<object_id>".to_string());
            let recipient = addresses.get(1).cloned().unwrap_or_else(|| "<recipient>".to_string());
            entities["object_id"] = json!(object_id);
            entities["recipient"] = json!(recipient);
            plan.push(json!({
                "tool": "build_transfer_object",
                "params": {
                    "sender": sender,
                    "object_id": object_id,
                    "recipient": recipient,
                    "gas_budget": 1000000,
                    "gas_object_id": null
                }
            }));
        } else if lower.contains("stake") || lower.contains("质押") {
            intent = "stake".to_string();
            confidence = 0.6;
            let validator = addresses.get(0).cloned().unwrap_or_else(|| "<validator>".to_string());
            entities["validator"] = json!(validator);
            plan.push(json!({
                "tool": "build_add_stake",
                "params": {
                    "sender": sender,
                    "validator": validator,
                    "coins": ["<coin_object_id>"],
                    "amount": amount_u64,
                    "gas_budget": 1000000,
                    "gas_object_id": null
                }
            }));
        } else if lower.contains("unstake") || lower.contains("withdraw stake") || lower.contains("取回") {
            intent = "unstake".to_string();
            confidence = 0.6;
            let staked_sui = addresses.get(0).cloned().unwrap_or_else(|| "<staked_sui>".to_string());
            entities["staked_sui"] = json!(staked_sui);
            plan.push(json!({
                "tool": "build_withdraw_stake",
                "params": {
                    "sender": sender,
                    "staked_sui": staked_sui,
                    "gas_budget": 1000000,
                    "gas_object_id": null
                }
            }));
        } else if lower.contains("mint") || lower.contains("铸造") {
            intent = "mint".to_string();
            confidence = 0.45;
            plan.push(json!({
                "tool": "auto_execute_move_call_filled",
                "params": {
                    "sender": sender,
                    "package": "<package>",
                    "module": "<module>",
                    "function": "<function>",
                    "type_args": [],
                    "arguments": [],
                    "gas_budget": 1000000,
                    "gas_object_id": null,
                    "gas_price": null,
                    "zk_login_inputs_json": "<zk_login_inputs_json>",
                    "address_seed": "<address_seed>",
                    "max_epoch": "<max_epoch>",
                    "user_signature": "<user_signature>"
                }
            }));
        } else if lower.contains("borrow") || lower.contains("借") {
            intent = "borrow".to_string();
            confidence = 0.45;
            plan.push(json!({
                "tool": "auto_execute_move_call_filled",
                "params": {
                    "sender": sender,
                    "package": "<package>",
                    "module": "<module>",
                    "function": "<function>",
                    "type_args": [],
                    "arguments": [],
                    "gas_budget": 1000000,
                    "gas_object_id": null,
                    "gas_price": null,
                    "zk_login_inputs_json": "<zk_login_inputs_json>",
                    "address_seed": "<address_seed>",
                    "max_epoch": "<max_epoch>",
                    "user_signature": "<user_signature>"
                }
            }));
        } else if lower.contains("lend") || lower.contains("贷") {
            intent = "lend".to_string();
            confidence = 0.45;
            plan.push(json!({
                "tool": "auto_execute_move_call_filled",
                "params": {
                    "sender": sender,
                    "package": "<package>",
                    "module": "<module>",
                    "function": "<function>",
                    "type_args": [],
                    "arguments": [],
                    "gas_budget": 1000000,
                    "gas_object_id": null,
                    "gas_price": null,
                    "zk_login_inputs_json": "<zk_login_inputs_json>",
                    "address_seed": "<address_seed>",
                    "max_epoch": "<max_epoch>",
                    "user_signature": "<user_signature>"
                }
            }));
        }

        (intent, action, entities, confidence, plan)
    }

    fn tool_plan_to_pipeline(plan: &[Value]) -> Vec<Value> {
        plan.iter()
            .map(|item| {
                let params = item.get("params").cloned().unwrap_or(Value::Null);
                let mut missing = Vec::new();
                Self::collect_placeholders(&params, &mut missing);
                json!({
                    "tool": item.get("tool").cloned().unwrap_or(Value::Null),
                    "params": params,
                    "ready": missing.is_empty(),
                    "missing": missing
                })
            })
            .collect()
    }

    fn collect_placeholders(value: &Value, missing: &mut Vec<String>) {
        match value {
            Value::String(value) => {
                if value.starts_with('<') && value.ends_with('>') {
                    missing.push(value.clone());
                }
            }
            Value::Array(items) => {
                for item in items {
                    Self::collect_placeholders(item, missing);
                }
            }
            Value::Object(map) => {
                for value in map.values() {
                    Self::collect_placeholders(value, missing);
                }
            }
            _ => {}
        }
    }

    fn extract_amount(_text: &str, lower: &str) -> Option<String> {
        if let Some(value) = Self::extract_arabic_number(lower) {
            return Some(value);
        }
        Self::extract_chinese_number(lower).map(|value| value.to_string())
    }

    fn extract_arabic_number(text: &str) -> Option<String> {
        let mut current = String::new();
        for ch in text.chars() {
            if ch.is_ascii_digit() || ch == '.' {
                current.push(ch);
            } else if !current.is_empty() {
                break;
            }
        }
        if current.is_empty() { None } else { Some(current) }
    }

    fn extract_chinese_number(text: &str) -> Option<u64> {
        let mut buffer = String::new();
        for ch in text.chars() {
            if "零一二三四五六七八九十百千万亿两".contains(ch) {
                buffer.push(ch);
            } else if !buffer.is_empty() {
                break;
            }
        }
        if buffer.is_empty() {
            return None;
        }

        let digits = |ch| match ch {
            '零' => Some(0),
            '一' => Some(1),
            '二' => Some(2),
            '两' => Some(2),
            '三' => Some(3),
            '四' => Some(4),
            '五' => Some(5),
            '六' => Some(6),
            '七' => Some(7),
            '八' => Some(8),
            '九' => Some(9),
            _ => None,
        };

        let mut total: u64 = 0;
        let mut section: u64 = 0;
        let mut number: u64 = 0;

        for ch in buffer.chars() {
            if let Some(value) = digits(ch) {
                number = value;
            } else {
                let unit = match ch {
                    '十' => 10,
                    '百' => 100,
                    '千' => 1000,
                    '万' => 10_000,
                    '亿' => 100_000_000,
                    _ => 1,
                };
                if unit >= 10_000 {
                    section = (section + number) * unit;
                    total += section;
                    section = 0;
                } else {
                    if number == 0 {
                        number = 1;
                    }
                    section += number * unit;
                }
                number = 0;
            }
        }
        Some(total + section + number)
    }

    fn extract_addresses(text: &str) -> Vec<String> {
        text.split_whitespace()
            .filter(|item| item.starts_with("0x"))
            .map(|item| item.trim_matches(|c: char| c == ',' || c == ';').to_string())
            .collect()
    }

    fn extract_tx_bytes(result: &CallToolResult) -> Option<String> {
        let text = Self::extract_text(result)?;
        serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|value| value.get("tx_bytes").and_then(|value| value.as_str()).map(|value| value.to_string()))
    }

    fn extract_text(result: &CallToolResult) -> Option<String> {
        let content = result.content.first()?;
        match &content.raw {
            RawContent::Text(text) => Some(text.text.clone()),
            RawContent::Resource(resource) => match &resource.resource {
                ResourceContents::TextResourceContents { text, .. } => Some(text.clone()),
                _ => None,
            },
            _ => None,
        }
    }
