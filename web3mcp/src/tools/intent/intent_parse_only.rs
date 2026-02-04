    // ---------------- W3RT minimal intent parsing (Solana-first) ----------------

    fn w3rt_parse_intent_plan(
        text: &str,
        sender: String,
        network: Option<String>,
    ) -> (String, Value, f64) {
        // Minimal parser: only supports Solana swap intent schema needed by w3rt_run_workflow_v0.
        // Everything else is returned as generic intent.
        let lower = text.to_lowercase();

        // Network: detect mainnet/devnet/testnet. Default mainnet.
        let mut net = network.unwrap_or_else(|| {
            if lower.contains("devnet") {
                "devnet".to_string()
            } else if lower.contains("testnet") {
                "testnet".to_string()
            } else {
                "mainnet".to_string()
            }
        });
        if net.trim().is_empty() {
            net = "mainnet".to_string();
        }

        // Very simple intent detectors.
        let is_swap = lower.contains("swap") || lower.contains("换") || lower.contains("兑换");
        let is_transfer = lower.contains("send ") || lower.contains("transfer ") || lower.contains("转 ") || lower.contains("转账");

        // Slippage bps (optional)
        let mut slippage_bps: u64 = 100;
        if let Some(idx) = lower.find("slippage") {
            let tail = &lower[idx..];
            // Try parse like "slippage 0.5%" or "slippage 1%"
            let parts: Vec<&str> = tail.split_whitespace().collect();
            if parts.len() >= 2 {
                let mut v = parts[1].trim().to_string();
                v = v.trim_end_matches('%').to_string();
                if let Ok(p) = v.parse::<f64>() {
                    slippage_bps = (p * 100.0).round() as u64;
                }
            }
        }

        if is_swap {
            // crude token/amount extraction: find first number token pair and "to" token.
            // default placeholders.
            let mut amount = "<amount>".to_string();
            let mut from_token = "sol".to_string();
            let mut to_token = "usdc".to_string();

            // token words
            let cleaned = lower.replace(',', " ").replace("/", " ");
            let words: Vec<&str> = cleaned.split_whitespace().collect();

            // find amount + from token
            for i in 0..words.len() {
                if words[i].chars().any(|c| c.is_ascii_digit()) {
                    amount = words[i].to_string();
                    if i + 1 < words.len() {
                        from_token = words[i + 1].to_string();
                    }
                    break;
                }
            }

            // find "to" token
            for i in 0..words.len() {
                if words[i] == "to" || words[i] == "->" {
                    if i + 1 < words.len() {
                        to_token = words[i + 1].to_string();
                    }
                    break;
                }
            }

            let intent_value = json!({
                "chain": "solana",
                "action": "swap_exact_in",
                "input_token": from_token,
                "output_token": to_token,
                "amount_in": amount,
                "slippage_bps": slippage_bps,
                "user_pubkey": sender,
                "resolved_network": {
                    "family": "solana",
                    "network_name": net,
                },
                "confidence": 0.7
            });

            return ("swap".to_string(), intent_value, 0.7);
        }

        if is_transfer {
            // Minimal SOL transfer parsing:
            // - "send 0.01 sol to <pubkey>"
            // - "transfer 0.5 sol to <pubkey>"
            let cleaned = lower.replace(',', " ").replace("/", " ");
            let words: Vec<&str> = cleaned.split_whitespace().collect();

            let mut amount = "<amount>".to_string();
            let mut asset = "sol".to_string();
            let mut to_addr = "<recipient>".to_string();

            for i in 0..words.len() {
                if words[i].chars().any(|c| c.is_ascii_digit()) {
                    amount = words[i].to_string();
                    if i + 1 < words.len() {
                        asset = words[i + 1].to_string();
                    }
                    break;
                }
            }

            for i in 0..words.len() {
                if words[i] == "to" {
                    if i + 1 < words.len() {
                        to_addr = words[i + 1].to_string();
                    }
                    break;
                }
            }

            let intent_value = json!({
                "chain": "solana",
                "action": "transfer_native",
                "asset": asset,
                "amount": amount,
                "to": to_addr,
                "from": sender,
                "resolved_network": {
                    "family": "solana",
                    "network_name": net
                },
                "confidence": 0.7
            });

            return ("transfer".to_string(), intent_value, 0.7);
        }

        (
            "unknown".to_string(),
            json!({
                "intent": "unknown",
                "raw": text,
                "sender": sender,
                "network": net,
                "confidence": 0.2
            }),
            0.2,
        )
    }
