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
        let is_quote = lower.contains("quote")
            || lower.contains("price")
            || lower.contains("报价")
            || lower.contains("价格")
            || lower.contains("询价");
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

        if is_quote {
            // crude token/amount extraction.
            // default placeholders.
            let mut amount = "<amount>".to_string();
            let mut from_token = "sol".to_string();
            let mut to_token = "usdc".to_string();

            // If user says "get"/"buy" we interpret as ExactOut quote (receive exact amount).
            let is_exact_out = lower.contains(" get ")
                || lower.contains(" buy ")
                || lower.contains("购买")
                || lower.contains("拿到");

            let cleaned = lower.replace([',', '/'], " ");
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

            // For exact-out phrasing, try parse: "quote <from> to get <amount> <to>".
            let mut swap_mode = "ExactIn".to_string();
            let mut amount_in: Option<String> = Some(amount.clone());
            let mut amount_out: Option<String> = None;

            if is_exact_out {
                for i in 0..words.len() {
                    if words[i] == "get" || words[i] == "buy" {
                        if i + 2 < words.len() {
                            amount_out = Some(words[i + 1].to_string());
                            to_token = words[i + 2].to_string();
                            swap_mode = "ExactOut".to_string();
                            amount_in = None;
                        }
                        break;
                    }
                }
            }

            let intent_value = if swap_mode == "ExactOut" {
                json!({
                    "chain": "solana",
                    "action": "quote",
                    "swap_mode": swap_mode,
                    "input_token": from_token,
                    "output_token": to_token,
                    "amount_out": amount_out.unwrap_or(amount),
                    "slippage_bps": slippage_bps,
                    "user_pubkey": sender,
                    "resolved_network": {
                        "family": "solana",
                        "network_name": net,
                    },
                    "confidence": 0.65
                })
            } else {
                json!({
                    "chain": "solana",
                    "action": "quote",
                    "swap_mode": swap_mode,
                    "input_token": from_token,
                    "output_token": to_token,
                    "amount_in": amount_in.unwrap_or(amount),
                    "slippage_bps": slippage_bps,
                    "user_pubkey": sender,
                    "resolved_network": {
                        "family": "solana",
                        "network_name": net,
                    },
                    "confidence": 0.7
                })
            };

            let conf = intent_value["confidence"].as_f64().unwrap_or(0.7);
            return ("quote".to_string(), intent_value, conf);
        }

        if is_swap {
            // crude token/amount extraction.
            // default placeholders.
            let mut amount = "<amount>".to_string();
            let mut from_token = "sol".to_string();
            let mut to_token = "usdc".to_string();

            // If user says "get"/"buy" we interpret as swap_exact_out (receive exact amount).
            let is_exact_out = lower.contains(" get ") || lower.contains(" buy ") || lower.contains("购买") || lower.contains("拿到");

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

            // For exact-out phrasing, try parse: "swap <from> to get <amount> <to>".
            let mut action = "swap_exact_in".to_string();
            let mut amount_in: Option<String> = Some(amount.clone());
            let mut amount_out: Option<String> = None;

            if is_exact_out {
                for i in 0..words.len() {
                    if words[i] == "get" || words[i] == "buy" {
                        if i + 2 < words.len() {
                            amount_out = Some(words[i + 1].to_string());
                            to_token = words[i + 2].to_string();
                            action = "swap_exact_out".to_string();
                            amount_in = None;
                        }
                        break;
                    }
                }
            }

            let intent_value = if action == "swap_exact_out" {
                json!({
                    "chain": "solana",
                    "action": action,
                    "input_token": from_token,
                    "output_token": to_token,
                    "amount_out": amount_out.unwrap_or(amount),
                    "slippage_bps": slippage_bps,
                    "user_pubkey": sender,
                    "resolved_network": {
                        "family": "solana",
                        "network_name": net,
                    },
                    "confidence": 0.65
                })
            } else {
                json!({
                    "chain": "solana",
                    "action": action,
                    "input_token": from_token,
                    "output_token": to_token,
                    "amount_in": amount_in.unwrap_or(amount),
                    "slippage_bps": slippage_bps,
                    "user_pubkey": sender,
                    "resolved_network": {
                        "family": "solana",
                        "network_name": net,
                    },
                    "confidence": 0.7
                })
            };

            let conf = intent_value["confidence"].as_f64().unwrap_or(0.7);
            return ("swap".to_string(), intent_value, conf);
        }

        // Read-only requests.
        let is_balance = lower.contains("balance")
            || lower.contains("holdings")
            || lower.contains("portfolio")
            || lower.contains("持仓")
            || lower.contains("余额");
        if is_balance {
            // Try parse token symbol: e.g. "balance usdc" / "usdc balance".
            let cleaned = lower.replace([',', '/'], " ");
            let words: Vec<&str> = cleaned.split_whitespace().collect();
            let mut symbol: Option<String> = None;
            for w in &words {
                if *w == "balance" || *w == "holdings" || *w == "portfolio" {
                    continue;
                }
                // crude: symbols are short-ish alphabetic strings
                if w.len() <= 10 && w.chars().all(|c| c.is_ascii_alphabetic()) {
                    symbol = Some(w.to_string());
                    break;
                }
            }

            let intent_value = json!({
                "chain": "solana",
                "action": "get_portfolio",
                "owner": sender,
                "symbol": symbol,
                "resolved_network": {
                    "family": "solana",
                    "network_name": net
                },
                "confidence": 0.8
            });
            return ("portfolio".to_string(), intent_value, 0.8);
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

            let action = if asset.to_lowercase() == "sol" {
                "transfer_native"
            } else {
                // For now: USDC/USDT supported as SPL.
                "transfer_spl"
            };

            let intent_value = json!({
                "chain": "solana",
                "action": action,
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
