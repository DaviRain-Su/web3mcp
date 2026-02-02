    /// Generate a transaction template for common actions
    #[tool(description = "Generate a transaction template for common actions")]
    async fn get_transaction_template(
        &self,
        Parameters(request): Parameters<TransactionTemplateRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let sender = request.sender.clone();
        let gas_budget = request.gas_budget.unwrap_or(1_000_000);
        let template = request.template.to_lowercase();

        let payload = match template.as_str() {
            "transfer_sui" => json!({
                "tool": "build_transfer_sui",
                "params": {
                    "sender": sender,
                    "recipient": request.recipient.unwrap_or_else(|| "<recipient>".to_string()),
                    "amount": request.amount.unwrap_or(10_000_000),
                    "input_coins": [],
                    "auto_select_coins": true,
                    "gas_budget": gas_budget
                }
            }),
            "transfer_object" => json!({
                "tool": "build_transfer_object",
                "params": {
                    "sender": sender,
                    "object_id": request.object_id.unwrap_or_else(|| "<object_id>".to_string()),
                    "recipient": request.recipient.unwrap_or_else(|| "<recipient>".to_string()),
                    "gas_budget": gas_budget,
                    "gas_object_id": request.gas_object_id
                }
            }),
            "stake" => json!({
                "tool": "build_add_stake",
                "params": {
                    "sender": sender,
                    "validator": request.validator.unwrap_or_else(|| "<validator>".to_string()),
                    "coins": ["<coin_object_id>"],
                    "amount": request.amount,
                    "gas_budget": gas_budget,
                    "gas_object_id": request.gas_object_id
                }
            }),
            "unstake" => json!({
                "tool": "build_withdraw_stake",
                "params": {
                    "sender": sender,
                    "staked_sui": request.staked_sui.unwrap_or_else(|| "<staked_sui>".to_string()),
                    "gas_budget": gas_budget,
                    "gas_object_id": request.gas_object_id
                }
            }),
            "pay_sui" => json!({
                "tool": "build_pay_sui",
                "params": {
                    "sender": sender,
                    "recipients": request.recipients.unwrap_or_else(|| vec!["<recipient>".to_string()]),
                    "amounts": request.amounts.unwrap_or_else(|| vec![10_000_000]),
                    "input_coins": ["<coin_object_id>"],
                    "gas_budget": gas_budget
                }
            }),
            other => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Unknown template '{}'. Use transfer_sui|transfer_object|stake|unstake|pay_sui",
                        other
                    )),
                    data: None,
                })
            }
        };

        let response = Self::pretty_json(&json!({
            "template": template,
            "payload": payload
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
