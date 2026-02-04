    #[cfg(feature = "solana-extended-tools")]
    const SOLANA_ERROR_OK: &str = "Ok";
    const SOLANA_ERROR_MISSING_ACCOUNT: &str = "MissingAccount";
    const SOLANA_ERROR_TYPE: &str = "TypeError";
    #[cfg(feature = "solana-extended-tools")]
    const SOLANA_ERROR_ANCHOR: &str = "AnchorConstraint";
    const SOLANA_ERROR_PROGRAM: &str = "ProgramError";

    fn solana_classify_send_error(msg: &str) -> (String, Option<String>) {
        let m = msg.to_lowercase();
        if m.contains("blockhash") {
            return (
                Self::SOLANA_ERROR_PROGRAM.to_string(),
                Some(
                    "Blockhash not found/expired. Rebuild the tx with a fresh recentBlockhash."
                        .to_string(),
                ),
            );
        }
        if m.contains("insufficient") {
            return (
                Self::SOLANA_ERROR_PROGRAM.to_string(),
                Some("Insufficient funds for fees or rent. Top up fee payer and retry.".to_string()),
            );
        }
        if m.contains("signature") && (m.contains("verify") || m.contains("missing")) {
            return (
                Self::SOLANA_ERROR_TYPE.to_string(),
                Some(
                    "Transaction appears unsigned or has invalid signatures. Ensure SOLANA_KEYPAIR_PATH is set or provide a fully signed tx."
                        .to_string(),
                ),
            );
        }
        if m.contains("account not found") || m.contains("could not find account") {
            return (
                Self::SOLANA_ERROR_MISSING_ACCOUNT.to_string(),
                Some(
                    "One or more accounts were missing on-chain. Ensure all accounts exist (ATA/PDA creation may be required)."
                        .to_string(),
                ),
            );
        }
        (Self::SOLANA_ERROR_PROGRAM.to_string(), None)
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_classify_simulation(err: &Value, logs: &[String]) -> (String, Option<String>) {
        // error_class values are intentionally stable strings for downstream agents:
        // - MissingAccount
        // - TypeError
        // - AnchorConstraint
        // - ProgramError
        // - Ok

        // Intentionally heuristic.
        let err_s = err.to_string();
        let mut error_class = Self::SOLANA_ERROR_PROGRAM.to_string();

        if err_s.contains("AccountNotFound") || err_s.contains("MissingAccount") {
            error_class = Self::SOLANA_ERROR_MISSING_ACCOUNT.to_string();
        } else if err_s.contains("InvalidArgument")
            || err_s.contains("InvalidInstructionData")
            || err_s.contains("InvalidAccountData")
        {
            error_class = Self::SOLANA_ERROR_TYPE.to_string();
        }

        if logs
            .iter()
            .any(|l| l.contains("AnchorError") || l.contains("AnchorError occurred"))
        {
            error_class = Self::SOLANA_ERROR_ANCHOR.to_string();
        }

        let suggest_fix = if error_class == "MissingAccount" {
            Some(
                "One or more required accounts were not provided or are invalid. Re-run plan and fill missing accounts (ATA/PDA/system/token program IDs)."
                    .to_string(),
            )
        } else if error_class == "TypeError" {
            Some(
                "Instruction data likely failed to decode. Check IDL arg types; ensure all u64/u128 amounts are strings; ensure enums/options match the IDL."
                    .to_string(),
            )
        } else if error_class == "AnchorConstraint" {
            Some(
                "Anchor constraint failed (has_one/constraint/owner/seeds). Check accounts correspond to the expected PDA/ATA and signers are correct."
                    .to_string(),
            )
        } else {
            logs.iter()
                .rev()
                .find(|l| l.contains("custom program error") || l.contains("Program log:"))
                .map(|l| format!("Review program logs; last relevant line: {}", l))
        };

        (error_class, suggest_fix)
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_known_program_label(pid: &str) -> Option<&'static str> { 
        match pid {
            // Core
            "11111111111111111111111111111111" => Some("System Program"),
            "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr" => Some("Memo Program"),
            "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL" => Some("Associated Token Account Program"),
            "ComputeBudget111111111111111111111111111111" => Some("Compute Budget Program"),

            // DeFi (common)
            "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4" => Some("Jupiter (V6)"),
            "MFv2hWf31Z9kbCa1snEPYctwafyhdvnV7FZnsebVacA" => Some("Marginfi"),
            "dRiftyHA39MWEi3m9aunc5MzRF1JYuBsbn6VPcn33UH" => Some("Drift"),
            "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc" => Some("Orca Whirlpool"),
            "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8" => Some("Raydium AMM v4"),
            "MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD" => Some("Marinade"),

            // More programs from omniweb3-mcp idl_registry/programs.json
            "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo" => Some("Meteora DLMM"),
            "cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG" => Some("Meteora DAMM v2"),
            "Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB" => Some("Meteora DAMM v1"),
            "dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN" => Some("Meteora DBC"),
            "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P" => Some("Pump.fun"),
            "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf" => Some("Squads V4"),
            "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK" => Some("Raydium CLMM"),
            "3ZZuTbwC6aJbvteyVxXUS7gtFYdf7AuXeitx6VyvjvUp" => Some("Jupiter Prediction Market"),
            "save8RQVPMWNTzU18t3GBvBkN9hT7jsGjiCQ28FpD9H" => Some("Bankineco"),

            // Known but may not have IDL in this repo (still useful for preview labels)
            "KLend2g3cP87ber41qQDzWpAFuqP2tCxDqC8S3k7L1U" => Some("Kamino Lending"),
            "FEESngU3neckdwib9X3KWqdL7Mjmqk1XNp3uh5JbP4KP" => Some("Meteora M3M3"),
            "5ocnV1qiCgaQR8Jb8xWnVbApfaygJ8tNoZfgPwsgx9kx" => Some("Sanctum S Controller"),

            // Common swap mints (not programs, but helpful when showing account lists)
            "So11111111111111111111111111111111111111112" => Some("Wrapped SOL mint"),
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" => Some("USDC mint"),

            // Metaplex
            "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s" => Some("Metaplex Token Metadata"),

            // Address lookup tables (v0)
            "AddressLookupTab1e1111111111111111111111111" => {
                Some("Address Lookup Table Program")
            }

            _ => None,
        }
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_is_known_safe_address(addr: &str) -> bool {
        // Addresses that are safe/expected to show up in txs and should not trigger unknown-program alarms.
        // Note: we intentionally treat "known labels" (including mints) as safe here.
        // (We accept a few string comparisons here; this runs only during previews.)
        addr == "11111111111111111111111111111111"
            || addr == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" // SPL Token
            || addr == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" // SPL Token 2022
            || addr == "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL" // ATA
            || addr == "ComputeBudget111111111111111111111111111111" // ComputeBudget
            || addr == "Sysvar1nstructions1111111111111111111111111"
            || addr == "SysvarC1ock11111111111111111111111111111111"
            || Self::solana_known_program_label(addr).is_some()
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_jup_swap_dex_label(swap_dbg: &str) -> Option<&'static str> {
        // Best-effort mapping from carbon-jupiter Swap debug output to a human label.
        // Example debug strings:
        // - "Whirlpool { a_to_b: true }"
        // - "RaydiumClmm"
        // - "MeteoraDlmm"
        // - "LifinityV2"
        let s = swap_dbg;
        if s.starts_with("Whirlpool") || s.starts_with("WhirlpoolSwapV2") {
            Some("Orca Whirlpool")
        } else if s.starts_with("Raydium") || s.starts_with("RaydiumClmm") || s.starts_with("RaydiumCP") {
            Some("Raydium")
        } else if s.starts_with("Meteora") || s.starts_with("MeteoraDlmm") || s.starts_with("MeteoraDamm") {
            Some("Meteora")
        } else if s.starts_with("Orca") {
            Some("Orca")
        } else if s.starts_with("Phoenix") {
            Some("Phoenix")
        } else if s.starts_with("Openbook") || s.starts_with("OpenBook") {
            Some("OpenBook")
        } else if s.starts_with("Jupiter") {
            Some("Jupiter")
        } else if s.starts_with("Lifinity") {
            Some("Lifinity")
        } else if s.starts_with("Saber") {
            Some("Saber")
        } else if s.starts_with("TokenSwap") {
            Some("TokenSwap")
        } else if s.starts_with("Marinade") {
            Some("Marinade")
        } else if s.starts_with("Perps") {
            Some("Perps")
        } else if s.starts_with("Pump") {
            Some("Pump")
        } else {
            None
        }
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_jup_swap_direction(swap_dbg: &str) -> Option<String> {
        // Extract direction-like booleans from the Debug string.
        // We keep this intentionally lightweight (string contains checks).
        if swap_dbg.contains("a_to_b: true") {
            Some("a_to_b".to_string())
        } else if swap_dbg.contains("a_to_b: false") {
            Some("b_to_a".to_string())
        } else if swap_dbg.contains("x_to_y: true") {
            Some("x_to_y".to_string())
        } else if swap_dbg.contains("x_to_y: false") {
            Some("y_to_x".to_string())
        } else if swap_dbg.contains("is_quote_to_base: true") {
            Some("quote_to_base".to_string())
        } else if swap_dbg.contains("is_quote_to_base: false") {
            Some("base_to_quote".to_string())
        } else if swap_dbg.contains("is_base_to_quote: false") {
            Some("quote_to_base".to_string())
        } else {
            None
        }
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_jup_swap_side(swap_dbg: &str) -> Option<&'static str> {
        // For orderbook-style swaps (Serum/OpenBook/Phoenix), Carbon's Debug includes side.
        if swap_dbg.contains("side: Bid") {
            Some("bid")
        } else if swap_dbg.contains("side: Ask") {
            Some("ask")
        } else {
            None
        }
    }

    fn solana_rpc_url_for_network(network: Option<&str>) -> Result<String, ErrorData> {
        // Priority:
        // 1) SOLANA_RPC_URL (explicit override)
        // 2) SOLANA_RPC_URL_MAINNET / _DEVNET / _TESTNET
        // 3) well-known public endpoints
        if let Ok(url) = std::env::var("SOLANA_RPC_URL") {
            return Ok(url);
        }

        let net = network.unwrap_or("mainnet").trim().to_lowercase();
        let (env_key, default_url) = match net.as_str() {
            "mainnet" | "mainnet-beta" | "mainnet_beta" => (
                "SOLANA_RPC_URL_MAINNET",
                "https://api.mainnet-beta.solana.com",
            ),
            "devnet" => ("SOLANA_RPC_URL_DEVNET", "https://api.devnet.solana.com"),
            "testnet" => ("SOLANA_RPC_URL_TESTNET", "https://api.testnet.solana.com"),
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("network must be one of: mainnet|devnet|testnet"),
                    data: Some(json!({"provided": net})),
                })
            }
        };

        Ok(std::env::var(env_key).unwrap_or_else(|_| default_url.to_string()))
    }

    fn solana_rpc_url_default() -> String {
        Self::solana_rpc_url_for_network(None)
            .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string())
    }

    fn solana_keypair_path() -> Result<String, ErrorData> {
        std::env::var("SOLANA_KEYPAIR_PATH").map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(
                "Missing SOLANA_KEYPAIR_PATH env var (path to Solana JSON keypair file)",
            ),
            data: None,
        })
    }

    fn solana_read_keypair_from_json_file(
        path: &str,
    ) -> Result<solana_sdk::signature::Keypair, ErrorData> {
        let data = std::fs::read_to_string(path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read keypair file: {}", e)),
            data: None,
        })?;
        let arr: Vec<u8> = serde_json::from_str(&data).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid Solana keypair JSON: {}", e)),
            data: None,
        })?;
        solana_sdk::signature::Keypair::try_from(arr.as_slice()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid Solana keypair bytes: {}", e)),
            data: None,
        })
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_parse_pubkey(value: &str, label: &str) -> Result<solana_sdk::pubkey::Pubkey, ErrorData> {
        solana_sdk::pubkey::Pubkey::from_str(value).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid {}: {}", label, e)),
            data: None,
        })
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_parse_program_id(program_id: &str) -> Result<solana_sdk::pubkey::Pubkey, ErrorData> {
        Self::solana_parse_pubkey(program_id, "program_id")
    }

    fn solana_commitment_from_str(
        s: Option<&str>,
    ) -> Result<solana_commitment_config::CommitmentConfig, ErrorData> {
        let v = s.unwrap_or("confirmed").trim().to_lowercase();
        let c = match v.as_str() {
            "processed" => solana_commitment_config::CommitmentConfig::processed(),
            "confirmed" => solana_commitment_config::CommitmentConfig::confirmed(),
            "finalized" => solana_commitment_config::CommitmentConfig::finalized(),
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("commitment must be one of: processed|confirmed|finalized"),
                    data: Some(json!({ "provided": v })),
                })
            }
        };
        Ok(c)
    }

    fn solana_rpc(
        network: Option<&str>,
    ) -> Result<solana_client::nonblocking::rpc_client::RpcClient, ErrorData> {
        let url = Self::solana_rpc_url_for_network(network)?;
        Ok(solana_client::nonblocking::rpc_client::RpcClient::new(url))
    }

    fn solana_keypair_path_with_default(path: Option<&str>) -> Result<String, ErrorData> {
        if let Some(p) = path {
            return Ok(p.to_string());
        }
        if let Ok(p) = std::env::var("SOLANA_KEYPAIR_PATH") {
            return Ok(p);
        }
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        Ok(format!("{}/.config/solana/id.json", home))
    }

    #[tool(description = "Solana: get wallet address from SOLANA_KEYPAIR_PATH JSON")]
    async fn solana_get_wallet_address(&self) -> Result<CallToolResult, ErrorData> {
        let kp_path = Self::solana_keypair_path()?;
        let kp = Self::solana_read_keypair_from_json_file(&kp_path)?;
        let addr = solana_sdk::signature::Signer::pubkey(&kp).to_string();
        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_default(),
            "keypair_path": kp_path,
            "address": addr
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get keypair info (address) from a custom path or default")]
    async fn solana_keypair_info(
        &self,
        Parameters(request): Parameters<SolanaKeypairInfoRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let kp_path = Self::solana_keypair_path_with_default(request.keypair_path.as_deref())?;
        let kp = Self::solana_read_keypair_from_json_file(&kp_path)?;
        let addr = solana_sdk::signature::Signer::pubkey(&kp).to_string();
        let response = Self::pretty_json(&json!({
            "keypair_path": kp_path,
            "address": addr
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // ---------------- Solana DeFi APIs (off-chain) ----------------

    fn solana_meteora_dlmm_api_base_url() -> String {
        std::env::var("SOLANA_METEORA_DLMM_API_BASE_URL")
            .unwrap_or_else(|_| "https://dlmm-api.meteora.ag".to_string())
    }

    async fn solana_http_get_json(
        url: &str,
        timeout_ms: u64,
    ) -> Result<(reqwest::StatusCode, Value), ErrorData> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(timeout_ms))
            .build()
            .map_err(|e| Self::sdk_error("solana_http_get_json:client", e))?;

        let resp = client
            .get(url)
            .send()
            .await
            .map_err(|e| Self::sdk_error("solana_http_get_json:request", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| Self::sdk_error("solana_http_get_json:read_body", e))?;

        let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({ "raw": text }));
        Ok((status, parsed))
    }

    #[tool(description = "Meteora DLMM API: raw HTTP call (GET/POST minimal).")]
    async fn solana_meteora_dlmm_api_call(
        &self,
        Parameters(request): Parameters<SolanaMeteoraApiCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = request
            .base_url
            .unwrap_or_else(Self::solana_meteora_dlmm_api_base_url);

        let method = request
            .method
            .as_deref()
            .unwrap_or("GET")
            .trim()
            .to_uppercase();

        let path = request.path.trim();
        if path.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("path is required"),
                data: None,
            });
        }

        let base = base_url.trim_end_matches('/');
        let path = if path.starts_with('/') {
            path.to_string()
        } else {
            format!("/{}", path)
        };
        let mut url = format!("{}{}", base, path);

        if let Some(q) = request.query.as_ref().and_then(|v| v.as_object()) {
            let mut first = true;
            for (k, v) in q.iter() {
                let vs = if v.is_string() {
                    v.as_str().unwrap_or("").to_string()
                } else {
                    v.to_string()
                };
                url.push(if first { '?' } else { '&' });
                first = false;
                url.push_str(&format!("{}={}", urlencoding::encode(k), urlencoding::encode(&vs)));
            }
        }

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);

        let (status, parsed) = match method.as_str() {
            "GET" => Self::solana_http_get_json(&url, timeout_ms).await?,
            other => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Unsupported method: {} (only GET supported for now)", other)),
                    data: None,
                })
            }
        };

        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from Meteora DLMM API"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
            });
        }

        if request.result_only.unwrap_or(true) {
            let response = Self::pretty_json(&parsed)?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let response = Self::pretty_json(&json!({"url": url, "status": status.as_u16(), "body": parsed}))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Meteora DLMM API: list all DLMM pairs (pool metadata)")]
    async fn solana_meteora_dlmm_list_pairs(
        &self,
        Parameters(request): Parameters<SolanaMeteoraDlmmListPairsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = request
            .base_url
            .unwrap_or_else(Self::solana_meteora_dlmm_api_base_url);
        let url = format!("{}/pair/all", base_url.trim_end_matches('/'));

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);
        let (status, parsed) = Self::solana_http_get_json(&url, timeout_ms).await?;
        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from Meteora DLMM API"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
            });
        }

        let response = Self::pretty_json(&json!({
            "base_url": base_url,
            "count": parsed.as_array().map(|a| a.len()),
            "pairs": parsed
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Meteora DLMM API: get a specific DLMM pair by address")]
    async fn solana_meteora_dlmm_get_pair(
        &self,
        Parameters(request): Parameters<SolanaMeteoraDlmmGetPairRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = request
            .base_url
            .unwrap_or_else(Self::solana_meteora_dlmm_api_base_url);
        let addr = request.pair_address.trim();
        let url = format!("{}/pair/{}", base_url.trim_end_matches('/'), addr);

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);
        let (status, parsed) = Self::solana_http_get_json(&url, timeout_ms).await?;
        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from Meteora DLMM API"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
            });
        }

        let response = Self::pretty_json(&json!({
            "base_url": base_url,
            "pair_address": addr,
            "pair": parsed
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_meteora_dlmm_idl_json() -> serde_json::Value {
        // Bundled from the archived Omni Web3 MCP project.
        // Program: Meteora DLMM (LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo)
        let s = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../archive/omniweb3-mcp/idl_registry/LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo.json"
        ));
        serde_json::from_str(s).unwrap_or_else(|_| json!({ "raw": s }))
    }

    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Meteora DLMM (IDL): plan an instruction (default add_liquidity). Returns args/accounts plus fill-me templates."))]
    async fn solana_meteora_dlmm_plan(
        &self,
        Parameters(request): Parameters<SolanaMeteoraDlmmPlanRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        #[cfg(not(feature = "solana-extended-tools"))]
        {
            let _ = request;
            Err(ErrorData {
                code: ErrorCode(-32601),
                message: Cow::from(
                    "Tool not available: built without feature solana-extended-tools (rebuild with --features solana-extended-tools)",
                ),
                data: None,
            })
        }

        #[cfg(feature = "solana-extended-tools")]
        {
            let program_id = "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo";
            let idl = Self::solana_meteora_dlmm_idl_json();

            let instruction_name = request
                .instruction
                .as_deref()
                .unwrap_or("add_liquidity")
                .trim();
            if instruction_name.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("instruction is required"),
                    data: None,
                });
            }

            let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, instruction_name)
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Unknown instruction in Meteora DLMM IDL: {}",
                        e
                    )),
                    data: Some(json!({
                        "program_id": program_id,
                        "instruction": instruction_name,
                        "hint": "Use solana_idl_list_instructions or solana_idl_search to inspect available instructions"
                    })),
                })?;

            let include_templates = request.include_templates.unwrap_or(true);

            let args = ix
                .args
                .iter()
                .map(|a| {
                    json!({
                        "name": a.name,
                        "type": a.ty,
                    })
                })
                .collect::<Vec<Value>>();

            let accounts = ix
                .accounts
                .iter()
                .map(|a| {
                    json!({
                        "name": a.name,
                        "is_signer": a.is_signer,
                        "is_writable": a.is_mut,
                    })
                })
                .collect::<Vec<Value>>();

            let out = if include_templates {
                let mut args_template = serde_json::Map::new();
                for a in ix.args.iter() {
                    args_template.insert(a.name.clone(), json!("__FILL_ME__"));
                }

                let mut accounts_template = serde_json::Map::new();
                for a in ix.accounts.iter() {
                    accounts_template.insert(a.name.clone(), json!("__FILL_ME__"));
                }

                json!({
                    "ok": true,
                    "program_id": program_id,
                    "instruction": ix.name,
                    "args": args,
                    "accounts": accounts,
                    "args_template": Value::Object(args_template),
                    "accounts_template": Value::Object(accounts_template),
                    "next": {
                        "tool": "solana_meteora_dlmm_build_tx",
                        "args": {
                            "instruction": ix.name,
                            "args": "(fill args_template)",
                            "accounts": "(fill accounts_template)"
                        }
                    }
                })
            } else {
                json!({
                    "ok": true,
                    "program_id": program_id,
                    "instruction": ix.name,
                    "args": args,
                    "accounts": accounts
                })
            };

            let response = Self::pretty_json(&out)?;
            Ok(CallToolResult::success(vec![Content::text(response)]))
        }
    }

    fn meteora_pair_first_string(v: &Value, keys: &[&str]) -> Option<String> {
        let obj = v.as_object()?;
        for k in keys {
            if let Some(val) = obj.get(*k) {
                if let Some(s) = val.as_str() {
                    let ss = s.trim();
                    if !ss.is_empty() {
                        return Some(ss.to_string());
                    }
                }
            }
        }
        None
    }

    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Meteora DLMM (IDL): fetch pair metadata and produce a best-effort filled args/accounts template for add_liquidity. This is heuristic and may require manual edits."))]
    async fn solana_meteora_dlmm_fill_template(
        &self,
        Parameters(request): Parameters<SolanaMeteoraDlmmFillTemplateRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        #[cfg(not(feature = "solana-extended-tools"))]
        {
            let _ = request;
            Err(ErrorData {
                code: ErrorCode(-32601),
                message: Cow::from(
                    "Tool not available: built without feature solana-extended-tools (rebuild with --features solana-extended-tools)",
                ),
                data: None,
            })
        }

        #[cfg(feature = "solana-extended-tools")]
        {
            let program_id = "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo";
            let idl = Self::solana_meteora_dlmm_idl_json();

            let instruction_name = request
                .instruction
                .as_deref()
                .unwrap_or("add_liquidity")
                .trim();
            if instruction_name.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("instruction is required"),
                    data: None,
                });
            }

            // 1) Fetch pair metadata from Meteora DLMM API
            let base_url = request
                .base_url
                .unwrap_or_else(Self::solana_meteora_dlmm_api_base_url);
            let addr = request.pair_address.trim();
            let url = format!("{}/pair/{}", base_url.trim_end_matches('/'), addr);
            let timeout_ms = request.timeout_ms.unwrap_or(15_000);
            let (status, pair) = Self::solana_http_get_json(&url, timeout_ms).await?;
            if !status.is_success() {
                return Err(ErrorData {
                    code: ErrorCode(i32::from(status.as_u16())),
                    message: Cow::from("HTTP error from Meteora DLMM API"),
                    data: Some(json!({"url": url, "status": status.as_u16(), "body": pair})),
                });
            }

            // Attempt to detect mint fields
            let mint_x = Self::meteora_pair_first_string(
                &pair,
                &[
                    "mint_x",
                    "mintX",
                    "tokenXMint",
                    "token_x_mint",
                    "token0Mint",
                    "token0_mint",
                ],
            );
            let mint_y = Self::meteora_pair_first_string(
                &pair,
                &[
                    "mint_y",
                    "mintY",
                    "tokenYMint",
                    "token_y_mint",
                    "token1Mint",
                    "token1_mint",
                ],
            );

            let owner_pk = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
            let fee_payer_pk = if let Some(fp) = request.fee_payer.as_deref() {
                Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
            } else {
                owner_pk
            };

            let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, instruction_name)
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Unknown instruction in Meteora DLMM IDL: {}",
                        e
                    )),
                    data: Some(json!({
                        "program_id": program_id,
                        "instruction": instruction_name
                    })),
                })?;

            // 2) Fill accounts template heuristically
            let mut accounts_template = serde_json::Map::new();
            let mut filled: Vec<Value> = Vec::new();

            for a in ix.accounts.iter() {
                let n = a.name.to_lowercase();

                let mut val: Option<String> = None;
                let mut reason: Option<String> = None;

                if n.contains("lb_pair") || n == "pair" || n.ends_with("_pair") {
                    val = Some(addr.to_string());
                    reason = Some("pair_address".to_string());
                } else if n.contains("mint_x") || n.contains("token_x_mint") || n.contains("token0_mint") {
                    if let Some(ref mx) = mint_x {
                        val = Some(mx.clone());
                        reason = Some("pair.mint_x".to_string());
                    }
                } else if n.contains("mint_y") || n.contains("token_y_mint") || n.contains("token1_mint") {
                    if let Some(ref my) = mint_y {
                        val = Some(my.clone());
                        reason = Some("pair.mint_y".to_string());
                    }
                } else if n.contains("fee_payer") || n == "payer" {
                    val = Some(fee_payer_pk.to_string());
                    reason = Some("fee_payer".to_string());
                } else if n.contains("owner") || n.contains("user") || n.contains("authority") {
                    val = Some(owner_pk.to_string());
                    reason = Some("owner".to_string());
                } else if (n.contains("token") || n.contains("ata")) && (n.contains("user") || n.contains("owner")) {
                    // Attempt ATA derivation for token accounts
                    if (n.contains("x") || n.contains("0")) && mint_x.is_some() {
                        let mx = Self::solana_parse_pubkey(mint_x.as_ref().unwrap(), "mint_x")?;
                        let ata = spl_associated_token_account::get_associated_token_address(&owner_pk, &mx);
                        val = Some(ata.to_string());
                        reason = Some("derived_ata(owner,mint_x)".to_string());
                    } else if (n.contains("y") || n.contains("1")) && mint_y.is_some() {
                        let my = Self::solana_parse_pubkey(mint_y.as_ref().unwrap(), "mint_y")?;
                        let ata = spl_associated_token_account::get_associated_token_address(&owner_pk, &my);
                        val = Some(ata.to_string());
                        reason = Some("derived_ata(owner,mint_y)".to_string());
                    }
                }

                let out_val = val.clone().unwrap_or_else(|| "__FILL_ME__".to_string());
                accounts_template.insert(a.name.clone(), Value::String(out_val));

                if let (Some(v), Some(r)) = (val, reason) {
                    filled.push(json!({"account": a.name, "value": v, "reason": r}));
                }
            }

            // 3) Fill args template heuristically
            let mut args_template = serde_json::Map::new();
            let mut args_filled: Vec<Value> = Vec::new();

            for a in ix.args.iter() {
                let n = a.name.to_lowercase();
                let mut val: Option<Value> = None;
                let mut reason: Option<String> = None;

                if (n.contains("amount") || n.contains("liquidity")) && (n.contains("x") || n.contains("0")) {
                    if let Some(ref s) = request.amount_x_raw {
                        val = Some(Value::String(s.clone()));
                        reason = Some("amount_x_raw".to_string());
                    }
                } else if (n.contains("amount") || n.contains("liquidity")) && (n.contains("y") || n.contains("1")) {
                    if let Some(ref s) = request.amount_y_raw {
                        val = Some(Value::String(s.clone()));
                        reason = Some("amount_y_raw".to_string());
                    }
                }

                args_template.insert(
                    a.name.clone(),
                    val.clone().unwrap_or_else(|| Value::String("__FILL_ME__".to_string())),
                );

                if let (Some(v), Some(r)) = (val, reason) {
                    args_filled.push(json!({"arg": a.name, "value": v, "reason": r}));
                }
            }

            let response = Self::pretty_json(&json!({
                "ok": true,
                "program_id": program_id,
                "instruction": ix.name,
                "pair_api": {
                    "base_url": base_url,
                    "url": url
                },
                "pair_detected": {
                    "pair_address": addr,
                    "mint_x": mint_x,
                    "mint_y": mint_y
                },
                "filled_accounts": filled,
                "filled_args": args_filled,
                "accounts_template": Value::Object(accounts_template),
                "args_template": Value::Object(args_template),
                "next": {
                    "tool": "solana_meteora_dlmm_build_tx",
                    "args": {
                        "network": request.network,
                        "instruction": ix.name,
                        "args": Value::Object(args_template),
                        "accounts": Value::Object(accounts_template),
                        "sign": true,
                        "create_pending": true
                    }
                },
                "note": "Heuristic fill only. You will likely need to replace __FILL_ME__ fields (especially PDAs/position accounts)."
            }))?;

            Ok(CallToolResult::success(vec![Content::text(response)]))
        }
    }

    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Meteora DLMM (IDL): build a transaction for a single DLMM instruction (default add_liquidity). Safe: returns tx_base64 and creates a pending confirmation by default (no broadcast)."))]
    async fn solana_meteora_dlmm_build_tx(
        &self,
        Parameters(request): Parameters<SolanaMeteoraDlmmBuildTxRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        #[cfg(not(feature = "solana-extended-tools"))]
        {
            let _ = request;
            Err(ErrorData {
                code: ErrorCode(-32601),
                message: Cow::from(
                    "Tool not available: built without feature solana-extended-tools (rebuild with --features solana-extended-tools)",
                ),
                data: None,
            })
        }

        #[cfg(feature = "solana-extended-tools")]
        {
            let network = request.network.as_deref();
            let network_str = network.unwrap_or("mainnet").trim().to_lowercase();
            let rpc_url = Self::solana_rpc_url_for_network(network)?;
            let client = Self::solana_rpc(network)?;

            let program_id = "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo";
            let idl = Self::solana_meteora_dlmm_idl_json();

            let instruction_name = request
                .instruction
                .as_deref()
                .unwrap_or("add_liquidity")
                .trim();
            if instruction_name.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("instruction is required"),
                    data: None,
                });
            }

            // Parse + normalize instruction from IDL
            let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, instruction_name)
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!(
                        "Unknown instruction in Meteora DLMM IDL: {}",
                        e
                    )),
                    data: Some(json!({
                        "program_id": program_id,
                        "instruction": instruction_name,
                        "hint": "Use solana_idl_list_instructions or solana_idl_plan_instruction to inspect required args/accounts"
                    })),
                })?;

            // Build args pairs from request.args (object)
            let args_obj = request.args.as_object().ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("args must be an object"),
                data: Some(json!({"provided": request.args})),
            })?;

            let mut args_pairs: Vec<(crate::utils::solana_idl::IdlArg, Value)> = Vec::new();
            for a in ix.args.iter() {
                let v = args_obj.get(&a.name).cloned().ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Missing arg: {}", a.name)),
                    data: Some(json!({
                        "missing": a.name,
                        "note": "Args must match IDL exactly. Consider calling solana_idl_plan_instruction for a template."
                    })),
                })?;
                args_pairs.push((a.clone(), v));
            }

            let data =
                crate::utils::solana_idl::encode_anchor_ix_data(&idl, &ix.name, &args_pairs)?;

            // Accounts: object mapping name -> pubkey
            let accounts_obj = request.accounts.as_object().ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("accounts must be an object"),
                data: Some(json!({"provided": request.accounts})),
            })?;

            let mut metas: Vec<solana_sdk::instruction::AccountMeta> = Vec::new();
            for acc in ix.accounts.iter() {
                let pk_s = accounts_obj
                    .get(&acc.name)
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(format!(
                            "Missing account pubkey for: {}",
                            acc.name
                        )),
                        data: Some(json!({
                            "missing": acc.name,
                            "note": "Provide accounts as an object mapping IDL account name -> pubkey (base58)."
                        })),
                    })?;
                let pk = Self::solana_parse_pubkey(pk_s.trim(), &format!("account {}", acc.name))?;
                metas.push(if acc.is_mut {
                    solana_sdk::instruction::AccountMeta::new(pk, acc.is_signer)
                } else {
                    solana_sdk::instruction::AccountMeta::new_readonly(pk, acc.is_signer)
                });
            }

            // Build transaction (optionally signed)
            let sign = request.sign.unwrap_or(true);
            let kp_path = if sign {
                Some(Self::solana_keypair_path()?)
            } else {
                None
            };
            let kp = if sign {
                Some(Self::solana_read_keypair_from_json_file(
                    kp_path.as_ref().unwrap(),
                )?)
            } else {
                None
            };

            let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
                Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
            } else if let Some(ref k) = kp {
                solana_sdk::signature::Signer::pubkey(k)
            } else {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(
                        "fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set",
                    ),
                    data: None,
                });
            };

            let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
                solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                    data: None,
                })?
            } else {
                client
                    .get_latest_blockhash()
                    .await
                    .map_err(|e| Self::sdk_error("solana_meteora_dlmm_build_tx", e))?
            };

            let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();

            if let Some(limit) = request.compute_unit_limit {
                ixs.push(
                    solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                        limit,
                    ),
                );
            }
            if let Some(price) = request.compute_unit_price_micro_lamports {
                ixs.push(
                    solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                        price,
                    ),
                );
            }

            ixs.push(solana_sdk::instruction::Instruction {
                program_id: Self::solana_parse_program_id(program_id)?,
                accounts: metas.clone(),
                data,
            });

            let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));
            let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
            tx.message.recent_blockhash = recent_blockhash;

            if let Some(ref k) = kp {
                tx.sign(&[k], recent_blockhash);
            }

            let tx_bytes = bincode::serialize(&tx)
                .map_err(|e| Self::sdk_error("solana_meteora_dlmm_build_tx", e))?;
            let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let mut out = json!({
                "ok": true,
                "status": "built",
                "network": network_str,
                "rpc_url": rpc_url,
                "program_id": program_id,
                "instruction": ix.name,
                "tx_summary_hash": hash,
                "transaction_base64": tx_base64,
                "note": if sign { "Transaction is signed (SOLANA_KEYPAIR_PATH)." } else { "Transaction is unsigned. You must sign it before broadcasting." }
            });

            if request.create_pending.unwrap_or(true) {
                let created = crate::utils::solana_confirm_store::now_ms();
                let ttl = request
                    .confirm_ttl_ms
                    .unwrap_or(10 * 60 * 1000)
                    .min(15 * 60 * 1000);
                let expires = created + ttl;

                let id_seed = format!("{}:{}", created, hash);
                let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
                let confirmation_id = format!("solana_meteora_dlmm_{}", &id_suffix[..16]);

                let summary = json!({
                    "tool": "solana_meteora_dlmm_build_tx",
                    "program_id": program_id,
                    "instruction": ix.name,
                    "accounts": ix.accounts.iter().map(|a| json!({
                        "name": a.name,
                        "is_signer": a.is_signer,
                        "is_writable": a.is_mut,
                        "pubkey": accounts_obj.get(&a.name).and_then(|v| v.as_str())
                    })).collect::<Vec<Value>>(),
                    "args": args_obj,
                    "tx_bytes_len": tx_bytes.len(),
                    "note": "Pending confirmation created. Use solana_confirm_transaction to broadcast. Mainnet requires confirm_token."
                });

                crate::utils::solana_confirm_store::insert_pending(
                    &confirmation_id,
                    &tx_base64,
                    created,
                    expires,
                    &hash,
                    "solana_meteora_dlmm_build_tx",
                    Some(summary.clone()),
                )?;

                let confirm = json!({
                    "tool": "solana_confirm_transaction",
                    "args": {
                        "id": confirmation_id,
                        "hash": hash,
                        "network": network_str
                    }
                });

                out["status"] = Value::String("pending".to_string());
                out["pending_confirmation_id"] = Value::String(confirmation_id.clone());
                out["expires_in_ms"] = Value::Number(ttl.into());
                out["confirm"] = confirm;
            }

            let response = Self::pretty_json(&out)?;
            Ok(CallToolResult::success(vec![Content::text(response)]))
        }
    }

    fn meteora_first_number(v: &Value, keys: &[&str]) -> Option<(f64, String)> {
        let obj = v.as_object()?;
        for k in keys {
            if let Some(val) = obj.get(*k) {
                // Some APIs return numeric-as-string
                if let Some(n) = val.as_f64() {
                    return Some((n, (*k).to_string()));
                }
                if let Some(s) = val.as_str() {
                    if let Ok(n) = s.trim().parse::<f64>() {
                        return Some((n, (*k).to_string()));
                    }
                }
            }
        }
        None
    }

    fn meteora_first_string(v: &Value, keys: &[&str]) -> Option<(String, String)> {
        let obj = v.as_object()?;
        for k in keys {
            if let Some(val) = obj.get(*k) {
                if let Some(s) = val.as_str() {
                    let ss = s.trim();
                    if !ss.is_empty() {
                        return Some((ss.to_string(), (*k).to_string()));
                    }
                }
            }
        }
        None
    }

    fn meteora_pair_has_mints(pair: &Value, mints: &[&str]) -> bool {
        let obj = match pair.as_object() {
            Some(o) => o,
            None => return false,
        };
        let mut found = 0;
        for key in [
            "mint_x",
            "mint_y",
            "mintX",
            "mintY",
            "tokenXMint",
            "tokenYMint",
            "token_x_mint",
            "token_y_mint",
        ] {
            if let Some(v) = obj.get(key).and_then(|v| v.as_str()) {
                let vv = v.trim();
                if mints.iter().any(|m| m.eq_ignore_ascii_case(vv)) {
                    found += 1;
                }
            }
        }
        found >= 2
    }

    #[tool(description = "Meteora DLMM API: rank DLMM pairs by recent fees (adaptive fields). Outputs a top-N list and simple risk tags.")]
    async fn solana_meteora_dlmm_rank_pairs(
        &self,
        Parameters(request): Parameters<SolanaMeteoraDlmmRankPairsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let base_url = request
            .base_url
            .unwrap_or_else(Self::solana_meteora_dlmm_api_base_url);
        let url = format!("{}/pair/all", base_url.trim_end_matches('/'));

        let timeout_ms = request.timeout_ms.unwrap_or(15_000);
        let (status, parsed) = Self::solana_http_get_json(&url, timeout_ms).await?;
        if !status.is_success() {
            return Err(ErrorData {
                code: ErrorCode(i32::from(status.as_u16())),
                message: Cow::from("HTTP error from Meteora DLMM API"),
                data: Some(json!({"url": url, "status": status.as_u16(), "body": parsed})),
            });
        }

        let pairs = parsed.as_array().ok_or_else(|| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from("Unexpected response: expected JSON array from /pair/all"),
            data: Some(json!({"url": url, "body": parsed})),
        })?;

        let filter = request.filter.as_deref().unwrap_or("all").trim().to_lowercase();
        let limit = request.limit.unwrap_or(20).min(200);

        // Mainnet canonical mints
        // wSOL: So11111111111111111111111111111111111111112
        // USDC: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
        let wsol = "So11111111111111111111111111111111111111112";
        let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";

        let mut items: Vec<Value> = Vec::new();

        // Try to adaptively find these fields across versions.
        let fee_keys = ["fee24h", "fees24h", "fees_24h", "fee_24h", "fee_24_hours", "fees_24_hours"];
        let volume_keys = ["volume24h", "volume_24h", "volume_24_hours", "volume24H"];
        let tvl_keys = ["tvl", "liquidity", "liquidity_usd", "tvl_usd", "tvlUsd", "liquidityUsd"];
        let trades_keys = ["trade24h", "trades24h", "trades_24h", "txn24h", "txns24h", "txCount24h"];

        let addr_keys = [
            "address",
            "pair_address",
            "pairAddress",
            "lbPair",
            "poolAddress",
            "pool_address",
        ];
        let mintx_keys = ["mint_x", "mintX", "tokenXMint", "token_x_mint"];
        let minty_keys = ["mint_y", "mintY", "tokenYMint", "token_y_mint"];

        // Diagnostics (first observed key names)
        let mut diag_fee: Option<String> = None;
        let mut diag_volume: Option<String> = None;
        let mut diag_tvl: Option<String> = None;
        let mut diag_trades: Option<String> = None;
        let mut diag_addr: Option<String> = None;
        let mut diag_mintx: Option<String> = None;
        let mut diag_minty: Option<String> = None;

        for p in pairs.iter() {
            if filter == "sol_usdc" && !Self::meteora_pair_has_mints(p, &[wsol, usdc]) {
                continue;
            }

            let (pair_address, addr_key) = match Self::meteora_first_string(p, &addr_keys) {
                Some((s, k)) => (s, k),
                None => (String::new(), String::new()),
            };

            let (mint_x, mx_key) = match Self::meteora_first_string(p, &mintx_keys) {
                Some((s, k)) => (Some(s), Some(k)),
                None => (None, None),
            };
            let (mint_y, my_key) = match Self::meteora_first_string(p, &minty_keys) {
                Some((s, k)) => (Some(s), Some(k)),
                None => (None, None),
            };

            let fee = Self::meteora_first_number(p, &fee_keys);
            let volume = Self::meteora_first_number(p, &volume_keys);
            let tvl = Self::meteora_first_number(p, &tvl_keys);
            let trades = Self::meteora_first_number(p, &trades_keys);

            if diag_addr.is_none() && !addr_key.is_empty() {
                diag_addr = Some(addr_key);
            }
            if diag_mintx.is_none() {
                if let Some(k) = mx_key.clone() {
                    diag_mintx = Some(k);
                }
            }
            if diag_minty.is_none() {
                if let Some(k) = my_key.clone() {
                    diag_minty = Some(k);
                }
            }
            if diag_fee.is_none() {
                if let Some((_, k)) = fee.as_ref() {
                    diag_fee = Some(k.clone());
                }
            }
            if diag_volume.is_none() {
                if let Some((_, k)) = volume.as_ref() {
                    diag_volume = Some(k.clone());
                }
            }
            if diag_tvl.is_none() {
                if let Some((_, k)) = tvl.as_ref() {
                    diag_tvl = Some(k.clone());
                }
            }
            if diag_trades.is_none() {
                if let Some((_, k)) = trades.as_ref() {
                    diag_trades = Some(k.clone());
                }
            }

            let fee_v = fee.as_ref().map(|(n, _)| *n);
            let volume_v = volume.as_ref().map(|(n, _)| *n);
            let tvl_v = tvl.as_ref().map(|(n, _)| *n);
            let trades_v = trades.as_ref().map(|(n, _)| *n);

            // Ranking score: prefer fee24h; fall back to volume, then trades, then tvl.
            let score = fee_v
                .or(volume_v)
                .or(trades_v)
                .or(tvl_v)
                .unwrap_or(0.0);

            // Risk tags (very heuristic)
            let mut tags: Vec<String> = Vec::new();
            if let (Some(fee24), Some(tvl_usd)) = (fee_v, tvl_v) {
                if tvl_usd > 0.0 && fee24 / tvl_usd > 0.05 {
                    tags.push("high_fee_vs_tvl".to_string());
                }
                if tvl_usd < 50_000.0 && fee24 > 1_000.0 {
                    tags.push("low_tvl".to_string());
                }
            }
            if let (Some(fee24), Some(vol24)) = (fee_v, volume_v) {
                if vol24 > 0.0 && fee24 / vol24 > 0.01 {
                    tags.push("high_fee_rate".to_string());
                }
            }
            if tvl_v.unwrap_or(0.0) < 20_000.0 {
                tags.push("very_low_liquidity".to_string());
            }

            items.push(json!({
                "pair_address": if pair_address.is_empty() { Value::Null } else { Value::String(pair_address) },
                "mint_x": mint_x,
                "mint_y": mint_y,
                "fee_24h": fee_v,
                "volume_24h": volume_v,
                "tvl": tvl_v,
                "trades_24h": trades_v,
                "score": score,
                "risk_tags": tags,
            }));
        }

        items.sort_by(|a, b| {
            let sa = a.get("score").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let sb = b.get("score").and_then(|v| v.as_f64()).unwrap_or(0.0);
            sb.partial_cmp(&sa).unwrap_or(std::cmp::Ordering::Equal)
        });
        items.truncate(limit);

        let include_diag = request.include_field_diagnostics.unwrap_or(true);
        let out = if include_diag {
            json!({
                "base_url": base_url,
                "filter": filter,
                "limit": limit,
                "source": {"url": url, "count": pairs.len()},
                "field_diagnostics": {
                    "pair_address": diag_addr,
                    "mint_x": diag_mintx,
                    "mint_y": diag_minty,
                    "fee_24h": diag_fee,
                    "volume_24h": diag_volume,
                    "tvl": diag_tvl,
                    "trades_24h": diag_trades
                },
                "pairs": items
            })
        } else {
            json!({
                "base_url": base_url,
                "filter": filter,
                "limit": limit,
                "pairs": items
            })
        };

        let response = Self::pretty_json(&out)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // ---------------- Solana common RPC tools ----------------

    #[tool(description = "Solana: raw JSON-RPC call (method+params). Useful to avoid tool explosion in Claude Desktop.")]
    async fn solana_rpc_call(
        &self,
        Parameters(request): Parameters<SolanaRpcCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref().unwrap_or("mainnet");
        let rpc_url = Self::solana_rpc_url_for_network(Some(network))?;

        let method = request.method.trim();
        if method.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("method is required"),
                data: None,
            });
        }

        let id = request.id.unwrap_or(1);

        // By default, JSON-RPC params should be an array. However, we accept an object and pass it
        // through as-is to support edge cases / future methods.
        //
        // UX: LLMs sometimes send params as a JSON-encoded string (e.g. "[\"abc\"]").
        // If so, we try to parse it into real JSON.
        let mut params = request
            .params
            .unwrap_or_else(|| Value::Array(Vec::new()));
        if let Value::String(s) = &params {
            let ss = s.trim();
            if (ss.starts_with('[') && ss.ends_with(']')) || (ss.starts_with('{') && ss.ends_with('}')) {
                params = serde_json::from_str(ss).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("params looks like JSON but failed to parse: {}", e)),
                    data: Some(json!({"params_raw": s})),
                })?;
            }
        }

        let body = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });

        let resp = reqwest::Client::new()
            .post(&rpc_url)
            .json(&body)
            .send()
            .await
            .map_err(|e| Self::sdk_error("solana_rpc_call", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| Self::sdk_error("solana_rpc_call", e))?;

        let parsed: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({ "raw": text }));

        // Turn JSON-RPC error into a tool error by default, so the LLM doesn't have to pattern-match
        // on {error:{...}}.
        let fail_on_rpc_error = request.fail_on_rpc_error.unwrap_or(true);
        if fail_on_rpc_error {
            if let Some(err) = parsed.get("error") {
                let code = err
                    .get("code")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(-32000);
                let message = err
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Solana JSON-RPC error")
                    .to_string();
                let data = err.get("data").cloned();

                let code_i32: i32 = code
                    .try_into()
                    .unwrap_or(-32000);

                return Err(ErrorData {
                    code: ErrorCode(code_i32),
                    message: Cow::from(message),
                    data,
                });
            }
        }

        if !status.is_success() {
            let status_code: i32 = i32::from(status.as_u16());
            return Err(ErrorData {
                code: ErrorCode(status_code),
                message: Cow::from("HTTP error from Solana RPC"),
                data: Some(json!({ "rpc_url": rpc_url, "status": status.as_u16(), "body": parsed })),
            });
        }

        // Default to returning only `result` to reduce token usage / clutter in LLM clients.
        let result_only = request.result_only.unwrap_or(true);

        // Base value to return.
        let mut v = if result_only {
            // Prefer returning response.result; if missing, return the whole parsed response.
            parsed
                .get("result")
                .cloned()
                .unwrap_or(parsed.clone())
        } else {
            json!({
                "rpc_url": rpc_url,
                "network": network,
                "method": method,
                "id": id,
                "status": status.as_u16(),
                "response": parsed
            })
        };

        // Optional extraction via JSON Pointer.
        if let Some(ptr) = request.result_path.as_deref() {
            let ptr = ptr.trim();
            if !ptr.is_empty() {
                if let Some(extracted) = v.pointer(ptr).cloned() {
                    v = extracted;
                } else {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from("result_path not found in response"),
                        data: Some(json!({ "result_path": ptr })),
                    });
                }
            }
        }

        let output = Self::pretty_json(&v)?;
        Ok(CallToolResult::success(vec![Content::text(output)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get balance (lamports) for an address"))]
    async fn solana_get_balance(
        &self,
        Parameters(request): Parameters<SolanaGetBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let addr = Self::solana_parse_pubkey(request.address.trim(), "address")?;
        let client = Self::solana_rpc(request.network.as_deref())?;
        let lamports = client
            .get_balance(&addr)
            .await
            .map_err(|e| Self::sdk_error("solana_get_balance", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "address": addr.to_string(),
            "lamports": lamports
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get account info (optionally with encoding)"))]
    async fn solana_get_account_info(
        &self,
        Parameters(request): Parameters<SolanaGetAccountInfoRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let addr = Self::solana_parse_pubkey(request.address.trim(), "address")?;
        let client = Self::solana_rpc(request.network.as_deref())?;

        let encoding = request.encoding.as_deref().unwrap_or("base64").to_lowercase();
        let enc = match encoding.as_str() {
            "base64" => solana_rpc_client_api::response::UiAccountEncoding::Base64,
            "base64+zstd" | "base64zstd" => solana_rpc_client_api::response::UiAccountEncoding::Base64Zstd,
            "jsonparsed" | "json_parsed" => solana_rpc_client_api::response::UiAccountEncoding::JsonParsed,
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("encoding must be one of: base64|base64+zstd|jsonParsed"),
                    data: Some(json!({ "provided": encoding })),
                })
            }
        };

        let cfg = solana_client::rpc_config::RpcAccountInfoConfig {
            encoding: Some(enc),
            commitment: Some(solana_commitment_config::CommitmentConfig::confirmed()),
            ..Default::default()
        };

        let res = client
            .get_ui_account_with_config(&addr, cfg)
            .await
            .map_err(|e| Self::sdk_error("solana_get_account_info", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "address": addr.to_string(),
            "context": res.context,
            "value": res.value
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get latest blockhash"))]
    async fn solana_get_latest_blockhash(
        &self,
        Parameters(request): Parameters<SolanaGetLatestBlockhashRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;

        let res = client
            .get_latest_blockhash_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_latest_blockhash", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "commitment": request.commitment.unwrap_or("confirmed".to_string()),
            "blockhash": res.0.to_string(),
            "last_valid_block_height": res.1
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get signature status"))]
    async fn solana_get_signature_status(
        &self,
        Parameters(request): Parameters<SolanaGetSignatureStatusRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let sig = solana_sdk::signature::Signature::from_str(request.signature.trim()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid signature: {}", e)),
            data: None,
        })?;

        let search_history = request.search_transaction_history.unwrap_or(false);
        let res = if search_history {
            client
                .get_signature_statuses_with_history(&[sig])
                .await
                .map_err(|e| Self::sdk_error("solana_get_signature_status", e))?
        } else {
            client
                .get_signature_statuses(&[sig])
                .await
                .map_err(|e| Self::sdk_error("solana_get_signature_status", e))?
        };

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "signature": sig.to_string(),
            "search_transaction_history": search_history,
            "context": res.context,
            "value": res.value.get(0).cloned().unwrap_or(None)
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get transaction by signature"))]
    async fn solana_get_transaction(
        &self,
        Parameters(request): Parameters<SolanaGetTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let sig = solana_sdk::signature::Signature::from_str(request.signature.trim()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid signature: {}", e)),
            data: None,
        })?;

        let encoding = request.encoding.as_deref().unwrap_or("json").to_lowercase();
        let enc = match encoding.as_str() {
            "json" => solana_transaction_status::UiTransactionEncoding::Json,
            "jsonparsed" | "json_parsed" => solana_transaction_status::UiTransactionEncoding::JsonParsed,
            "base64" => solana_transaction_status::UiTransactionEncoding::Base64,
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("encoding must be one of: json|jsonParsed|base64"),
                    data: Some(json!({ "provided": encoding })),
                })
            }
        };

        let cfg = solana_client::rpc_config::RpcTransactionConfig {
            encoding: Some(enc),
            commitment: Some(solana_commitment_config::CommitmentConfig::confirmed()),
            max_supported_transaction_version: Some(request.max_supported_transaction_version.unwrap_or(0)),
        };

        let tx = client
            .get_transaction_with_config(&sig, cfg)
            .await
            .map_err(|e| Self::sdk_error("solana_get_transaction", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "signature": sig.to_string(),
            "transaction": tx
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get current slot"))]
    async fn solana_get_slot(
        &self,
        Parameters(request): Parameters<SolanaGetSlotRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;
        let slot = client
            .get_slot_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_slot", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "commitment": request.commitment.unwrap_or("confirmed".to_string()),
            "slot": slot
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get current block height"))]
    async fn solana_get_block_height(
        &self,
        Parameters(request): Parameters<SolanaGetBlockHeightRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let commitment = Self::solana_commitment_from_str(request.commitment.as_deref())?;
        let height = client
            .get_block_height_with_commitment(commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_block_height", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "commitment": request.commitment.unwrap_or("confirmed".to_string()),
            "block_height": height
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: request airdrop (devnet/testnet only)"))]
    async fn solana_request_airdrop(
        &self,
        Parameters(request): Parameters<SolanaRequestAirdropRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let net = request.network.as_deref().unwrap_or("devnet").trim().to_lowercase();
        if net == "mainnet" || net == "mainnet-beta" || net == "mainnet_beta" {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("airdrop is only supported on devnet/testnet"),
                data: Some(json!({"network": net})),
            });
        }

        let client = Self::solana_rpc(Some(&net))?;
        let addr = Self::solana_parse_pubkey(request.address.trim(), "address")?;
        let sig = client
            .request_airdrop(&addr, request.lamports)
            .await
            .map_err(|e| Self::sdk_error("solana_request_airdrop", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(Some(&net))?,
            "network": net,
            "address": addr.to_string(),
            "lamports": request.lamports,
            "signature": sig.to_string(),
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: list SPL token accounts for an owner (optionally filter by mint)"))]
    async fn solana_get_token_accounts(
        &self,
        Parameters(request): Parameters<SolanaGetTokenAccountsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;

        // Note: solana-client currently fixes encoding=jsonParsed for get_token_accounts_by_owner_with_commitment.
        // We accept encoding param for API compatibility, but only support jsonParsed here.
        let encoding = request.encoding.as_deref().unwrap_or("jsonParsed").to_lowercase();
        if !(encoding == "jsonparsed" || encoding == "json_parsed") {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("encoding must be jsonParsed for this tool"),
                data: Some(json!({ "provided": encoding })),
            });
        }

        let filter = if let Some(m) = request.mint.as_deref() {
            let mint = Self::solana_parse_pubkey(m.trim(), "mint")?;
            solana_client::rpc_request::TokenAccountsFilter::Mint(mint)
        } else {
            solana_client::rpc_request::TokenAccountsFilter::ProgramId(
                solana_sdk::pubkey::Pubkey::from_str("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap(),
            )
        };

        let commitment = solana_commitment_config::CommitmentConfig::confirmed();
        let res = client
            .get_token_accounts_by_owner_with_commitment(&owner, filter, commitment)
            .await
            .map_err(|e| Self::sdk_error("solana_get_token_accounts", e))?;

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "owner": owner.to_string(),
            "mint": request.mint,
            "encoding": "jsonParsed",
            "context": res.context,
            "value": res.value
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: get SPL token balance for owner+mint (aggregates all token accounts)"))]
    async fn solana_get_token_balance(
        &self,
        Parameters(request): Parameters<SolanaGetTokenBalanceRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let client = Self::solana_rpc(request.network.as_deref())?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;

        let commitment = solana_commitment_config::CommitmentConfig::confirmed();
        let res = client
            .get_token_accounts_by_owner_with_commitment(
                &owner,
                solana_client::rpc_request::TokenAccountsFilter::Mint(mint),
                commitment,
            )
            .await
            .map_err(|e| Self::sdk_error("solana_get_token_balance", e))?;

        // Best-effort parse jsonParsed layout: value[i].account.data.parsed.info.tokenAmount
        let mut total_raw: u128 = 0;
        let mut decimals: Option<u8> = None;
        let mut accounts: Vec<Value> = Vec::new();

        for keyed in &res.value {
            let v = serde_json::to_value(keyed).unwrap_or(Value::Null);
            // Extract tokenAmount fields
            let ta = v
                .pointer("/account/data/parsed/info/tokenAmount")
                .cloned()
                .unwrap_or(Value::Null);
            let amount_raw = ta
                .get("amount")
                .and_then(|x| x.as_str())
                .and_then(|s| s.parse::<u128>().ok())
                .unwrap_or(0);
            let dec = ta.get("decimals").and_then(|x| x.as_u64()).map(|d| d as u8);
            if decimals.is_none() {
                decimals = dec;
            }
            total_raw = total_raw.saturating_add(amount_raw);
            accounts.push(v);
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url_for_network(request.network.as_deref())?,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "owner": owner.to_string(),
            "mint": mint.to_string(),
            "encoding": "jsonParsed",
            "decimals": decimals,
            "total_amount_raw": total_raw.to_string(),
            "token_accounts_count": accounts.len(),
            "token_accounts": accounts
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: one-step token transfer (build tx; safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_transfer(
        &self,
        Parameters(request): Parameters<SolanaSplTransferRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;
        let client = Self::solana_rpc(network)?;

        // For spl_token::state::Mint::unpack
        use solana_program_pack::Pack as _;

        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let recipient = Self::solana_parse_pubkey(request.recipient.trim(), "recipient")?;

        let amount: u64 = request.amount_raw.trim().parse().map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("amount_raw must be a u64 integer string"),
            data: Some(json!({"provided": request.amount_raw})),
        })?;

        let token_program_id = spl_token::id();

        let source_token_account = if let Some(s) = request.source_token_account.as_deref() {
            Self::solana_parse_pubkey(s.trim(), "source_token_account")?
        } else {
            spl_associated_token_account::get_associated_token_address(&owner, &mint)
        };

        let destination_token_account = if let Some(s) = request.destination_token_account.as_deref() {
            Self::solana_parse_pubkey(s.trim(), "destination_token_account")?
        } else {
            spl_associated_token_account::get_associated_token_address(&recipient, &mint)
        };

        let create_ata_if_missing = request.create_ata_if_missing.unwrap_or(false);

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set",
                ),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_spl_transfer", e))?
        };

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();

        // Optional ComputeBudget (prepend)
        if let Some(limit) = request.compute_unit_limit {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                    limit,
                ),
            );
        }
        if let Some(price) = request.compute_unit_price_micro_lamports {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                    price,
                ),
            );
        }

        // Optional create destination ATA if missing
        if create_ata_if_missing {
            let exists = client.get_account(&destination_token_account).await.is_ok();
            if !exists {
                ixs.push(
                    spl_associated_token_account::instruction::create_associated_token_account(
                        &fee_payer,
                        &recipient,
                        &mint,
                        &token_program_id,
                    ),
                );
            }
        }

        // Source ATA should already exist; do not auto-create by default.
        if client.get_account(&source_token_account).await.is_err() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("source_token_account does not exist"),
                data: Some(json!({
                    "source_token_account": source_token_account.to_string(),
                    "owner": owner.to_string(),
                    "mint": mint.to_string(),
                    "hint": "Provide source_token_account explicitly, or create/fund the owner's ATA first."
                })),
            });
        }

        let use_checked = request.use_transfer_checked.unwrap_or(true);
        let (transfer_ix, decimals_used): (solana_sdk::instruction::Instruction, Option<u8>) = if use_checked {
            // Fetch mint decimals and use transfer_checked for safety.
            let mint_acc = client
                .get_account(&mint)
                .await
                .map_err(|e| Self::sdk_error("solana_spl_transfer", e))?;
            let mint_state = spl_token::state::Mint::unpack(&mint_acc.data).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode mint account: {}", e)),
                data: Some(json!({"mint": mint.to_string()})),
            })?;
            let dec = mint_state.decimals;
            (
                spl_token::instruction::transfer_checked(
                    &token_program_id,
                    &source_token_account,
                    &mint,
                    &destination_token_account,
                    &owner,
                    &[],
                    amount,
                    dec,
                )
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to build token transfer_checked instruction: {}", e)),
                    data: None,
                })?,
                Some(dec),
            )
        } else {
            (
                spl_token::instruction::transfer(
                    &token_program_id,
                    &source_token_account,
                    &destination_token_account,
                    &owner,
                    &[],
                    amount,
                )
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to build token transfer instruction: {}", e)),
                    data: None,
                })?,
                None,
            )
        };

        ixs.push(transfer_ix);

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "mint": mint.to_string(),
                "owner": owner.to_string(),
                "recipient": recipient.to_string(),
                "amount_raw": amount.to_string(),
                "use_transfer_checked": use_checked,
                "mint_decimals": decimals_used,
                "source_token_account": source_token_account.to_string(),
                "destination_token_account": destination_token_account.to_string(),
                "create_ata_if_missing": create_ata_if_missing,
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_spl_transfer",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "rpc_url": rpc_url,
                "network": network_str,
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "transaction": {
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len(),
                    "keypair_path": kp_path
                },
                "expires_in_ms": ttl,
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        // confirm=true: broadcast now
        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        // If tx isn't signed, attempt to sign if SOLANA_KEYPAIR_PATH exists.
        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());
        if tx2.signatures.is_empty()
            || tx2
                .signatures
                .iter()
                .all(|s| *s == solana_sdk::signature::Signature::default())
        {
            return Self::guard_result(
                "solana_send_transaction",
                "SIGNED_TX_REQUIRED",
                "confirm=true requires a signed transaction",
                false,
                Some("Set sign=true (and configure SOLANA_KEYPAIR_PATH), or sign externally then call solana_send_transaction again"),
                Some(json!({
                    "tool": "solana_send_transaction",
                    "args": {
                        "network": request.network.clone().unwrap_or("mainnet".to_string()),
                        "transaction_base64": request.transaction_base64.clone(),
                        "confirm": true,
                        "allow_direct_send": true
                    }
                })),
                Some(json!({
                    "safer_default": "Use confirm=false to create a pending confirmation first",
                    "how_to": "solana_send_transaction(confirm=false) -> solana_confirm_transaction(confirm_token)"
                })),
            );
        }

        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_spl_transfer", e))?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "transfer": {
                "mint": mint.to_string(),
                "owner": owner.to_string(),
                "recipient": recipient.to_string(),
                "amount_raw": amount.to_string(),
                "source_token_account": source_token_account.to_string(),
                "destination_token_account": destination_token_account.to_string(),
                "create_ata_if_missing": create_ata_if_missing
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: one-step token transfer using UI amount (decimal string) (safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_transfer_ui_amount(
        &self,
        Parameters(request): Parameters<SolanaSplTransferUiAmountRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // For spl_token::state::Mint::unpack
        use solana_program_pack::Pack as _;

        let network = request.network.as_deref();
        let client = Self::solana_rpc(network)?;
        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;

        let mint_acc = client
            .get_account(&mint)
            .await
            .map_err(|e| Self::sdk_error("solana_spl_transfer_ui_amount", e))?;
        let mint_state = spl_token::state::Mint::unpack(&mint_acc.data).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode mint account: {}", e)),
            data: Some(json!({"mint": mint.to_string()})),
        })?;
        let decimals = mint_state.decimals;

        fn ui_to_raw(amount: &str, decimals: u8) -> Result<u64, ErrorData> {
            let s = amount.trim();
            if s.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount is required"),
                    data: None,
                });
            }
            if s.starts_with('-') {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount must be non-negative"),
                    data: Some(json!({"provided": s})),
                });
            }
            let parts: Vec<&str> = s.split('.').collect();
            if parts.len() > 2 {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount must be a decimal string"),
                    data: Some(json!({"provided": s})),
                });
            }
            let whole = parts[0];
            let frac = if parts.len() == 2 { parts[1] } else { "" };

            if !whole.chars().all(|c| c.is_ascii_digit()) || !frac.chars().all(|c| c.is_ascii_digit()) {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount must contain only digits and at most one '.'"),
                    data: Some(json!({"provided": s})),
                });
            }

            if frac.len() > decimals as usize {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("too many decimal places for token"),
                    data: Some(json!({"provided": s, "decimals": decimals})),
                });
            }

            let mut frac_padded = frac.to_string();
            while frac_padded.len() < decimals as usize {
                frac_padded.push('0');
            }

            let whole_u128: u128 = if whole.is_empty() { 0 } else { whole.parse().unwrap_or(0) };
            let frac_u128: u128 = if decimals == 0 || frac_padded.is_empty() {
                0
            } else {
                frac_padded.parse().unwrap_or(0)
            };

            let scale: u128 = 10u128.pow(decimals as u32);
            let raw = whole_u128
                .checked_mul(scale)
                .and_then(|x| x.checked_add(frac_u128))
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount overflows"),
                    data: Some(json!({"provided": s})),
                })?;

            u64::try_from(raw).map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("amount overflows u64"),
                data: Some(json!({"provided": s})),
            })
        }

        let amount_raw = ui_to_raw(&request.amount, decimals)?;

        // Reuse solana_spl_transfer implementation.
        let req2 = SolanaSplTransferRequest {
            network: request.network.clone(),
            mint: request.mint,
            owner: request.owner,
            recipient: request.recipient,
            amount_raw: amount_raw.to_string(),
            use_transfer_checked: Some(true),
            source_token_account: request.source_token_account,
            destination_token_account: request.destination_token_account,
            create_ata_if_missing: request.create_ata_if_missing,
            fee_payer: request.fee_payer,
            recent_blockhash: request.recent_blockhash,
            compute_unit_limit: request.compute_unit_limit,
            compute_unit_price_micro_lamports: request.compute_unit_price_micro_lamports,
            sign: request.sign,
            confirm: request.confirm,
            commitment: request.commitment,
            skip_preflight: request.skip_preflight,
            timeout_ms: request.timeout_ms,
        };

        self.solana_spl_transfer(Parameters(req2)).await
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: create an associated token account (ATA) (safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_create_ata(
        &self,
        Parameters(request): Parameters<SolanaSplCreateAtaRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;
        let client = Self::solana_rpc(network)?;

        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;
        let token_program_id = spl_token::id();

        let ata = spl_associated_token_account::get_associated_token_address(&owner, &mint);

        let create_if_missing = request.create_if_missing.unwrap_or(true);
        let exists = client.get_account(&ata).await.is_ok();
        if create_if_missing && exists {
            let response = Self::pretty_json(&json!({
                "status": "exists",
                "rpc_url": rpc_url,
                "network": network_str,
                "owner": owner.to_string(),
                "mint": mint.to_string(),
                "token_program_id": token_program_id.to_string(),
                "associated_token_account": ata.to_string(),
                "note": "ATA already exists; no transaction created."
            }))?;
            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set",
                ),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_spl_create_ata", e))?
        };

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();
        if let Some(limit) = request.compute_unit_limit {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                    limit,
                ),
            );
        }
        if let Some(price) = request.compute_unit_price_micro_lamports {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                    price,
                ),
            );
        }

        ixs.push(
            spl_associated_token_account::instruction::create_associated_token_account(
                &fee_payer,
                &owner,
                &mint,
                &token_program_id,
            ),
        );

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "owner": owner.to_string(),
                "mint": mint.to_string(),
                "token_program_id": token_program_id.to_string(),
                "associated_token_account": ata.to_string(),
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_spl_create_ata",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "rpc_url": rpc_url,
                "network": network_str,
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "transaction": {
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len(),
                    "keypair_path": kp_path
                },
                "expires_in_ms": ttl,
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());
        if tx2.signatures.is_empty()
            || tx2
                .signatures
                .iter()
                .all(|s| *s == solana_sdk::signature::Signature::default())
        {
            return Self::guard_result(
                "solana_send_transaction",
                "SIGNED_TX_REQUIRED",
                "confirm=true requires a signed transaction",
                false,
                Some("Set sign=true (and configure SOLANA_KEYPAIR_PATH), or sign externally then call solana_send_transaction again"),
                Some(json!({
                    "tool": "solana_send_transaction",
                    "args": {
                        "network": request.network.clone().unwrap_or("mainnet".to_string()),
                        "transaction_base64": request.transaction_base64.clone(),
                        "confirm": true,
                        "allow_direct_send": true
                    }
                })),
                Some(json!({
                    "safer_default": "Use confirm=false to create a pending confirmation first",
                    "how_to": "solana_send_transaction(confirm=false) -> solana_confirm_transaction(confirm_token)"
                })),
            );
        }

        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_spl_create_ata", e))?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "associated_token_account": ata.to_string()
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: revoke token delegate (safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_revoke(
        &self,
        Parameters(request): Parameters<SolanaSplRevokeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // For spl_token::state::Account::unpack
        use solana_program_pack::Pack as _;

        let network = request.network.as_deref();
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;
        let client = Self::solana_rpc(network)?;

        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let token_program_id = spl_token::id();

        let token_account = if let Some(s) = request.token_account.as_deref() {
            Self::solana_parse_pubkey(s.trim(), "token_account")?
        } else {
            spl_associated_token_account::get_associated_token_address(&owner, &mint)
        };

        let validate_token_account = request.validate_token_account.unwrap_or(true);
        if validate_token_account {
            let ta_acc = client
                .get_account(&token_account)
                .await
                .map_err(|e| Self::sdk_error("solana_spl_revoke", e))?;
            let ta_state = spl_token::state::Account::unpack(&ta_acc.data).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode token account: {}", e)),
                data: Some(json!({"token_account": token_account.to_string()})),
            })?;
            if ta_state.mint != mint {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token_account mint does not match request.mint"),
                    data: Some(json!({
                        "token_account": token_account.to_string(),
                        "token_account_mint": ta_state.mint.to_string(),
                        "requested_mint": mint.to_string()
                    })),
                });
            }
            if ta_state.owner != owner {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token_account owner does not match request.owner"),
                    data: Some(json!({
                        "token_account": token_account.to_string(),
                        "token_account_owner": ta_state.owner.to_string(),
                        "requested_owner": owner.to_string()
                    })),
                });
            }
        }

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set",
                ),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_spl_revoke", e))?
        };

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();
        if let Some(limit) = request.compute_unit_limit {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                    limit,
                ),
            );
        }
        if let Some(price) = request.compute_unit_price_micro_lamports {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                    price,
                ),
            );
        }

        let revoke_ix = spl_token::instruction::revoke(
            &token_program_id,
            &token_account,
            &owner,
            &[],
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to build token revoke instruction: {}", e)),
            data: None,
        })?;
        ixs.push(revoke_ix);

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "mint": mint.to_string(),
                "owner": owner.to_string(),
                "token_account": token_account.to_string(),
                "validate_token_account": validate_token_account,
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_spl_revoke",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "rpc_url": rpc_url,
                "network": network_str,
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "transaction": {
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len(),
                    "keypair_path": kp_path
                },
                "expires_in_ms": ttl,
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());
        if tx2.signatures.is_empty()
            || tx2
                .signatures
                .iter()
                .all(|s| *s == solana_sdk::signature::Signature::default())
        {
            return Self::guard_result(
                "solana_send_transaction",
                "SIGNED_TX_REQUIRED",
                "confirm=true requires a signed transaction",
                false,
                Some("Set sign=true (and configure SOLANA_KEYPAIR_PATH), or sign externally then call solana_send_transaction again"),
                Some(json!({
                    "tool": "solana_send_transaction",
                    "args": {
                        "network": request.network.clone().unwrap_or("mainnet".to_string()),
                        "transaction_base64": request.transaction_base64.clone(),
                        "confirm": true,
                        "allow_direct_send": true
                    }
                })),
                Some(json!({
                    "safer_default": "Use confirm=false to create a pending confirmation first",
                    "how_to": "solana_send_transaction(confirm=false) -> solana_confirm_transaction(confirm_token)"
                })),
            );
        }

        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_spl_revoke", e))?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "revoke": {
                "mint": mint.to_string(),
                "owner": owner.to_string(),
                "token_account": token_account.to_string(),
                "validate_token_account": validate_token_account
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: close a token account (safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_close_account(
        &self,
        Parameters(request): Parameters<SolanaSplCloseAccountRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // For spl_token::state::Account::unpack
        use solana_program_pack::Pack as _;

        let network = request.network.as_deref();
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;
        let client = Self::solana_rpc(network)?;

        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let token_program_id = spl_token::id();

        let token_account = if let Some(s) = request.token_account.as_deref() {
            Self::solana_parse_pubkey(s.trim(), "token_account")?
        } else {
            spl_associated_token_account::get_associated_token_address(&owner, &mint)
        };

        let destination = if let Some(d) = request.destination.as_deref() {
            Self::solana_parse_pubkey(d.trim(), "destination")?
        } else {
            owner
        };

        let validate_token_account = request.validate_token_account.unwrap_or(true);
        if validate_token_account {
            let ta_acc = client
                .get_account(&token_account)
                .await
                .map_err(|e| Self::sdk_error("solana_spl_close_account", e))?;
            let ta_state = spl_token::state::Account::unpack(&ta_acc.data).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode token account: {}", e)),
                data: Some(json!({"token_account": token_account.to_string()})),
            })?;
            if ta_state.mint != mint {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token_account mint does not match request.mint"),
                    data: Some(json!({
                        "token_account": token_account.to_string(),
                        "token_account_mint": ta_state.mint.to_string(),
                        "requested_mint": mint.to_string()
                    })),
                });
            }
            if ta_state.owner != owner {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token_account owner does not match request.owner"),
                    data: Some(json!({
                        "token_account": token_account.to_string(),
                        "token_account_owner": ta_state.owner.to_string(),
                        "requested_owner": owner.to_string()
                    })),
                });
            }
        }

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set",
                ),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_spl_close_account", e))?
        };

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();
        if let Some(limit) = request.compute_unit_limit {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                    limit,
                ),
            );
        }
        if let Some(price) = request.compute_unit_price_micro_lamports {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                    price,
                ),
            );
        }

        let close_ix = spl_token::instruction::close_account(
            &token_program_id,
            &token_account,
            &destination,
            &owner,
            &[],
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to build token close_account instruction: {}", e)),
            data: None,
        })?;
        ixs.push(close_ix);

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "mint": mint.to_string(),
                "owner": owner.to_string(),
                "token_account": token_account.to_string(),
                "destination": destination.to_string(),
                "validate_token_account": validate_token_account,
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_spl_close_account",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "rpc_url": rpc_url,
                "network": network_str,
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "transaction": {
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len(),
                    "keypair_path": kp_path
                },
                "expires_in_ms": ttl,
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());
        if tx2.signatures.is_empty()
            || tx2
                .signatures
                .iter()
                .all(|s| *s == solana_sdk::signature::Signature::default())
        {
            return Self::guard_result(
                "solana_send_transaction",
                "SIGNED_TX_REQUIRED",
                "confirm=true requires a signed transaction",
                false,
                Some("Set sign=true (and configure SOLANA_KEYPAIR_PATH), or sign externally then call solana_send_transaction again"),
                Some(json!({
                    "tool": "solana_send_transaction",
                    "args": {
                        "network": request.network.clone().unwrap_or("mainnet".to_string()),
                        "transaction_base64": request.transaction_base64.clone(),
                        "confirm": true,
                        "allow_direct_send": true
                    }
                })),
                Some(json!({
                    "safer_default": "Use confirm=false to create a pending confirmation first",
                    "how_to": "solana_send_transaction(confirm=false) -> solana_confirm_transaction(confirm_token)"
                })),
            );
        }

        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_spl_close_account", e))?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "close_account": {
                "mint": mint.to_string(),
                "owner": owner.to_string(),
                "token_account": token_account.to_string(),
                "destination": destination.to_string(),
                "validate_token_account": validate_token_account
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: one-step token approve using UI amount (decimal string) (safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_approve_ui_amount(
        &self,
        Parameters(request): Parameters<SolanaSplApproveUiAmountRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // For spl_token::state::Mint::unpack
        use solana_program_pack::Pack as _;

        let network = request.network.as_deref();
        let client = Self::solana_rpc(network)?;
        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;

        let mint_acc = client
            .get_account(&mint)
            .await
            .map_err(|e| Self::sdk_error("solana_spl_approve_ui_amount", e))?;
        let mint_state = spl_token::state::Mint::unpack(&mint_acc.data).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to decode mint account: {}", e)),
            data: Some(json!({"mint": mint.to_string()})),
        })?;
        let decimals = mint_state.decimals;

        fn ui_to_raw(amount: &str, decimals: u8) -> Result<u64, ErrorData> {
            let s = amount.trim();
            if s.is_empty() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount is required"),
                    data: None,
                });
            }
            if s.starts_with('-') {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount must be non-negative"),
                    data: Some(json!({"provided": s})),
                });
            }
            let parts: Vec<&str> = s.split('.').collect();
            if parts.len() > 2 {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount must be a decimal string"),
                    data: Some(json!({"provided": s})),
                });
            }
            let whole = parts[0];
            let frac = if parts.len() == 2 { parts[1] } else { "" };

            if !whole.chars().all(|c| c.is_ascii_digit()) || !frac.chars().all(|c| c.is_ascii_digit()) {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount must contain only digits and at most one '.'"),
                    data: Some(json!({"provided": s})),
                });
            }

            if frac.len() > decimals as usize {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("too many decimal places for token"),
                    data: Some(json!({"provided": s, "decimals": decimals})),
                });
            }

            let mut frac_padded = frac.to_string();
            while frac_padded.len() < decimals as usize {
                frac_padded.push('0');
            }

            let whole_u128: u128 = if whole.is_empty() { 0 } else { whole.parse().unwrap_or(0) };
            let frac_u128: u128 = if decimals == 0 || frac_padded.is_empty() {
                0
            } else {
                frac_padded.parse().unwrap_or(0)
            };

            let scale: u128 = 10u128.pow(decimals as u32);
            let raw = whole_u128
                .checked_mul(scale)
                .and_then(|x| x.checked_add(frac_u128))
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("amount overflows"),
                    data: Some(json!({"provided": s})),
                })?;

            u64::try_from(raw).map_err(|_| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("amount overflows u64"),
                data: Some(json!({"provided": s})),
            })
        }

        let amount_raw = ui_to_raw(&request.amount, decimals)?;

        let req2 = SolanaSplApproveRequest {
            network: request.network.clone(),
            mint: request.mint,
            owner: request.owner,
            delegate: request.delegate,
            amount_raw: amount_raw.to_string(),
            validate_mint_decimals: request.validate_mint_decimals,
            token_account: request.token_account,
            fee_payer: request.fee_payer,
            recent_blockhash: request.recent_blockhash,
            compute_unit_limit: request.compute_unit_limit,
            compute_unit_price_micro_lamports: request.compute_unit_price_micro_lamports,
            sign: request.sign,
            confirm: request.confirm,
            commitment: request.commitment,
            skip_preflight: request.skip_preflight,
            timeout_ms: request.timeout_ms,
        };

        self.solana_spl_approve(Parameters(req2)).await
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana SPL: one-step token approve (build tx; safe default: creates pending confirmation unless confirm=true)"))]
    async fn solana_spl_approve(
        &self,
        Parameters(request): Parameters<SolanaSplApproveRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;
        let client = Self::solana_rpc(network)?;

        // For spl_token::state::Mint/Account unpack
        use solana_program_pack::Pack as _;

        let mint = Self::solana_parse_pubkey(request.mint.trim(), "mint")?;
        let owner = Self::solana_parse_pubkey(request.owner.trim(), "owner")?;
        let delegate = Self::solana_parse_pubkey(request.delegate.trim(), "delegate")?;

        let amount: u64 = request.amount_raw.trim().parse().map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("amount_raw must be a u64 integer string"),
            data: Some(json!({"provided": request.amount_raw})),
        })?;

        let token_program_id = spl_token::id();

        let token_account = if let Some(s) = request.token_account.as_deref() {
            Self::solana_parse_pubkey(s.trim(), "token_account")?
        } else {
            spl_associated_token_account::get_associated_token_address(&owner, &mint)
        };

        let validate_mint_decimals = request.validate_mint_decimals.unwrap_or(true);
        let mut mint_decimals: Option<u8> = None;
        if validate_mint_decimals {
            // Validate mint account can be decoded, and token_account matches (mint, owner).
            let mint_acc = client
                .get_account(&mint)
                .await
                .map_err(|e| Self::sdk_error("solana_spl_approve", e))?;
            let mint_state = spl_token::state::Mint::unpack(&mint_acc.data).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode mint account: {}", e)),
                data: Some(json!({"mint": mint.to_string()})),
            })?;
            mint_decimals = Some(mint_state.decimals);

            let ta_acc = client
                .get_account(&token_account)
                .await
                .map_err(|e| Self::sdk_error("solana_spl_approve", e))?;
            let ta_state = spl_token::state::Account::unpack(&ta_acc.data).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to decode token account: {}", e)),
                data: Some(json!({"token_account": token_account.to_string()})),
            })?;

            if ta_state.mint != mint {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token_account mint does not match request.mint"),
                    data: Some(json!({
                        "token_account": token_account.to_string(),
                        "token_account_mint": ta_state.mint.to_string(),
                        "requested_mint": mint.to_string()
                    })),
                });
            }
            if ta_state.owner != owner {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("token_account owner does not match request.owner"),
                    data: Some(json!({
                        "token_account": token_account.to_string(),
                        "token_account_owner": ta_state.owner.to_string(),
                        "requested_owner": owner.to_string()
                    })),
                });
            }
        }

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(
                    "fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set",
                ),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_spl_approve", e))?
        };

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();
        if let Some(limit) = request.compute_unit_limit {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                    limit,
                ),
            );
        }
        if let Some(price) = request.compute_unit_price_micro_lamports {
            ixs.push(
                solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                    price,
                ),
            );
        }

        let approve_ix = spl_token::instruction::approve(
            &token_program_id,
            &token_account,
            &delegate,
            &owner,
            &[],
            amount,
        )
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to build token approve instruction: {}", e)),
            data: None,
        })?;
        ixs.push(approve_ix);

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "mint": mint.to_string(),
                "mint_decimals": mint_decimals,
                "validate_mint_decimals": validate_mint_decimals,
                "owner": owner.to_string(),
                "delegate": delegate.to_string(),
                "amount_raw": amount.to_string(),
                "token_account": token_account.to_string(),
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_spl_approve",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "status": "pending",
                "rpc_url": rpc_url,
                "network": network_str,
                "confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "transaction": {
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len(),
                    "keypair_path": kp_path
                },
                "expires_in_ms": ttl,
                "next": {
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());
        if tx2.signatures.is_empty()
            || tx2
                .signatures
                .iter()
                .all(|s| *s == solana_sdk::signature::Signature::default())
        {
            return Self::guard_result(
                "solana_send_transaction",
                "SIGNED_TX_REQUIRED",
                "confirm=true requires a signed transaction",
                false,
                Some("Set sign=true (and configure SOLANA_KEYPAIR_PATH), or sign externally then call solana_send_transaction again"),
                Some(json!({
                    "tool": "solana_send_transaction",
                    "args": {
                        "network": request.network.clone().unwrap_or("mainnet".to_string()),
                        "transaction_base64": request.transaction_base64.clone(),
                        "confirm": true,
                        "allow_direct_send": true
                    }
                })),
                Some(json!({
                    "safer_default": "Use confirm=false to create a pending confirmation first",
                    "how_to": "solana_send_transaction(confirm=false) -> solana_confirm_transaction(confirm_token)"
                })),
            );
        }

        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_spl_approve", e))?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms).await?;

        let response = Self::pretty_json(&json!({
            "status": "sent",
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "approve": {
                "mint": mint.to_string(),
                "mint_decimals": mint_decimals,
                "validate_mint_decimals": validate_mint_decimals,
                "owner": owner.to_string(),
                "delegate": delegate.to_string(),
                "amount_raw": amount.to_string(),
                "token_account": token_account.to_string()
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    async fn solana_wait_for_signature(
        client: &solana_client::nonblocking::rpc_client::RpcClient,
        sig: &solana_sdk::signature::Signature,
        commitment: &str,
        timeout_ms: u64,
    ) -> Result<serde_json::Value, ErrorData> {
        use solana_transaction_status::TransactionConfirmationStatus as Tcs;

        let want = commitment.trim().to_lowercase();
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_ms);

        loop {
            let res = client
                .get_signature_statuses(&[*sig])
                .await
                .map_err(|e| Self::sdk_error("solana_wait_for_signature", e))?;

            let st = res.value.get(0).cloned().unwrap_or(None);
            if let Some(s) = st {
                if let Some(err) = s.err {
                    return Err(ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from("Transaction failed"),
                        data: Some(json!({"signature": sig.to_string(), "err": err})),
                    });
                }

                let level_ok = match want.as_str() {
                    "processed" => true,
                    "confirmed" => matches!(s.confirmation_status, Some(Tcs::Confirmed | Tcs::Finalized)),
                    "finalized" => matches!(s.confirmation_status, Some(Tcs::Finalized)),
                    _ => true,
                };

                if level_ok {
                    return Ok(json!({
                        "signature": sig.to_string(),
                        "confirmation_status": s.confirmation_status,
                        "confirmations": s.confirmations,
                        "slot": s.slot,
                        "status": "ok"
                    }));
                }
            }

            if std::time::Instant::now() >= deadline {
                return Ok(json!({
                    "signature": sig.to_string(),
                    "status": "timeout"
                }));
            }

            tokio::time::sleep(std::time::Duration::from_millis(800)).await;
        }
    }

    fn solana_try_sign_if_needed(
        tx: &mut solana_sdk::transaction::Transaction,
        kp: Option<&solana_sdk::signature::Keypair>,
    ) {
        if let Some(k) = kp {
            // If signatures are missing or default, attempt to sign.
            let all_default = tx
                .signatures
                .iter()
                .all(|s| *s == solana_sdk::signature::Signature::default());
            if tx.signatures.is_empty() || all_default {
                let bh = tx.message.recent_blockhash;
                tx.sign(&[k], bh);
            }
        }
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_ui_account_encoding_from_str(
        encoding: &str,
    ) -> Result<solana_rpc_client_api::response::UiAccountEncoding, ErrorData> {
        let e = encoding.trim().to_lowercase();
        let enc = match e.as_str() {
            "base64" => solana_rpc_client_api::response::UiAccountEncoding::Base64,
            "base64+zstd" | "base64zstd" => solana_rpc_client_api::response::UiAccountEncoding::Base64Zstd,
            "jsonparsed" | "json_parsed" => solana_rpc_client_api::response::UiAccountEncoding::JsonParsed,
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(
                        "accounts_encoding must be one of: base64|base64+zstd|jsonParsed",
                    ),
                    data: Some(json!({ "provided": encoding })),
                })
            }
        };
        Ok(enc)
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_suggest_compute_unit_limit(units_consumed: Option<u64>) -> Option<u32> {
        // Best-effort heuristic: 20% headroom + fixed 10k buffer.
        // Clamp to a reasonable range.
        let u = units_consumed?;
        let mut suggested = (u as f64 * 1.2).ceil() as u64;
        suggested = suggested.saturating_add(10_000);
        let min = 50_000u64;
        let max = 1_400_000u64;
        suggested = suggested.clamp(min, max);
        Some(suggested as u32)
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_percentile_u64(mut xs: Vec<u64>, p: f64) -> Option<u64> {
        if xs.is_empty() {
            return None;
        }
        xs.sort_unstable();
        let p = p.clamp(0.0, 1.0);
        let idx = ((xs.len() - 1) as f64 * p).round() as usize;
        xs.get(idx).copied()
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_suggest_fee_sample_addresses_from_metas(
        metas: &[solana_sdk::instruction::AccountMeta],
        max: usize,
    ) -> Vec<solana_sdk::pubkey::Pubkey> {
        // Heuristic: take writable accounts first (most likely to be hot / stateful),
        // then fill with remaining accounts. Dedup while preserving order.
        let mut out: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();

        let mut push = |pk: solana_sdk::pubkey::Pubkey| {
            if out.len() >= max {
                return;
            }
            if !out.contains(&pk) {
                out.push(pk);
            }
        };

        for m in metas.iter().filter(|m| m.is_writable) {
            push(m.pubkey);
        }
        for m in metas.iter().filter(|m| !m.is_writable) {
            push(m.pubkey);
        }

        out
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: build a (optionally signed) transaction from one or more instructions"))]
    async fn solana_tx_build(
        &self,
        Parameters(request): Parameters<SolanaTxBuildRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let rpc_url = Self::solana_rpc_url_for_network(network)?;
        let client = Self::solana_rpc(network)?;

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set"),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_tx_build", e))?
        };

        if request.instructions.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("instructions is required"),
                data: None,
            });
        }

        let mut ixs: Vec<solana_sdk::instruction::Instruction> = Vec::new();
        let mut ix_summaries: Vec<Value> = Vec::new();

        // Optional ComputeBudget instructions (prepend, as required by runtime conventions)
        if let Some(limit) = request.compute_unit_limit {
            ixs.push(solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_limit(
                limit,
            ));
            ix_summaries.push(json!({
                "index": "compute_budget_0",
                "program_id": "ComputeBudget111111111111111111111111111111",
                "kind": "set_compute_unit_limit",
                "compute_unit_limit": limit
            }));
        }
        if let Some(price) = request.compute_unit_price_micro_lamports {
            ixs.push(solana_compute_budget_interface::ComputeBudgetInstruction::set_compute_unit_price(
                price,
            ));
            ix_summaries.push(json!({
                "index": "compute_budget_1",
                "program_id": "ComputeBudget111111111111111111111111111111",
                "kind": "set_compute_unit_price",
                "compute_unit_price_micro_lamports": price
            }));
        }

        for (idx, ix) in request.instructions.iter().enumerate() {
            let program_id = Self::solana_parse_program_id(ix.program_id.trim())?;
            let data = base64::engine::general_purpose::STANDARD
                .decode(ix.data_base64.trim())
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid data_base64 for instruction {}: {}", idx, e)),
                    data: None,
                })?;

            let mut metas: Vec<solana_sdk::instruction::AccountMeta> = Vec::new();
            for m in &ix.accounts {
                let pk = Self::solana_parse_pubkey(m.pubkey.trim(), "account pubkey")?;
                metas.push(if m.is_writable {
                    solana_sdk::instruction::AccountMeta::new(pk, m.is_signer)
                } else {
                    solana_sdk::instruction::AccountMeta::new_readonly(pk, m.is_signer)
                });
            }

            ixs.push(solana_sdk::instruction::Instruction {
                program_id,
                accounts: metas,
                data,
            });

            ix_summaries.push(json!({
                "index": idx,
                "program_id": ix.program_id,
                "accounts_count": ix.accounts.len(),
                "data_base64_len": ix.data_base64.len()
            }));
        }

        let message = solana_sdk::message::Message::new(&ixs, Some(&fee_payer));

        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;

        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "fee_payer": fee_payer.to_string(),
            "recent_blockhash": recent_blockhash.to_string(),
            "signed": sign,
            "keypair_path": kp_path,
            "instructions": ix_summaries,
            "transaction_base64": tx_base64,
            "transaction_bytes_len": tx_bytes.len(),
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: simulate a transaction (no broadcast)"))]
    async fn solana_simulate_transaction(
        &self,
        Parameters(request): Parameters<SolanaSimulateTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let cfg = request.simulate_config.clone();
        let network = cfg
            .as_ref()
            .and_then(|c| c.network.as_deref())
            .or(request.network.as_deref());
        let rpc_url = Self::solana_rpc_url_for_network(network)?;
        let client = Self::solana_rpc(network)?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(request.transaction_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {}", e)),
                data: None,
            })?;

        let mut tx: solana_sdk::transaction::Transaction =
            bincode::deserialize(&tx_bytes).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction bytes: {}", e)),
                data: None,
            })?;

        let replace = cfg
            .as_ref()
            .and_then(|c| c.replace_recent_blockhash)
            .or(request.replace_recent_blockhash)
            .unwrap_or(true);
        if replace {
            let bh = client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_simulate_transaction", e))?;
            tx.message.recent_blockhash = bh;
        }

        let sig_verify = cfg
            .as_ref()
            .and_then(|c| c.sig_verify)
            .or(request.sig_verify)
            .unwrap_or(false);
        let strict_sig_verify = cfg
            .as_ref()
            .and_then(|c| c.strict_sig_verify)
            .unwrap_or(false);
        if sig_verify {
            // If strict, require a local keypair when signatures are missing.
            let need_sign = tx.signatures.is_empty()
                || tx
                    .signatures
                    .iter()
                    .all(|s| *s == solana_sdk::signature::Signature::default());

            let kp = Self::solana_keypair_path()
                .ok()
                .and_then(|p| Self::solana_read_keypair_from_json_file(&p).ok());

            if strict_sig_verify && need_sign && kp.is_none() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(
                        "sig_verify=true requires signatures but no local keypair is available. Set SOLANA_KEYPAIR_PATH or set simulate_config.strict_sig_verify=false",
                    ),
                    data: None,
                });
            }

            // Best-effort sign if signatures are missing and a keypair is available.
            Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());
        }

        let commitment = cfg
            .as_ref()
            .and_then(|c| c.commitment.clone())
            .or(request.commitment.clone())
            .unwrap_or("confirmed".to_string());

        let accounts_cfg = if let Some(ref c) = cfg {
            if let Some(ref addrs) = c.simulate_accounts {
                if addrs.is_empty() {
                    None
                } else {
                    let enc_str = c.accounts_encoding.as_deref().unwrap_or("base64");
                    let enc = Self::solana_ui_account_encoding_from_str(enc_str)?;
                    Some(solana_client::rpc_config::RpcSimulateTransactionAccountsConfig {
                        encoding: Some(enc),
                        addresses: addrs.clone(),
                    })
                }
            } else {
                None
            }
        } else {
            None
        };

        let sim = client
            .simulate_transaction_with_config(
                &tx,
                solana_client::rpc_config::RpcSimulateTransactionConfig {
                    sig_verify,
                    replace_recent_blockhash: replace,
                    commitment: Some(Self::solana_commitment_from_str(Some(&commitment))?),
                    encoding: None,
                    accounts: accounts_cfg,
                    min_context_slot: None,
                    inner_instructions: false,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_simulate_transaction", e))?;

        let suggested_cu_limit = Self::solana_suggest_compute_unit_limit(sim.value.units_consumed);

        let suggest_price = cfg
            .as_ref()
            .and_then(|c| c.suggest_compute_unit_price)
            .unwrap_or(false);
        let mut suggested_cu_price: Option<u64> = None;
        let mut price_sample: Option<Value> = None;
        if suggest_price {
            // Prefer account-scoped fees if the caller provided addresses.
            let addr_strs: Vec<String> = cfg
                .as_ref()
                .and_then(|c| c.simulate_accounts.clone())
                .unwrap_or_default();

            let mut addrs: Vec<solana_sdk::pubkey::Pubkey> = addr_strs
                .iter()
                .filter_map(|s| solana_sdk::pubkey::Pubkey::from_str(s.trim()).ok())
                .collect();

            if addrs.is_empty() {
                // Auto-sample from tx message keys (max 16)
                addrs = tx.message.account_keys.iter().take(16).cloned().collect();
            }

            let fees_res = if !addrs.is_empty() {
                client.get_recent_prioritization_fees(&addrs).await
            } else {
                // fallback: cluster-wide sample
                client.get_recent_prioritization_fees(&[]).await
            };

            if let Ok(fees) = fees_res {
                let vals: Vec<u64> = fees.iter().map(|f| f.prioritization_fee).collect();
                suggested_cu_price = Self::solana_percentile_u64(vals.clone(), 0.75);
                price_sample = Some(json!({
                    "scope": if !addrs.is_empty() { "addresses" } else { "cluster" },
                    "addresses_count": addrs.len(),
                    "addresses": addrs.iter().take(16).map(|p| p.to_string()).collect::<Vec<String>>(),
                    "count": fees.len(),
                    "p50": Self::solana_percentile_u64(vals.clone(), 0.50),
                    "p75": Self::solana_percentile_u64(vals.clone(), 0.75),
                    "p90": Self::solana_percentile_u64(vals, 0.90)
                }));
            }
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network.unwrap_or("mainnet"),
            "sig_verify": sig_verify,
            "replace_recent_blockhash": replace,
            "commitment": commitment,
            "context": sim.context,
            "value": sim.value,
            "suggestions": {
                "compute_unit_limit": suggested_cu_limit,
                "compute_unit_price_micro_lamports": suggested_cu_price,
                "recent_prioritization_fees": price_sample
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: simulate a single instruction by internally building a tx (no broadcast)"))]
    async fn solana_simulate_instruction(
        &self,
        Parameters(request): Parameters<SolanaSimulateInstructionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let cfg = request.simulate_config.clone();
        let network = cfg
            .as_ref()
            .and_then(|c| c.network.as_deref())
            .or(request.network.as_deref());
        let rpc_url = Self::solana_rpc_url_for_network(network)?;
        let client = Self::solana_rpc(network)?;

        // Fee payer is required (no dummy defaults).
        let fee_payer = Self::solana_parse_pubkey(request.fee_payer.trim(), "fee_payer")?;

        let replace = cfg
            .as_ref()
            .and_then(|c| c.replace_recent_blockhash)
            .or(request.replace_recent_blockhash)
            .unwrap_or(true);

        let recent_blockhash = if replace {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_simulate_instruction", e))?
        } else if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            // Still fetch if not provided, so the tx is always well-formed.
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_simulate_instruction", e))?
        };

        let ix_in = &request.instruction;
        let program_id = Self::solana_parse_program_id(ix_in.program_id.trim())?;
        let data = base64::engine::general_purpose::STANDARD
            .decode(ix_in.data_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid instruction.data_base64: {}", e)),
                data: None,
            })?;

        let mut metas: Vec<solana_sdk::instruction::AccountMeta> = Vec::new();
        for m in &ix_in.accounts {
            let pk = Self::solana_parse_pubkey(m.pubkey.trim(), "account pubkey")?;
            metas.push(if m.is_writable {
                solana_sdk::instruction::AccountMeta::new(pk, m.is_signer)
            } else {
                solana_sdk::instruction::AccountMeta::new_readonly(pk, m.is_signer)
            });
        }

        let metas_for_fee = metas.clone();

        let ix = solana_sdk::instruction::Instruction {
            program_id,
            accounts: metas,
            data,
        };

        let message = solana_sdk::message::Message::new(&[ix], Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        let sig_verify = cfg
            .as_ref()
            .and_then(|c| c.sig_verify)
            .or(request.sig_verify)
            .unwrap_or(false);
        let strict_sig_verify = cfg
            .as_ref()
            .and_then(|c| c.strict_sig_verify)
            .unwrap_or(false);
        if sig_verify {
            let need_sign = tx.signatures.is_empty()
                || tx
                    .signatures
                    .iter()
                    .all(|s| *s == solana_sdk::signature::Signature::default());

            let kp = Self::solana_keypair_path()
                .ok()
                .and_then(|p| Self::solana_read_keypair_from_json_file(&p).ok());

            if strict_sig_verify && need_sign && kp.is_none() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(
                        "sig_verify=true requires signatures but no local keypair is available. Set SOLANA_KEYPAIR_PATH or set simulate_config.strict_sig_verify=false",
                    ),
                    data: None,
                });
            }

            Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());
        }

        let commitment = cfg
            .as_ref()
            .and_then(|c| c.commitment.clone())
            .or(request.commitment.clone())
            .unwrap_or("confirmed".to_string());

        let accounts_cfg = if let Some(ref c) = cfg {
            if let Some(ref addrs) = c.simulate_accounts {
                if addrs.is_empty() {
                    None
                } else {
                    let enc_str = c.accounts_encoding.as_deref().unwrap_or("base64");
                    let enc = Self::solana_ui_account_encoding_from_str(enc_str)?;
                    Some(solana_client::rpc_config::RpcSimulateTransactionAccountsConfig {
                        encoding: Some(enc),
                        addresses: addrs.clone(),
                    })
                }
            } else {
                None
            }
        } else {
            None
        };

        let sim = client
            .simulate_transaction_with_config(
                &tx,
                solana_client::rpc_config::RpcSimulateTransactionConfig {
                    sig_verify,
                    replace_recent_blockhash: replace,
                    commitment: Some(Self::solana_commitment_from_str(Some(&commitment))?),
                    encoding: None,
                    accounts: accounts_cfg,
                    min_context_slot: None,
                    inner_instructions: false,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_simulate_instruction", e))?;

        let suggested_cu_limit = Self::solana_suggest_compute_unit_limit(sim.value.units_consumed);

        let suggest_price = cfg
            .as_ref()
            .and_then(|c| c.suggest_compute_unit_price)
            .unwrap_or(false);
        let mut suggested_cu_price: Option<u64> = None;
        let mut price_sample: Option<Value> = None;
        if suggest_price {
            let addr_strs: Vec<String> = cfg
                .as_ref()
                .and_then(|c| c.simulate_accounts.clone())
                .unwrap_or_default();

            let mut addrs: Vec<solana_sdk::pubkey::Pubkey> = addr_strs
                .iter()
                .filter_map(|s| solana_sdk::pubkey::Pubkey::from_str(s.trim()).ok())
                .collect();

            if addrs.is_empty() {
                // Auto-sample addresses from the instruction metas (max 16)
                addrs = Self::solana_suggest_fee_sample_addresses_from_metas(&metas_for_fee, 16);
            }

            let fees_res = if !addrs.is_empty() {
                client.get_recent_prioritization_fees(&addrs).await
            } else {
                client.get_recent_prioritization_fees(&[]).await
            };

            if let Ok(fees) = fees_res {
                let vals: Vec<u64> = fees.iter().map(|f| f.prioritization_fee).collect();
                suggested_cu_price = Self::solana_percentile_u64(vals.clone(), 0.75);
                price_sample = Some(json!({
                    "scope": if !addrs.is_empty() { "addresses" } else { "cluster" },
                    "addresses_count": addrs.len(),
                    "addresses": addrs.iter().take(16).map(|p| p.to_string()).collect::<Vec<String>>(),
                    "count": fees.len(),
                    "p50": Self::solana_percentile_u64(vals.clone(), 0.50),
                    "p75": Self::solana_percentile_u64(vals.clone(), 0.75),
                    "p90": Self::solana_percentile_u64(vals, 0.90)
                }));
            }
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network.unwrap_or("mainnet"),
            "fee_payer": request.fee_payer,
            "recent_blockhash": recent_blockhash.to_string(),
            "sig_verify": sig_verify,
            "replace_recent_blockhash": replace,
            "commitment": commitment,
            "instruction": {
                "program_id": ix_in.program_id,
                "accounts_count": ix_in.accounts.len(),
                "data_base64_len": ix_in.data_base64.len()
            },
            "context": sim.context,
            "value": sim.value,
            "suggestions": {
                "compute_unit_limit": suggested_cu_limit,
                "compute_unit_price_micro_lamports": suggested_cu_price,
                "recent_prioritization_fees": price_sample
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: analyze a transaction (read-only). Returns program ids used and best-effort decoded actions."))]
    async fn solana_tx_analyze(
        &self,
        Parameters(request): Parameters<SolanaTxAnalyzeRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        use std::str::FromStr;

        let network = request.network.as_deref().unwrap_or("mainnet");
        let rpc_url = Self::solana_rpc_url_for_network(Some(network))?;
        let client = Self::solana_rpc(Some(network))?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(request.transaction_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {e}")),
                data: None,
            })?;

        let vtx: Option<solana_transaction::versioned::VersionedTransaction> =
            bincode::deserialize(&tx_bytes).ok();

        // Resolve account keys with LUT (best-effort).
        let (mut account_keys, mut instructions, mut address_table_lookups): (
            Vec<solana_sdk::pubkey::Pubkey>,
            Vec<solana_message::compiled_instruction::CompiledInstruction>,
            Vec<Value>,
        ) = (Vec::new(), Vec::new(), Vec::new());

        let mut tx_version = "legacy".to_string();
        let mut recent_blockhash: Option<String> = None;

        if let Some(v) = vtx.as_ref() {
            match &v.message {
                solana_message::VersionedMessage::Legacy(msg) => {
                    tx_version = "legacy".to_string();
                    account_keys = msg.account_keys.clone();
                    instructions = msg.instructions.clone();
                    recent_blockhash = Some(msg.recent_blockhash.to_string());
                }
                solana_message::VersionedMessage::V0(msg) => {
                    tx_version = "v0".to_string();
                    account_keys = msg.account_keys.clone();
                    instructions = msg.instructions.clone();
                    recent_blockhash = Some(msg.recent_blockhash.to_string());

                    let mut loaded_writable: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();
                    let mut loaded_readonly: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();

                    for l in &msg.address_table_lookups {
                        let lut_addr = l.account_key;
                        let mut resolved: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();
                        let mut err: Option<String> = None;

                        match client.get_account(&lut_addr).await {
                            Ok(a) => match solana_address_lookup_table_interface::state::AddressLookupTable::deserialize(&a.data) {
                                Ok(alt) => resolved = alt.addresses.to_vec(),
                                Err(e) => err = Some(format!("ALT deserialize failed: {e}")),
                            },
                            Err(e) => err = Some(format!("ALT fetch failed: {e}")),
                        }

                        let w: Vec<solana_sdk::pubkey::Pubkey> = l
                            .writable_indexes
                            .iter()
                            .filter_map(|i| resolved.get(*i as usize).cloned())
                            .collect();
                        let r: Vec<solana_sdk::pubkey::Pubkey> = l
                            .readonly_indexes
                            .iter()
                            .filter_map(|i| resolved.get(*i as usize).cloned())
                            .collect();

                        loaded_writable.extend(w.iter().cloned());
                        loaded_readonly.extend(r.iter().cloned());

                        address_table_lookups.push(json!({
                            "address": lut_addr.to_string(),
                            "writable_indexes_len": l.writable_indexes.len(),
                            "readonly_indexes_len": l.readonly_indexes.len(),
                            "resolved_writable_len": w.len(),
                            "resolved_readonly_len": r.len(),
                            "error": err
                        }));
                    }

                    account_keys.extend(loaded_writable);
                    account_keys.extend(loaded_readonly);
                }
            }
        } else {
            let tx: solana_sdk::transaction::Transaction =
                bincode::deserialize(&tx_bytes).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid transaction bytes: {e}")),
                    data: None,
                })?;
            tx_version = "legacy".to_string();
            account_keys = tx.message.account_keys.clone();
            instructions = tx.message.instructions.clone();
            recent_blockhash = Some(tx.message.recent_blockhash.to_string());
        }

        let fee_payer = account_keys.first().map(|p| p.to_string());

        // Program ids used.
        let mut programs_used: std::collections::HashSet<String> = std::collections::HashSet::new();
        for ix in &instructions {
            if let Some(pid) = account_keys.get(ix.program_id_index as usize) {
                programs_used.insert(pid.to_string());
            }
        }

        // Decode a small set of common actions.
        let system_program = solana_sdk::pubkey::Pubkey::from_str("11111111111111111111111111111111").unwrap();
        let token_legacy = solana_sdk::pubkey::Pubkey::from_str("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").ok();
        let token_2022 = solana_sdk::pubkey::Pubkey::from_str("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb").ok();

        let mut actions: Vec<Value> = Vec::new();
        for ix in &instructions {
            let pid = match account_keys.get(ix.program_id_index as usize) {
                Some(p) => *p,
                None => continue,
            };

            // System transfer (tag 2)
            if pid == system_program && ix.data.len() == 12 {
                let mut tag = [0u8; 4];
                tag.copy_from_slice(&ix.data[0..4]);
                if u32::from_le_bytes(tag) == 2 {
                    let mut amt = [0u8; 8];
                    amt.copy_from_slice(&ix.data[4..12]);
                    let lamports = u64::from_le_bytes(amt);
                    let from = ix.accounts.get(0).and_then(|i| account_keys.get(*i as usize)).map(|p| p.to_string());
                    let to = ix.accounts.get(1).and_then(|i| account_keys.get(*i as usize)).map(|p| p.to_string());
                    actions.push(json!({
                        "kind": "system_transfer",
                        "lamports": lamports,
                        "from": from,
                        "to": to
                    }));
                }
            }

            // SPL token transfer/transfer_checked
            if token_legacy.as_ref() == Some(&pid) || token_2022.as_ref() == Some(&pid) {
                if ix.data.is_empty() {
                    continue;
                }
                let tag = ix.data[0];
                if (tag == 3 && ix.data.len() == 9) || (tag == 12 && ix.data.len() == 10) {
                    let mut amt = [0u8; 8];
                    amt.copy_from_slice(&ix.data[1..9]);
                    let amount = u64::from_le_bytes(amt);
                    let (source_i, dest_i, auth_i) = if tag == 12 { (0usize, 2usize, 3usize) } else { (0usize, 1usize, 2usize) };

                    let source = ix.accounts.get(source_i).and_then(|i| account_keys.get(*i as usize)).map(|p| p.to_string());
                    let destination = ix.accounts.get(dest_i).and_then(|i| account_keys.get(*i as usize)).map(|p| p.to_string());
                    let authority = ix.accounts.get(auth_i).and_then(|i| account_keys.get(*i as usize)).map(|p| p.to_string());

                    actions.push(json!({
                        "kind": if tag == 12 { "token_transfer_checked" } else { "token_transfer" },
                        "program_id": pid.to_string(),
                        "amount": amount,
                        "source": source,
                        "destination": destination,
                        "authority": authority
                    }));
                }
            }
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network,
            "tx_version": tx_version,
            "fee_payer": fee_payer,
            "recent_blockhash": recent_blockhash,
            "account_keys_len": account_keys.len(),
            "address_table_lookups": address_table_lookups,
            "programs_used": programs_used.into_iter().collect::<Vec<String>>(),
            "actions": actions
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana: preview+simulate a transaction, return a short-lived confirmation token (id/hash) (safe default: does not broadcast)"))]
    async fn solana_tx_preview(
        &self,
        Parameters(request): Parameters<SolanaTxPreviewRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let cfg = request.simulate_config.clone();
        let network = cfg
            .as_ref()
            .and_then(|c| c.network.as_deref())
            .or(request.network.as_deref());
        let network_str = network.unwrap_or("mainnet").to_string();
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;
        let client = Self::solana_rpc(Some(&network_str))?;

        // Decode + parse tx
        let tx_bytes_in = base64::engine::general_purpose::STANDARD
            .decode(request.transaction_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {}", e)),
                data: None,
            })?;

        // Decode transaction: try VersionedTransaction (supports v0+LUT), then fallback to legacy Transaction
        let mut vtx: Option<solana_transaction::versioned::VersionedTransaction> =
            bincode::deserialize(&tx_bytes_in).ok();
        let mut tx: Option<solana_sdk::transaction::Transaction> = None;

        if vtx.is_none() {
            tx = Some(
                bincode::deserialize(&tx_bytes_in).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid transaction bytes: {}", e)),
                    data: None,
                })?,
            );
        }

        let mut tx_version: String = "legacy".to_string();
        let mut message_account_keys: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();
        let mut message_instructions: Vec<solana_message::compiled_instruction::CompiledInstruction> =
            Vec::new();
        let mut address_table_lookups: Vec<Value> = Vec::new();

        if let Some(ref mut legacy_tx) = tx {
            tx_version = "legacy".to_string();
            message_account_keys = legacy_tx.message.account_keys.clone();
            message_instructions = legacy_tx.message.instructions.clone();
        }

        if let Some(ref mut vt) = vtx {
            match &vt.message {
                solana_message::VersionedMessage::Legacy(msg) => {
                    tx_version = "legacy".to_string();
                    message_account_keys = msg.account_keys.clone();
                    message_instructions = msg.instructions.clone();
                }
                solana_message::VersionedMessage::V0(msg) => {
                    tx_version = "v0".to_string();

                    // Load LUT addresses (best-effort) and build combined account keys
                    let mut loaded_writable: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();
                    let mut loaded_readonly: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();

                    let mut lut_cache: std::collections::HashMap<solana_sdk::pubkey::Pubkey, Result<Vec<solana_sdk::pubkey::Pubkey>, String>> =
                        std::collections::HashMap::new();

                    for l in &msg.address_table_lookups {
                        let lut_addr = l.account_key;

                        let entry = if let Some(e) = lut_cache.get(&lut_addr) {
                            e.clone()
                        } else {
                            let res = match client.get_account(&lut_addr).await {
                                Ok(a) => solana_address_lookup_table_interface::state::AddressLookupTable::deserialize(&a.data)
                                    .map(|alt| alt.addresses.to_vec())
                                    .map_err(|e| format!("ALT deserialize failed: {e}")),
                                Err(e) => Err(format!("ALT account fetch failed: {e}")),
                            };
                            lut_cache.insert(lut_addr, res.clone());
                            res
                        };

                        let (lut_addresses, lut_error): (Vec<solana_sdk::pubkey::Pubkey>, Option<String>) =
                            match entry {
                                Ok(v) => (v, None),
                                Err(e) => (Vec::new(), Some(e)),
                            };

                        let w: Vec<solana_sdk::pubkey::Pubkey> = l
                            .writable_indexes
                            .iter()
                            .filter_map(|i| lut_addresses.get(*i as usize).cloned())
                            .collect();
                        let r: Vec<solana_sdk::pubkey::Pubkey> = l
                            .readonly_indexes
                            .iter()
                            .filter_map(|i| lut_addresses.get(*i as usize).cloned())
                            .collect();
                        loaded_writable.extend(w.iter().cloned());
                        loaded_readonly.extend(r.iter().cloned());

                        address_table_lookups.push(json!({
                            "address": lut_addr.to_string(),
                            "writable_indexes_len": l.writable_indexes.len(),
                            "readonly_indexes_len": l.readonly_indexes.len(),
                            "resolved_writable_len": w.len(),
                            "resolved_readonly_len": r.len(),
                            "error": lut_error
                        }));
                    }

                    message_account_keys = msg.account_keys.clone();
                    message_account_keys.extend(loaded_writable);
                    message_account_keys.extend(loaded_readonly);
                    message_instructions = msg.instructions.clone();
                }
            }
        }

        // Default-safe: keep sig_verify=false unless explicitly requested.
        let sig_verify = cfg.as_ref().and_then(|c| c.sig_verify).unwrap_or(false);
        let strict_sig_verify = cfg
            .as_ref()
            .and_then(|c| c.strict_sig_verify)
            .unwrap_or(false);

        // By default, refresh blockhash to reduce "BlockhashNotFound".
        let replace = cfg
            .as_ref()
            .and_then(|c| c.replace_recent_blockhash)
            .unwrap_or(true);
        if replace {
            let bh = client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_tx_preview", e))?;
            if let Some(ref mut legacy_tx) = tx {
                legacy_tx.message.recent_blockhash = bh;
            }
            if let Some(ref mut vt) = vtx {
                vt.message.set_recent_blockhash(bh);
            }
        }

        if sig_verify {
            // For v0 txs, strict signature verification requires external signing (we don't sign v0 locally yet).
            if tx_version == "v0" {
                if strict_sig_verify {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "sig_verify=true for v0 transactions is not supported without external signatures. Provide a signed v0 transaction_base64 or set simulate_config.strict_sig_verify=false",
                        ),
                        data: None,
                    });
                }
            } else if let Some(ref mut legacy_tx) = tx {
                // If strict, require a local keypair when signatures are missing.
                let need_sign = legacy_tx.signatures.is_empty()
                    || legacy_tx
                        .signatures
                        .iter()
                        .all(|s| *s == solana_sdk::signature::Signature::default());

                let kp = Self::solana_keypair_path()
                    .ok()
                    .and_then(|p| Self::solana_read_keypair_from_json_file(&p).ok());

                if strict_sig_verify && need_sign && kp.is_none() {
                    return Err(ErrorData {
                        code: ErrorCode(-32602),
                        message: Cow::from(
                            "sig_verify=true requires signatures but no local keypair is available. Set SOLANA_KEYPAIR_PATH or set simulate_config.strict_sig_verify=false",
                        ),
                        data: None,
                    });
                }

                // Best-effort sign if signatures are missing and a keypair is available.
                Self::solana_try_sign_if_needed(legacy_tx, kp.as_ref());
            }
        }

        let commitment = cfg
            .as_ref()
            .and_then(|c| c.commitment.clone())
            .unwrap_or("confirmed".to_string());

        let accounts_cfg = if let Some(ref c) = cfg {
            if let Some(ref addrs) = c.simulate_accounts {
                if addrs.is_empty() {
                    None
                } else {
                    let enc_str = c.accounts_encoding.as_deref().unwrap_or("base64");
                    let enc = Self::solana_ui_account_encoding_from_str(enc_str)?;
                    Some(solana_client::rpc_config::RpcSimulateTransactionAccountsConfig {
                        encoding: Some(enc),
                        addresses: addrs.clone(),
                    })
                }
            } else {
                None
            }
        } else {
            None
        };

        let mut retry_used = false;
        let mut retry_error: Option<String> = None;

        let mut sim = if let Some(ref legacy_tx) = tx {
            client
                .simulate_transaction_with_config(
                    legacy_tx,
                    solana_client::rpc_config::RpcSimulateTransactionConfig {
                        sig_verify,
                        replace_recent_blockhash: replace,
                        commitment: Some(Self::solana_commitment_from_str(Some(&commitment))?),
                        encoding: None,
                        accounts: accounts_cfg.clone(),
                        min_context_slot: None,
                        inner_instructions: false,
                    },
                )
                .await
                .map_err(|e| Self::sdk_error("solana_tx_preview", e))?
        } else if let Some(ref vt) = vtx {
            client
                .simulate_transaction_with_config(
                    vt,
                    solana_client::rpc_config::RpcSimulateTransactionConfig {
                        sig_verify,
                        replace_recent_blockhash: replace,
                        commitment: Some(Self::solana_commitment_from_str(Some(&commitment))?),
                        encoding: None,
                        accounts: accounts_cfg.clone(),
                        min_context_slot: None,
                        inner_instructions: false,
                    },
                )
                .await
                .map_err(|e| Self::sdk_error("solana_tx_preview", e))?
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from("Failed to decode transaction"),
                data: None,
            });
        };

        // If caller disabled replace_recent_blockhash and we hit BlockhashNotFound,
        // retry once with a fresh blockhash (wallet-like behavior).
        if !replace {
            let err_str = sim.value.err.as_ref().map(|e| format!("{:?}", e));
            if err_str
                .as_deref()
                .map(|s| s.contains("BlockhashNotFound"))
                .unwrap_or(false)
            {
                let bh = client
                    .get_latest_blockhash()
                    .await
                    .map_err(|e| Self::sdk_error("solana_tx_preview", e))?;

                if let Some(ref mut legacy_tx) = tx {
                    legacy_tx.message.recent_blockhash = bh;
                }
                if let Some(ref mut vt) = vtx {
                    vt.message.set_recent_blockhash(bh);
                }

                let retry = if let Some(ref legacy_tx) = tx {
                    client
                        .simulate_transaction_with_config(
                            legacy_tx,
                            solana_client::rpc_config::RpcSimulateTransactionConfig {
                                sig_verify,
                                replace_recent_blockhash: true,
                                commitment: Some(
                                    Self::solana_commitment_from_str(Some(&commitment))?,
                                ),
                                encoding: None,
                                accounts: accounts_cfg.clone(),
                                min_context_slot: None,
                                inner_instructions: false,
                            },
                        )
                        .await
                } else if let Some(ref vt) = vtx {
                    client
                        .simulate_transaction_with_config(
                            vt,
                            solana_client::rpc_config::RpcSimulateTransactionConfig {
                                sig_verify,
                                replace_recent_blockhash: true,
                                commitment: Some(
                                    Self::solana_commitment_from_str(Some(&commitment))?,
                                ),
                                encoding: None,
                                accounts: accounts_cfg.clone(),
                                min_context_slot: None,
                                inner_instructions: false,
                            },
                        )
                        .await
                } else {
                    unreachable!();
                };

                match retry {
                    Ok(s) => {
                        retry_used = true;
                        retry_error = None;
                        sim = s;
                    }
                    Err(e) => {
                        retry_used = true;
                        retry_error = Some(e.to_string());
                    }
                }
            }
        }

        // Re-serialize (may differ from input if blockhash/signatures updated)
        let tx_bytes = (if let Some(ref legacy_tx) = tx {
            bincode::serialize(legacy_tx)
        } else if let Some(ref vt) = vtx {
            bincode::serialize(vt)
        } else {
            // should be impossible
            bincode::serialize(&())
        })
        .map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize tx: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);
        let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

        // Compute suggestions
        let suggested_cu_limit = Self::solana_suggest_compute_unit_limit(sim.value.units_consumed);

        let suggest_price = cfg
            .as_ref()
            .and_then(|c| c.suggest_compute_unit_price)
            .unwrap_or(false);
        let mut suggested_cu_price: Option<u64> = None;
        let mut price_sample: Option<Value> = None;
        if suggest_price {
            let addr_strs: Vec<String> = cfg
                .as_ref()
                .and_then(|c| c.simulate_accounts.clone())
                .unwrap_or_default();

            let mut addrs: Vec<solana_sdk::pubkey::Pubkey> = addr_strs
                .iter()
                .filter_map(|s| solana_sdk::pubkey::Pubkey::from_str(s.trim()).ok())
                .collect();

            if addrs.is_empty() {
                addrs = message_account_keys.iter().take(16).cloned().collect();
            }

            let fees_res = if !addrs.is_empty() {
                client.get_recent_prioritization_fees(&addrs).await
            } else {
                client.get_recent_prioritization_fees(&[]).await
            };

            if let Ok(fees) = fees_res {
                let vals: Vec<u64> = fees.iter().map(|f| f.prioritization_fee).collect();
                suggested_cu_price = Self::solana_percentile_u64(vals.clone(), 0.75);
                price_sample = Some(json!({
                    "scope": if !addrs.is_empty() { "addresses" } else { "cluster" },
                    "addresses_count": addrs.len(),
                    "addresses": addrs.iter().take(16).map(|p| p.to_string()).collect::<Vec<String>>(),
                    "count": fees.len(),
                    "p50": Self::solana_percentile_u64(vals.clone(), 0.50),
                    "p75": Self::solana_percentile_u64(vals.clone(), 0.75),
                    "p90": Self::solana_percentile_u64(vals, 0.90),
                    "suggested_from": "p75"
                }));
            }
        }

        // Preview analysis: short summary + expandable details
        let mut program_ids: Vec<String> = Vec::new();
        let mut program_ids_unknown: Vec<String> = Vec::new();
        let mut warnings: Vec<Value> = Vec::new();
        let mut summary_lines: Vec<String> = Vec::new();
        let mut details_instructions: Vec<Value> = Vec::new();

        let token_pid = spl_token::id().to_string();
        let token_2022_pid = spl_token_2022::id().to_string();
        let ata_pid = spl_associated_token_account::id().to_string();
        let compute_budget_pid = solana_compute_budget_interface::id().to_string();
        let system_pid = "11111111111111111111111111111111";
        let jupiter_v6_pid = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";
        let mut jupiter_warned = false;

        let key_of = |i: u8| -> String {
            message_account_keys
                .get(i as usize)
                .map(|p| p.to_string())
                .unwrap_or_default()
        };

        let key_at = |v: &[u8], idx: usize| -> String {
            v.get(idx).copied().map(key_of).unwrap_or_default()
        };

        for (ix_index, ci) in message_instructions.iter().enumerate() {
            let pid = message_account_keys
                .get(ci.program_id_index as usize)
                .map(|p| p.to_string())
                .unwrap_or_default();
            if !pid.is_empty() && !program_ids.contains(&pid) {
                program_ids.push(pid.clone());
            }

            // Track unknown programs for wallet-like warnings
            // We only flag truly unknown *program ids* here. Known program ids and known-safe addresses
            // (including common mints) should not trigger the alarm.
            let known_program = pid == token_pid
                || pid == token_2022_pid
                || pid == ata_pid
                || pid == compute_budget_pid
                || pid == system_pid
                || Self::solana_is_known_safe_address(&pid);
            if !pid.is_empty() && !known_program && !program_ids_unknown.contains(&pid) {
                program_ids_unknown.push(pid.clone());
            }

            // Default detail record
            let mut detail = json!({
                "index": ix_index,
                "program_id": pid,
                "program_label": Self::solana_known_program_label(&pid),
                "accounts": ci.accounts.iter().map(|a| key_of(*a)).collect::<Vec<String>>(),
                "accounts_labeled": ci.accounts.iter().map(|a| {
                    let pk = key_of(*a);
                    json!({
                        "pubkey": pk,
                        "label": Self::solana_known_program_label(&pk)
                    })
                }).collect::<Vec<Value>>(),
                "data_len": ci.data.len(),
                "kind": "unknown"
            });

            if pid == jupiter_v6_pid {
                // Jupiter is an important, widely-used router program.
                // Full decoding requires Jupiter-specific instruction layouts (often Anchor-encoded).
                // For now, provide wallet-like clarity without guessing amounts.
                detail["kind"] = json!("jupiter_v6");
                detail["note"] = json!("Jupiter router instruction (Anchor-encoded). Decoding is best-effort.");
                detail["accounts_len"] = json!(ci.accounts.len());

                // Anchor programs typically prefix instruction data with an 8-byte discriminator.
                if ci.data.len() >= 8 {
                    let disc8: [u8; 8] = ci.data[0..8].try_into().unwrap();
                    let disc_u64 = u64::from_le_bytes(disc8);
                    detail["anchor_discriminator_u64_le"] = json!(disc_u64.to_string());
                    detail["anchor_discriminator_hex"] = json!(disc8.iter().map(|b| format!("{:02x}", b)).collect::<String>());
                    detail["anchor_discriminator_base64"] = json!(base64::engine::general_purpose::STANDARD.encode(disc8));
                    detail["anchor_args_len"] = json!(ci.data.len().saturating_sub(8));

                    // Try to map discriminator -> known Jupiter V6 instruction name.
                    // Anchor discriminator = first 8 bytes of sha256("global:<ix_name>").
                    let jup_candidates: [&str; 10] = [
                        "shared_accounts_route",
                        "shared_accounts_exact_out_route",
                        "shared_accounts_route_with_token_ledger",
                        "shared_accounts_exact_out_route_with_token_ledger",
                        "route",
                        "exact_out_route",
                        "route_with_token_ledger",
                        "exact_out_route_with_token_ledger",
                        "claim",
                        "set_token_ledger",
                    ];

                    let mut matched: Option<&str> = None;
                    for name in jup_candidates {
                        let preimage = format!("global:{name}");
                        let h = solana_sdk::hash::hash(preimage.as_bytes());
                        let cand: [u8; 8] = h.to_bytes()[0..8].try_into().unwrap();
                        if cand == disc8 {
                            matched = Some(name);
                            break;
                        }
                    }

                    if let Some(name) = matched {
                        detail["anchor_instruction"] = json!(name);
                        detail["anchor_instruction_display"] =
                            json!(name.split('_').map(|w| {
                                let mut c = w.chars();
                                match c.next() {
                                    None => "".to_string(),
                                    Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                                }
                            }).collect::<Vec<String>>().join(""));
                        summary_lines.push(format!("Jupiter: instruction={name}"));
                    }

                    // Best-effort: decode Jupiter instructions using carbon-jupiter-swap-decoder Borsh types.
                    // We key off the 8-byte Anchor discriminator (LE u64) observed on-chain.
                    if ci.data.len() > 8 {
                        match disc_u64 {
                            // SharedAccountsRoute
                            0xc1209b3341d69c81 => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::shared_accounts_route::SharedAccountsRoute as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("shared_accounts_route");
                                    detail["jupiter_shared_accounts_route"] = json!({
                                        "id": ix.id,
                                        "in_amount": ix.in_amount.to_string(),
                                        "quoted_out_amount": ix.quoted_out_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "percent": s.percent,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 13 {
                                        detail["jupiter_accounts"] = json!({
                                            "token_program": accs[0],
                                            "program_authority": accs[1],
                                            "user_transfer_authority": accs[2],
                                            "source_token_account": accs[3],
                                            "program_source_token_account": accs[4],
                                            "program_destination_token_account": accs[5],
                                            "destination_token_account": accs[6],
                                            "source_mint": accs[7],
                                            "destination_mint": accs[8],
                                            "platform_fee_account": accs[9],
                                            "token_2022_program": accs[10],
                                            "event_authority": accs[11],
                                            "program": accs[12]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter swap (ExactIn): {} -> {} (in={}, quote_out={}, slippage_bps={})",
                                            accs[7],
                                            accs[8],
                                            ix.in_amount,
                                            ix.quoted_out_amount,
                                            ix.slippage_bps
                                        ));
                                    }
                                }
                            }

                            // SharedAccountsExactOutRoute
                            0xb0d169a89a7d453e => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::shared_accounts_exact_out_route::SharedAccountsExactOutRoute as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("shared_accounts_exact_out_route");
                                    detail["jupiter_shared_accounts_exact_out_route"] = json!({
                                        "id": ix.id,
                                        "out_amount": ix.out_amount.to_string(),
                                        "quoted_in_amount": ix.quoted_in_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "percent": s.percent,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 13 {
                                        detail["jupiter_accounts"] = json!({
                                            "token_program": accs[0],
                                            "program_authority": accs[1],
                                            "user_transfer_authority": accs[2],
                                            "source_token_account": accs[3],
                                            "program_source_token_account": accs[4],
                                            "program_destination_token_account": accs[5],
                                            "destination_token_account": accs[6],
                                            "source_mint": accs[7],
                                            "destination_mint": accs[8],
                                            "platform_fee_account": accs[9],
                                            "token_2022_program": accs[10],
                                            "event_authority": accs[11],
                                            "program": accs[12]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter swap (ExactOut): {} -> {} (out={}, quote_in={}, slippage_bps={})",
                                            accs[7],
                                            accs[8],
                                            ix.out_amount,
                                            ix.quoted_in_amount,
                                            ix.slippage_bps
                                        ));
                                    }
                                }
                            }

                            // Route
                            0xe517cb977ae3ad2a => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::route::Route as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("route");
                                    detail["jupiter_route"] = json!({
                                        "in_amount": ix.in_amount.to_string(),
                                        "quoted_out_amount": ix.quoted_out_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "percent": s.percent,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 9 {
                                        detail["jupiter_accounts"] = json!({
                                            "token_program": accs[0],
                                            "user_transfer_authority": accs[1],
                                            "user_source_token_account": accs[2],
                                            "user_destination_token_account": accs[3],
                                            "destination_token_account": accs[4],
                                            "destination_mint": accs[5],
                                            "platform_fee_account": accs[6],
                                            "event_authority": accs[7],
                                            "program": accs[8]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter route (ExactIn): in={}, quote_out={}, slippage_bps={} (dest_mint={})",
                                            ix.in_amount,
                                            ix.quoted_out_amount,
                                            ix.slippage_bps,
                                            accs[5]
                                        ));
                                    }
                                }
                            }

                            // ExactOutRoute
                            0xd033ef977b2bed5c => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::exact_out_route::ExactOutRoute as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("exact_out_route");
                                    detail["jupiter_exact_out_route"] = json!({
                                        "out_amount": ix.out_amount.to_string(),
                                        "quoted_in_amount": ix.quoted_in_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "percent": s.percent,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 11 {
                                        detail["jupiter_accounts"] = json!({
                                            "token_program": accs[0],
                                            "user_transfer_authority": accs[1],
                                            "user_source_token_account": accs[2],
                                            "user_destination_token_account": accs[3],
                                            "destination_token_account": accs[4],
                                            "source_mint": accs[5],
                                            "destination_mint": accs[6],
                                            "platform_fee_account": accs[7],
                                            "token_2022_program": accs[8],
                                            "event_authority": accs[9],
                                            "program": accs[10]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter route (ExactOut): {} -> {} (out={}, quote_in={}, slippage_bps={})",
                                            accs[5],
                                            accs[6],
                                            ix.out_amount,
                                            ix.quoted_in_amount,
                                            ix.slippage_bps
                                        ));
                                    }
                                }
                            }

                            // RouteWithTokenLedger
                            0x96564774a75d0e68 => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::route_with_token_ledger::RouteWithTokenLedger as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("route_with_token_ledger");
                                    detail["jupiter_route_with_token_ledger"] = json!({
                                        "quoted_out_amount": ix.quoted_out_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "percent": s.percent,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 10 {
                                        detail["jupiter_accounts"] = json!({
                                            "token_program": accs[0],
                                            "user_transfer_authority": accs[1],
                                            "user_source_token_account": accs[2],
                                            "user_destination_token_account": accs[3],
                                            "destination_token_account": accs[4],
                                            "destination_mint": accs[5],
                                            "platform_fee_account": accs[6],
                                            "token_ledger": accs[7],
                                            "event_authority": accs[8],
                                            "program": accs[9]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter route (TokenLedger): quote_out={}, slippage_bps={} (dest_mint={})",
                                            ix.quoted_out_amount,
                                            ix.slippage_bps,
                                            accs[5]
                                        ));
                                    }
                                }
                            }

                            // SharedAccountsRouteWithTokenLedger
                            0xe6798f50779f6aaa => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::shared_accounts_route_with_token_ledger::SharedAccountsRouteWithTokenLedger as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("shared_accounts_route_with_token_ledger");
                                    detail["jupiter_shared_accounts_route_with_token_ledger"] = json!({
                                        "id": ix.id,
                                        "quoted_out_amount": ix.quoted_out_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "percent": s.percent,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 14 {
                                        detail["jupiter_accounts"] = json!({
                                            "token_program": accs[0],
                                            "program_authority": accs[1],
                                            "user_transfer_authority": accs[2],
                                            "source_token_account": accs[3],
                                            "program_source_token_account": accs[4],
                                            "program_destination_token_account": accs[5],
                                            "destination_token_account": accs[6],
                                            "source_mint": accs[7],
                                            "destination_mint": accs[8],
                                            "platform_fee_account": accs[9],
                                            "token_2022_program": accs[10],
                                            "token_ledger": accs[11],
                                            "event_authority": accs[12],
                                            "program": accs[13]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter swap (TokenLedger): {} -> {} (quote_out={}, slippage_bps={})",
                                            accs[7],
                                            accs[8],
                                            ix.quoted_out_amount,
                                            ix.slippage_bps
                                        ));
                                    }
                                }
                            }

                            // V2 variants
                            0xbb64facc31c4af14 => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::route_v2::RouteV2 as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("route_v2");
                                    detail["jupiter_route_v2"] = json!({
                                        "in_amount": ix.in_amount.to_string(),
                                        "quoted_out_amount": ix.quoted_out_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "positive_slippage_bps": ix.positive_slippage_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "bps": s.bps,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });

                                    let accs: Vec<String> = ci.accounts.iter().map(|a| key_of(*a)).collect();
                                    if accs.len() >= 10 {
                                        detail["jupiter_accounts"] = json!({
                                            "user_transfer_authority": accs[0],
                                            "user_source_token_account": accs[1],
                                            "user_destination_token_account": accs[2],
                                            "source_mint": accs[3],
                                            "destination_mint": accs[4],
                                            "source_token_program": accs[5],
                                            "destination_token_program": accs[6],
                                            "destination_token_account": accs[7],
                                            "event_authority": accs[8],
                                            "program": accs[9]
                                        });
                                        summary_lines.push(format!(
                                            "Jupiter swap v2 (ExactIn): {} -> {} (in={}, quote_out={}, slippage_bps={})",
                                            accs[3],
                                            accs[4],
                                            ix.in_amount,
                                            ix.quoted_out_amount,
                                            ix.slippage_bps
                                        ));
                                    }
                                }
                            }

                            0x9d8ab85215f4f324 => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::exact_out_route_v2::ExactOutRouteV2 as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("exact_out_route_v2");
                                    detail["jupiter_exact_out_route_v2"] = json!({
                                        "out_amount": ix.out_amount.to_string(),
                                        "quoted_in_amount": ix.quoted_in_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "positive_slippage_bps": ix.positive_slippage_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "bps": s.bps,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });
                                }
                            }

                            0xd19853937cfed8e9 => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::shared_accounts_route_v2::SharedAccountsRouteV2 as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("shared_accounts_route_v2");
                                    detail["jupiter_shared_accounts_route_v2"] = json!({
                                        "id": ix.id,
                                        "in_amount": ix.in_amount.to_string(),
                                        "quoted_out_amount": ix.quoted_out_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "positive_slippage_bps": ix.positive_slippage_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "bps": s.bps,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });
                                }
                            }

                            0x3560e5cad8bbfa18 => {
                                if let Ok(ix) = <carbon_jupiter_swap_decoder::instructions::shared_accounts_exact_out_route_v2::SharedAccountsExactOutRouteV2 as carbon_core::borsh::BorshDeserialize>::try_from_slice(&ci.data[8..]) {
                                    detail["jupiter_decoded_kind"] = json!("shared_accounts_exact_out_route_v2");
                                    detail["jupiter_shared_accounts_exact_out_route_v2"] = json!({
                                        "id": ix.id,
                                        "out_amount": ix.out_amount.to_string(),
                                        "quoted_in_amount": ix.quoted_in_amount.to_string(),
                                        "slippage_bps": ix.slippage_bps,
                                        "platform_fee_bps": ix.platform_fee_bps,
                                        "positive_slippage_bps": ix.positive_slippage_bps,
                                        "route_plan_len": ix.route_plan.len(),
                                        "route_plan": ix.route_plan.iter().take(8).enumerate().map(|(i, s)| {
                                            let swap_dbg = format!("{:?}", s.swap);
                                            json!({
                                                "i": i,
                                                "swap": swap_dbg,
                                                "dex": Self::solana_jup_swap_dex_label(&swap_dbg),
                                                "direction": Self::solana_jup_swap_direction(&swap_dbg),
                                                "side": Self::solana_jup_swap_side(&swap_dbg),
                                                "bps": s.bps,
                                                "input_index": s.input_index,
                                                "output_index": s.output_index
                                            })
                                        }).collect::<Vec<Value>>()
                                    });
                                }
                            }

                            _ => {}
                        }
                    }
                }

                // Keep a short prefix for debugging/mapping
                detail["data_prefix_base64"] = json!(
                    base64::engine::general_purpose::STANDARD
                        .encode(ci.data.iter().take(16).copied().collect::<Vec<u8>>())
                );

                summary_lines.push(format!(
                    "Jupiter: Anchor ix (accounts={}, data_len={})",
                    ci.accounts.len(),
                    ci.data.len()
                ));

                if !jupiter_warned {
                    warnings.push(json!({
                        "kind": "jupiter_router",
                        "severity": "low",
                        "program": jupiter_v6_pid,
                        "note": "Jupiter router program invoked. Verify input/output amounts in wallet UI before signing."
                    }));
                    jupiter_warned = true;
                }
            } else if pid == compute_budget_pid {
                // ComputeBudget program has a 1-byte discriminator followed by LE bytes.
                let disc = ci.data.first().copied();
                match disc {
                    Some(2) => {
                        // SetComputeUnitLimit(u32)
                        let units = ci.data.get(1..5).and_then(|b| Some(u32::from_le_bytes(b.try_into().ok()?)));
                        if let Some(units) = units {
                            summary_lines.push(format!("ComputeBudget: CU limit = {}", units));
                            detail["kind"] = json!("compute_budget_set_cu_limit");
                            detail["units"] = json!(units);
                        } else {
                            summary_lines.push("ComputeBudget: CU limit (unable to decode)".to_string());
                            detail["kind"] = json!("compute_budget_set_cu_limit");
                        }
                    }
                    Some(3) => {
                        // SetComputeUnitPrice(u64)
                        let micro = ci
                            .data
                            .get(1..9)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        if let Some(micro) = micro {
                            summary_lines.push(format!(
                                "ComputeBudget: CU price = {} micro-lamports",
                                micro
                            ));
                            detail["kind"] = json!("compute_budget_set_cu_price");
                            detail["micro_lamports"] = json!(micro.to_string());
                        } else {
                            summary_lines.push(
                                "ComputeBudget: CU price (unable to decode)".to_string(),
                            );
                            detail["kind"] = json!("compute_budget_set_cu_price");
                        }
                    }
                    Some(1) => {
                        let bytes = ci.data.get(1..5).and_then(|b| Some(u32::from_le_bytes(b.try_into().ok()?)));
                        if let Some(bytes) = bytes {
                            summary_lines.push(format!("ComputeBudget: heap frame = {} bytes", bytes));
                            detail["kind"] = json!("compute_budget_request_heap_frame");
                            detail["bytes"] = json!(bytes);
                        } else {
                            summary_lines.push("ComputeBudget: heap frame (unable to decode)".to_string());
                            detail["kind"] = json!("compute_budget_request_heap_frame");
                        }
                    }
                    Some(4) => {
                        let bytes = ci.data.get(1..5).and_then(|b| Some(u32::from_le_bytes(b.try_into().ok()?)));
                        if let Some(bytes) = bytes {
                            summary_lines.push(format!(
                                "ComputeBudget: loaded accounts data limit = {} bytes",
                                bytes
                            ));
                            detail["kind"] = json!("compute_budget_set_loaded_accounts_data_size_limit");
                            detail["bytes"] = json!(bytes);
                        } else {
                            summary_lines.push(
                                "ComputeBudget: loaded accounts data limit (unable to decode)"
                                    .to_string(),
                            );
                            detail["kind"] = json!("compute_budget_set_loaded_accounts_data_size_limit");
                        }
                    }
                    _ => {
                        summary_lines.push("ComputeBudget instruction".to_string());
                        detail["kind"] = json!("compute_budget");
                    }
                }
            } else if pid == token_pid {
                // Legacy SPL Token Program

                if let Ok(tok_ix) = spl_token::instruction::TokenInstruction::unpack(&ci.data) {
                    match tok_ix {
                        spl_token::instruction::TokenInstruction::Transfer { amount } => {
                            // accounts: [source, destination, authority]
                            let source = key_at(&ci.accounts, 0);
                            let destination = key_at(&ci.accounts, 1);
                            let authority = key_at(&ci.accounts, 2);
                            summary_lines.push(format!(
                                "SPL Token transfer: {} -> {} (amount: {})",
                                source, destination, amount
                            ));
                            detail["kind"] = json!("spl_token_transfer");
                            detail["source"] = json!(source);
                            detail["destination"] = json!(destination);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                        }
                        spl_token::instruction::TokenInstruction::TransferChecked { amount, decimals } => {
                            // accounts: [source, mint, destination, authority]
                            let source = key_at(&ci.accounts, 0);
                            let mint = key_at(&ci.accounts, 1);
                            let destination = key_at(&ci.accounts, 2);
                            let authority = key_at(&ci.accounts, 3);
                            summary_lines.push(format!(
                                "SPL Token transfer_checked: {} -> {} (mint: {}, amount: {}, decimals: {})",
                                source, destination, mint, amount, decimals
                            ));
                            detail["kind"] = json!("spl_token_transfer_checked");
                            detail["source"] = json!(source);
                            detail["destination"] = json!(destination);
                            detail["mint"] = json!(mint);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                            detail["decimals"] = json!(decimals);
                        }
                        spl_token::instruction::TokenInstruction::Approve { amount } => {
                            // accounts: [source, delegate, authority]
                            let source = key_at(&ci.accounts, 0);
                            let delegate = key_at(&ci.accounts, 1);
                            let authority = key_at(&ci.accounts, 2);
                            let is_infinite = amount == u64::MAX;
                            summary_lines.push(format!(
                                "SPL Token approve{}: delegate {} on {} (amount: {})",
                                if is_infinite { " (infinite)" } else { "" },
                                delegate,
                                source,
                                amount
                            ));
                            detail["kind"] = json!("spl_token_approve");
                            detail["source"] = json!(source);
                            detail["delegate"] = json!(delegate);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                            detail["infinite"] = json!(is_infinite);

                            warnings.push(json!({
                                "kind": "token_approve",
                                "severity": if is_infinite { "high" } else { "medium" },
                                "infinite": is_infinite,
                                "amount": amount.to_string(),
                                "delegate": delegate,
                                "source": source,
                                "note": if is_infinite { "This looks like an infinite token approval." } else { "Token approval." }
                            }));
                        }
                        spl_token::instruction::TokenInstruction::ApproveChecked { amount, decimals } => {
                            // accounts: [source, mint, delegate, authority]
                            let source = key_at(&ci.accounts, 0);
                            let mint = key_at(&ci.accounts, 1);
                            let delegate = key_at(&ci.accounts, 2);
                            let authority = key_at(&ci.accounts, 3);
                            let is_infinite = amount == u64::MAX;
                            summary_lines.push(format!(
                                "SPL Token approve_checked{}: delegate {} on {} (mint: {}, amount: {}, decimals: {})",
                                if is_infinite { " (infinite)" } else { "" },
                                delegate,
                                source,
                                mint,
                                amount,
                                decimals
                            ));
                            detail["kind"] = json!("spl_token_approve_checked");
                            detail["source"] = json!(source);
                            detail["mint"] = json!(mint);
                            detail["delegate"] = json!(delegate);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                            detail["decimals"] = json!(decimals);
                            detail["infinite"] = json!(is_infinite);

                            warnings.push(json!({
                                "kind": "token_approve",
                                "severity": if is_infinite { "high" } else { "medium" },
                                "infinite": is_infinite,
                                "amount": amount.to_string(),
                                "delegate": delegate,
                                "source": source,
                                "note": if is_infinite { "This looks like an infinite token approval." } else { "Token approval." }
                            }));
                        }
                        spl_token::instruction::TokenInstruction::Revoke => {
                            // accounts: [source, authority]
                            let source = key_at(&ci.accounts, 0);
                            let authority = key_at(&ci.accounts, 1);
                            summary_lines.push(format!("SPL Token revoke: {}", source));
                            detail["kind"] = json!("spl_token_revoke");
                            detail["source"] = json!(source);
                            detail["authority"] = json!(authority);
                        }
                        spl_token::instruction::TokenInstruction::CloseAccount => {
                            // accounts: [account, destination, authority]
                            let account = key_at(&ci.accounts, 0);
                            let destination = key_at(&ci.accounts, 1);
                            let authority = key_at(&ci.accounts, 2);
                            summary_lines.push(format!(
                                "SPL Token close_account: {} -> {}",
                                account, destination
                            ));
                            detail["kind"] = json!("spl_token_close_account");
                            detail["account"] = json!(account);
                            detail["destination"] = json!(destination);
                            detail["authority"] = json!(authority);

                            warnings.push(json!({
                                "kind": "close_token_account",
                                "severity": "medium",
                                "account": account,
                                "destination": destination,
                                "note": "This transaction closes a token account."
                            }));
                        }
                        spl_token::instruction::TokenInstruction::SetAuthority { .. } => {
                            summary_lines.push("SPL Token set_authority".to_string());
                            detail["kind"] = json!("spl_token_set_authority");
                            warnings.push(json!({
                                "kind": "set_authority",
                                "severity": "high",
                                "note": "This transaction changes token authority (high risk)."
                            }));
                        }
                        _ => {}
                    }
                }
            } else if pid == token_2022_pid {
                // SPL Token-2022 Program
                if let Ok(tok_ix) = spl_token_2022::instruction::TokenInstruction::unpack(&ci.data) {
                    match tok_ix {
                        #[allow(deprecated)]
                        spl_token_2022::instruction::TokenInstruction::Transfer { amount } => {
                            let source = key_at(&ci.accounts, 0);
                            let destination = key_at(&ci.accounts, 1);
                            let authority = key_at(&ci.accounts, 2);
                            summary_lines.push(format!(
                                "SPL Token-2022 transfer: {} -> {} (amount: {})",
                                source, destination, amount
                            ));
                            detail["kind"] = json!("spl_token_2022_transfer");
                            detail["source"] = json!(source);
                            detail["destination"] = json!(destination);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                        }
                        spl_token_2022::instruction::TokenInstruction::TransferChecked { amount, decimals } => {
                            let source = key_at(&ci.accounts, 0);
                            let mint = key_at(&ci.accounts, 1);
                            let destination = key_at(&ci.accounts, 2);
                            let authority = key_at(&ci.accounts, 3);
                            summary_lines.push(format!(
                                "SPL Token-2022 transfer_checked: {} -> {} (mint: {}, amount: {}, decimals: {})",
                                source, destination, mint, amount, decimals
                            ));
                            detail["kind"] = json!("spl_token_2022_transfer_checked");
                            detail["source"] = json!(source);
                            detail["destination"] = json!(destination);
                            detail["mint"] = json!(mint);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                            detail["decimals"] = json!(decimals);
                        }
                        spl_token_2022::instruction::TokenInstruction::Approve { amount } => {
                            let source = key_at(&ci.accounts, 0);
                            let delegate = key_at(&ci.accounts, 1);
                            let authority = key_at(&ci.accounts, 2);
                            let is_infinite = amount == u64::MAX;
                            summary_lines.push(format!(
                                "SPL Token-2022 approve{}: delegate {} on {} (amount: {})",
                                if is_infinite { " (infinite)" } else { "" },
                                delegate,
                                source,
                                amount
                            ));
                            detail["kind"] = json!("spl_token_2022_approve");
                            detail["source"] = json!(source);
                            detail["delegate"] = json!(delegate);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                            detail["infinite"] = json!(is_infinite);

                            warnings.push(json!({
                                "kind": "token_approve",
                                "severity": if is_infinite { "high" } else { "medium" },
                                "infinite": is_infinite,
                                "amount": amount.to_string(),
                                "delegate": delegate,
                                "source": source,
                                "note": if is_infinite { "This looks like an infinite token approval." } else { "Token approval." }
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::ApproveChecked { amount, decimals } => {
                            let source = key_at(&ci.accounts, 0);
                            let mint = key_at(&ci.accounts, 1);
                            let delegate = key_at(&ci.accounts, 2);
                            let authority = key_at(&ci.accounts, 3);
                            let is_infinite = amount == u64::MAX;
                            summary_lines.push(format!(
                                "SPL Token-2022 approve_checked{}: delegate {} on {} (mint: {}, amount: {}, decimals: {})",
                                if is_infinite { " (infinite)" } else { "" },
                                delegate,
                                source,
                                mint,
                                amount,
                                decimals
                            ));
                            detail["kind"] = json!("spl_token_2022_approve_checked");
                            detail["source"] = json!(source);
                            detail["mint"] = json!(mint);
                            detail["delegate"] = json!(delegate);
                            detail["authority"] = json!(authority);
                            detail["amount"] = json!(amount.to_string());
                            detail["decimals"] = json!(decimals);
                            detail["infinite"] = json!(is_infinite);

                            warnings.push(json!({
                                "kind": "token_approve",
                                "severity": if is_infinite { "high" } else { "medium" },
                                "infinite": is_infinite,
                                "amount": amount.to_string(),
                                "delegate": delegate,
                                "source": source,
                                "note": if is_infinite { "This looks like an infinite token approval." } else { "Token approval." }
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::Revoke => {
                            let source = key_at(&ci.accounts, 0);
                            let authority = key_at(&ci.accounts, 1);
                            summary_lines.push(format!("SPL Token-2022 revoke: {}", source));
                            detail["kind"] = json!("spl_token_2022_revoke");
                            detail["source"] = json!(source);
                            detail["authority"] = json!(authority);
                        }
                        spl_token_2022::instruction::TokenInstruction::CloseAccount => {
                            let account = key_at(&ci.accounts, 0);
                            let destination = key_at(&ci.accounts, 1);
                            let authority = key_at(&ci.accounts, 2);
                            summary_lines.push(format!(
                                "SPL Token-2022 close_account: {} -> {}",
                                account, destination
                            ));
                            detail["kind"] = json!("spl_token_2022_close_account");
                            detail["account"] = json!(account);
                            detail["destination"] = json!(destination);
                            detail["authority"] = json!(authority);

                            warnings.push(json!({
                                "kind": "close_token_account",
                                "severity": "medium",
                                "account": account,
                                "destination": destination,
                                "note": "This transaction closes a token account."
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::SetAuthority { .. } => {
                            summary_lines.push("SPL Token-2022 set_authority".to_string());
                            detail["kind"] = json!("spl_token_2022_set_authority");
                            warnings.push(json!({
                                "kind": "set_authority",
                                "severity": "high",
                                "note": "This transaction changes token authority (high risk)."
                            }));
                        }
                        // Friendly handling for common Token-2022 extension prefixes / advanced instructions
                        spl_token_2022::instruction::TokenInstruction::TransferFeeExtension => {
                            // Extension prefix: cannot fully decode without additional parsing.
                            // Still: surface this clearly for end users.
                            let src = key_at(&ci.accounts, 0);
                            let mint = key_at(&ci.accounts, 1);
                            summary_lines.push(format!(
                                "SPL Token-2022: TransferFee extension (src: {}, mint: {})",
                                src, mint
                            ));
                            detail["kind"] = json!("spl_token_2022_transfer_fee_extension");
                            detail["source"] = json!(src);
                            detail["mint"] = json!(mint);
                            warnings.push(json!({
                                "kind": "token2022_transfer_fee",
                                "severity": "medium",
                                "source": src,
                                "mint": mint,
                                "note": "Token-2022 TransferFee may charge fees on transfers. Verify amounts and expected output."
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::TransferHookExtension => {
                            // Extension prefix: can trigger hooks (extra CPI). Show involved accounts.
                            let src = key_at(&ci.accounts, 0);
                            let mint = key_at(&ci.accounts, 1);
                            let dst = key_at(&ci.accounts, 2);
                            let authority = key_at(&ci.accounts, 3);
                            summary_lines.push(format!(
                                "SPL Token-2022: TransferHook extension ({} -> {}, mint: {})",
                                src, dst, mint
                            ));
                            detail["kind"] = json!("spl_token_2022_transfer_hook_extension");
                            detail["source"] = json!(src);
                            detail["destination"] = json!(dst);
                            detail["mint"] = json!(mint);
                            detail["authority"] = json!(authority);
                            warnings.push(json!({
                                "kind": "token2022_transfer_hook",
                                "severity": "high",
                                "source": src,
                                "destination": dst,
                                "mint": mint,
                                "note": "Token-2022 TransferHook can trigger extra program calls (hook). Review carefully."
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::Reallocate { extension_types } => {
                            let acct = key_at(&ci.accounts, 0);
                            let payer = key_at(&ci.accounts, 1);
                            let ext_names: Vec<String> = extension_types.iter().map(|e| format!("{:?}", e)).collect();
                            summary_lines.push(format!(
                                "SPL Token-2022: Reallocate account {} ({} extensions)",
                                acct,
                                ext_names.len()
                            ));
                            detail["kind"] = json!("spl_token_2022_reallocate");
                            detail["account"] = json!(acct);
                            detail["payer"] = json!(payer);
                            detail["extension_types"] = json!(ext_names);

                            warnings.push(json!({
                                "kind": "token2022_reallocate",
                                "severity": "medium",
                                "account": acct,
                                "payer": payer,
                                "note": "Token-2022 account reallocation changes account data size; may increase rent/lamports. Review extension types in details."
                            }));
                        }
                        // More Token-2022 extension prefixes (friendly summaries)
                        spl_token_2022::instruction::TokenInstruction::MemoTransferExtension => {
                            summary_lines.push("SPL Token-2022: MemoTransfer extension".to_string());
                            detail["kind"] = json!("spl_token_2022_memo_transfer_extension");
                            warnings.push(json!({
                                "kind": "token2022_memo_transfer",
                                "severity": "low",
                                "note": "Token-2022 MemoTransfer may require memos on inbound transfers."
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::CpiGuardExtension => {
                            summary_lines.push("SPL Token-2022: CpiGuard extension".to_string());
                            detail["kind"] = json!("spl_token_2022_cpi_guard_extension");
                            warnings.push(json!({
                                "kind": "token2022_cpi_guard",
                                "severity": "medium",
                                "note": "Token-2022 CpiGuard restricts privileged ops via CPI; transfers may fail depending on context."
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::MetadataPointerExtension => {
                            summary_lines.push("SPL Token-2022: MetadataPointer extension".to_string());
                            detail["kind"] = json!("spl_token_2022_metadata_pointer_extension");
                        }
                        spl_token_2022::instruction::TokenInstruction::GroupPointerExtension => {
                            summary_lines.push("SPL Token-2022: GroupPointer extension".to_string());
                            detail["kind"] = json!("spl_token_2022_group_pointer_extension");
                        }
                        spl_token_2022::instruction::TokenInstruction::GroupMemberPointerExtension => {
                            summary_lines.push("SPL Token-2022: GroupMemberPointer extension".to_string());
                            detail["kind"] = json!("spl_token_2022_group_member_pointer_extension");
                        }
                        spl_token_2022::instruction::TokenInstruction::DefaultAccountStateExtension => {
                            summary_lines.push("SPL Token-2022: DefaultAccountState extension".to_string());
                            detail["kind"] = json!("spl_token_2022_default_account_state_extension");
                        }
                        spl_token_2022::instruction::TokenInstruction::InterestBearingMintExtension => {
                            summary_lines.push("SPL Token-2022: InterestBearing extension".to_string());
                            detail["kind"] = json!("spl_token_2022_interest_bearing_extension");
                        }
                        spl_token_2022::instruction::TokenInstruction::PausableExtension => {
                            summary_lines.push("SPL Token-2022: Pausable extension".to_string());
                            detail["kind"] = json!("spl_token_2022_pausable_extension");
                            warnings.push(json!({
                                "kind": "token2022_pausable",
                                "severity": "medium",
                                "note": "Token-2022 Pausable mint can pause transfers/minting; transfers may fail if paused."
                            }));
                        }
                        spl_token_2022::instruction::TokenInstruction::ConfidentialTransferExtension => {
                            summary_lines.push("SPL Token-2022: ConfidentialTransfer extension".to_string());
                            detail["kind"] = json!("spl_token_2022_confidential_transfer_extension");
                            warnings.push(json!({
                                "kind": "token2022_confidential_transfer",
                                "severity": "medium",
                                "note": "Token-2022 ConfidentialTransfer involves encrypted balances; preview may be incomplete."
                            }));
                        }
                        _ => {
                            // Many Token-2022 extensions exist; keep a generic line.
                            summary_lines.push("SPL Token-2022 instruction".to_string());
                            detail["kind"] = json!("spl_token_2022");
                        }
                    }
                } else {
                    summary_lines.push("SPL Token-2022 instruction (unable to decode)".to_string());
                    detail["kind"] = json!("spl_token_2022");
                }
            } else if pid == ata_pid {
                // Typically: create associated token account
                // accounts: [payer, ata, owner, mint, system, token, rent] (+ remaining)
                let payer = key_at(&ci.accounts, 0);
                let ata = key_at(&ci.accounts, 1);
                let owner = key_at(&ci.accounts, 2);
                let mint = key_at(&ci.accounts, 3);
                summary_lines.push(format!(
                    "Create ATA: {} (owner: {}, mint: {})",
                    ata, owner, mint
                ));
                detail["kind"] = json!("create_ata");
                detail["payer"] = json!(payer);
                detail["ata"] = json!(ata);
                detail["owner"] = json!(owner);
                detail["mint"] = json!(mint);
            } else if pid == system_pid {
                // Decode a subset of SystemProgram instructions (transfer/create/assign).
                let sys = ci.data.as_slice();
                let discr = sys
                    .get(0..4)
                    .and_then(|b| Some(u32::from_le_bytes(b.try_into().ok()?)));

                match discr {
                    Some(2) => {
                        // Transfer { lamports: u64 }
                        let lamports = sys
                            .get(4..12)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        let from = key_at(&ci.accounts, 0);
                        let to = key_at(&ci.accounts, 1);
                        if let Some(lamports) = lamports {
                            summary_lines.push(format!(
                                "SOL transfer: {} -> {} (lamports: {})",
                                from, to, lamports
                            ));
                            detail["kind"] = json!("system_transfer");
                            detail["from"] = json!(from);
                            detail["to"] = json!(to);
                            detail["lamports"] = json!(lamports.to_string());
                        } else {
                            summary_lines.push("SOL transfer (unable to decode amount)".to_string());
                            detail["kind"] = json!("system_transfer");
                        }
                    }
                    Some(0) => {
                        // CreateAccount { lamports: u64, space: u64, owner: Pubkey }
                        let lamports = sys
                            .get(4..12)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        let space = sys
                            .get(12..20)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        let owner = sys.get(20..52).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });
                        let payer = key_at(&ci.accounts, 0);
                        let new_account = key_at(&ci.accounts, 1);

                        summary_lines.push(format!(
                            "Create account: {} (payer: {})",
                            new_account, payer
                        ));
                        detail["kind"] = json!("system_create_account");
                        detail["payer"] = json!(payer);
                        detail["new_account"] = json!(new_account);
                        if let Some(l) = lamports {
                            detail["lamports"] = json!(l.to_string());
                        }
                        if let Some(s) = space {
                            detail["space"] = json!(s.to_string());
                        }
                        if let Some(o) = owner {
                            detail["owner"] = json!(o);
                        }
                    }
                    Some(1) => {
                        // Assign { owner: Pubkey }
                        let owner = sys.get(4..36).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });
                        let acct = key_at(&ci.accounts, 0);
                        summary_lines.push(format!(
                            "Assign account owner: {} -> {:?}",
                            acct, owner
                        ));
                        detail["kind"] = json!("system_assign");
                        detail["account"] = json!(acct);
                        if let Some(o) = owner {
                            detail["owner"] = json!(o);
                        }
                        warnings.push(json!({
                            "kind": "system_assign",
                            "severity": "high",
                            "note": "This transaction assigns an account to a new program owner (high risk)."
                        }));
                    }
                    Some(3) => {
                        // CreateAccountWithSeed { base: Pubkey, seed: String, lamports: u64, space: u64, owner: Pubkey }
                        // Layout: u32 discr (already), base(32), seed_len(u64), seed_bytes, lamports(u64), space(u64), owner(32)
                        let mut off = 4;
                        let base = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });
                        off += 32;
                        let seed_len = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)))
                            .unwrap_or(0) as usize;
                        off += 8;
                        let seed = sys
                            .get(off..off + seed_len)
                            .and_then(|b| std::str::from_utf8(b).ok())
                            .map(|s| s.to_string());
                        off += seed_len;
                        let lamports = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        off += 8;
                        let space = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        off += 8;
                        let owner = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });

                        let payer = key_at(&ci.accounts, 0);
                        let created = key_at(&ci.accounts, 1);
                        summary_lines.push(format!(
                            "Create account (with seed): {} (payer: {})",
                            created, payer
                        ));
                        detail["kind"] = json!("system_create_account_with_seed");
                        detail["payer"] = json!(payer);
                        detail["created"] = json!(created);
                        detail["base"] = json!(base);
                        detail["seed"] = json!(seed);
                        if let Some(l) = lamports {
                            detail["lamports"] = json!(l.to_string());
                        }
                        if let Some(s) = space {
                            detail["space"] = json!(s.to_string());
                        }
                        if let Some(o) = owner {
                            detail["owner"] = json!(o);
                        }
                    }
                    Some(8) => {
                        // Allocate { space: u64 }
                        let space = sys
                            .get(4..12)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        let acct = key_at(&ci.accounts, 0);
                        summary_lines.push(format!(
                            "Allocate account space: {} (space: {:?})",
                            acct, space
                        ));
                        detail["kind"] = json!("system_allocate");
                        detail["account"] = json!(acct);
                        if let Some(s) = space {
                            detail["space"] = json!(s.to_string());
                        }
                    }
                    Some(9) => {
                        // AllocateWithSeed { base: Pubkey, seed: String, space: u64, owner: Pubkey }
                        let mut off = 4;
                        let base = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });
                        off += 32;
                        let seed_len = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)))
                            .unwrap_or(0) as usize;
                        off += 8;
                        let seed = sys
                            .get(off..off + seed_len)
                            .and_then(|b| std::str::from_utf8(b).ok())
                            .map(|s| s.to_string());
                        off += seed_len;
                        let space = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        off += 8;
                        let owner = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });

                        let acct = key_at(&ci.accounts, 0);
                        summary_lines.push(format!(
                            "Allocate with seed: {} (space: {:?})",
                            acct, space
                        ));
                        detail["kind"] = json!("system_allocate_with_seed");
                        detail["account"] = json!(acct);
                        detail["base"] = json!(base);
                        detail["seed"] = json!(seed);
                        if let Some(s) = space {
                            detail["space"] = json!(s.to_string());
                        }
                        if let Some(o) = owner {
                            detail["owner"] = json!(o);
                        }
                    }
                    Some(10) => {
                        // AssignWithSeed { base: Pubkey, seed: String, owner: Pubkey }
                        let mut off = 4;
                        let base = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });
                        off += 32;
                        let seed_len = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)))
                            .unwrap_or(0) as usize;
                        off += 8;
                        let seed = sys
                            .get(off..off + seed_len)
                            .and_then(|b| std::str::from_utf8(b).ok())
                            .map(|s| s.to_string());
                        off += seed_len;
                        let owner = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });

                        let acct = key_at(&ci.accounts, 0);
                        summary_lines.push(format!(
                            "Assign with seed: {} -> {:?}",
                            acct, owner
                        ));
                        detail["kind"] = json!("system_assign_with_seed");
                        detail["account"] = json!(acct);
                        detail["base"] = json!(base);
                        detail["seed"] = json!(seed);
                        if let Some(o) = owner {
                            detail["owner"] = json!(o);
                        }
                        warnings.push(json!({
                            "kind": "system_assign",
                            "severity": "high",
                            "note": "This transaction assigns an account to a new program owner (high risk)."
                        }));
                    }
                    Some(11) => {
                        // TransferWithSeed { lamports: u64, from_seed: String, from_owner: Pubkey }
                        let mut off = 4;
                        let lamports = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)));
                        off += 8;
                        let seed_len = sys
                            .get(off..off + 8)
                            .and_then(|b| Some(u64::from_le_bytes(b.try_into().ok()?)))
                            .unwrap_or(0) as usize;
                        off += 8;
                        let from_seed = sys
                            .get(off..off + seed_len)
                            .and_then(|b| std::str::from_utf8(b).ok())
                            .map(|s| s.to_string());
                        off += seed_len;
                        let from_owner = sys.get(off..off + 32).and_then(|b| {
                            let arr: [u8; 32] = b.try_into().ok()?;
                            Some(solana_sdk::pubkey::Pubkey::new_from_array(arr).to_string())
                        });

                        let from = key_at(&ci.accounts, 0);
                        let base = key_at(&ci.accounts, 1);
                        let to = key_at(&ci.accounts, 2);
                        summary_lines.push(format!(
                            "SOL transfer (with seed): {} -> {} (lamports: {:?})",
                            from, to, lamports
                        ));
                        detail["kind"] = json!("system_transfer_with_seed");
                        detail["from"] = json!(from);
                        detail["to"] = json!(to);
                        detail["base"] = json!(base);
                        detail["from_seed"] = json!(from_seed);
                        detail["from_owner"] = json!(from_owner);
                        if let Some(l) = lamports {
                            detail["lamports"] = json!(l.to_string());
                        }
                    }
                    _ => {
                        if let Some(d) = discr {
                            summary_lines.push(format!("System Program instruction (discriminant={})", d));
                            detail["kind"] = json!("system_program_unknown");
                            detail["discriminant"] = json!(d);
                        } else {
                            summary_lines.push("System Program instruction".to_string());
                            detail["kind"] = json!("system_program_unknown");
                        }

                        warnings.push(json!({
                            "kind": "system_program",
                            "severity": "low",
                            "note": "System Program instruction was not fully decoded. Review details before confirming."
                        }));
                    }
                }
            }

            details_instructions.push(detail);
        }

        // Post-process summary_lines: compact noisy lines (esp. ComputeBudget)
        {
            let mut cu_limit: Option<String> = None;
            let mut cu_price: Option<String> = None;
            let mut heap: Option<String> = None;
            let mut data_limit: Option<String> = None;

            let mut out: Vec<String> = Vec::new();
            for s in summary_lines.into_iter() {
                if let Some(v) = s.strip_prefix("ComputeBudget: CU limit = ") {
                    cu_limit = Some(v.trim().to_string());
                    continue;
                }
                if let Some(v) = s.strip_prefix("ComputeBudget: CU price = ") {
                    // Keep only the number (drop trailing unit if present)
                    cu_price = Some(v.replace(" micro-lamports", "").trim().to_string());
                    continue;
                }
                if let Some(v) = s.strip_prefix("ComputeBudget: heap frame = ") {
                    heap = Some(v.trim().to_string());
                    continue;
                }
                if let Some(v) = s.strip_prefix("ComputeBudget: loaded accounts data limit = ") {
                    data_limit = Some(v.trim().to_string());
                    continue;
                }
                if s.starts_with("ComputeBudget") {
                    // Drop other compute budget noise (unable to decode etc.)
                    continue;
                }

                // De-dupe exact duplicates while preserving order
                if !out.contains(&s) {
                    out.push(s);
                }
            }

            let mut cb_parts: Vec<String> = Vec::new();
            if let Some(v) = cu_limit {
                cb_parts.push(format!("cu_limit={}", v));
            }
            if let Some(v) = cu_price {
                cb_parts.push(format!("cu_price_micro_lamports={}", v));
            }
            if let Some(v) = heap {
                cb_parts.push(format!("heap_frame={}", v));
            }
            if let Some(v) = data_limit {
                cb_parts.push(format!("loaded_accounts_data_limit={}", v));
            }
            if !cb_parts.is_empty() {
                out.insert(0, format!("ComputeBudget: {}", cb_parts.join(", ")));
            }

            // Unknown programs warning (wallet-like)
            if !program_ids_unknown.is_empty() {
                // show up to 5, rest in details
                let shown: Vec<String> = program_ids_unknown.iter().take(5).cloned().collect();
                let more = program_ids_unknown.len().saturating_sub(shown.len());

                let shown_pretty: Vec<String> = shown
                    .iter()
                    .map(|p| {
                        let label = Self::solana_known_program_label(p);
                        if let Some(l) = label {
                            // compact display like "Orca Whirlpool(whirL...)"
                            let short = if p.len() > 8 {
                                format!("{}...", &p[..5])
                            } else {
                                p.clone()
                            };
                            format!("{}({})", l, short)
                        } else {
                            p.clone()
                        }
                    })
                    .collect();

                let line = if more > 0 {
                    format!("Unknown programs: {} (+{} more)", shown_pretty.join(", "), more)
                } else {
                    format!("Unknown programs: {}", shown_pretty.join(", "))
                };
                out.push(line);

                let labeled: Vec<Value> = program_ids_unknown
                    .iter()
                    .map(|p| {
                        json!({
                            "pubkey": p,
                            "label": Self::solana_known_program_label(p)
                        })
                    })
                    .collect();

                warnings.push(json!({
                    "kind": "unknown_program",
                    "severity": "high",
                    "count": program_ids_unknown.len(),
                    "program_ids": program_ids_unknown,
                    "programs": labeled,
                    "note": "This transaction calls one or more unknown programs. Only confirm if you trust the source and understand what it does."
                }));
            }

            summary_lines = out;
        }

        // Store pending confirmation (5min default)
        let created = crate::utils::solana_confirm_store::now_ms();
        let ttl_default = 5 * 60 * 1000;
        let ttl = request
            .confirm_ttl_ms
            .unwrap_or(ttl_default)
            .min(15 * 60 * 1000);
        let expires = created + ttl;

        let id_seed = format!("{}:{}", created, hash);
        let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
        let confirmation_id = format!("solana_preview_{}", &id_suffix[..16]);

        let summary = json!({
            "network": network_str,
            "rpc_url": rpc_url,
            "commitment": commitment,
            "sig_verify": sig_verify,
            "replace_recent_blockhash": replace,
            "simulate_retry": {
                "used": retry_used,
                "error": retry_error
            },
            "tx_bytes_len": tx_bytes.len(),
            "tx_version": tx_version,
            "address_table_lookups": address_table_lookups,
            "program_ids": program_ids,
            "programs_labeled": program_ids.iter().map(|p| json!({
                "pubkey": p,
                "label": Self::solana_known_program_label(p)
            })).collect::<Vec<Value>>(),
            "program_ids_unknown": program_ids_unknown,
            "summary_lines": summary_lines,
            "risk_warnings": warnings,
            "details": {
                "instructions": details_instructions
            },
            "suggestions": {
                "compute_unit_limit": suggested_cu_limit,
                "compute_unit_price_micro_lamports": suggested_cu_price,
                "recent_prioritization_fees": price_sample
            }
        });

        crate::utils::solana_confirm_store::insert_pending(
            &confirmation_id,
            &tx_base64,
            created,
            expires,
            &hash,
            "solana_tx_preview",
            Some(summary.clone()),
        )?;

        let confirm_timeout_ms = request.confirm_timeout_ms.unwrap_or(60_000);
        let confirm_skip_preflight = request.confirm_skip_preflight.unwrap_or(false);

        let response = Self::pretty_json(&json!({
            "ok": true,
            "stage": "preview",
            "status": "preview",
            "rpc_url": rpc_url,
            "network": network_str,
            "tx_version": tx_version,
            "address_table_lookups": address_table_lookups,

            // Compatibility + unified naming
            "confirmation_id": confirmation_id,
            "pending_confirmation_id": confirmation_id,

            "tx_summary_hash": hash,
            "expires_in_ms": ttl,
            "confirmation": {
                "tool": "solana_confirm_transaction",
                "args": {
                    "id": confirmation_id,
                    "hash": hash,
                    "network": network_str,
                    "commitment": commitment,
                    "timeout_ms": confirm_timeout_ms,
                    "skip_preflight": confirm_skip_preflight
                }
            },
            "transaction_base64": tx_base64,
            "context": sim.context,
            "retry": {
                "used": retry_used,
                "error": retry_error
            },
            "value": sim.value,
            "preview": {
                "summary_lines": summary.get("summary_lines"),
                "risk_warnings": summary.get("risk_warnings"),
                "program_ids": summary.get("program_ids"),
                "details": summary.get("details")
            },
            "suggestions": summary.get("suggestions")
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn solana_is_mainnet_network(network: Option<&str>) -> bool {
        match network.map(|s| s.trim().to_lowercase()) {
            None => true, // default is mainnet
            Some(s) if s.is_empty() => true,
            Some(s) if s == "mainnet" || s == "mainnet-beta" => true,
            _ => false,
        }
    }

    #[tool(description = "Solana: build a native SOL transfer transaction (returns transaction_base64; does not broadcast)")]
    async fn solana_build_transfer(
        &self,
        Parameters(request): Parameters<SolanaBuildTransferRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let rpc_url = Self::solana_rpc_url_for_network(network)?;
        let client = Self::solana_rpc(network)?;

        let sender = solana_sdk::pubkey::Pubkey::from_str(request.sender.trim()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid sender pubkey: {}", e)),
            data: Some(json!({"sender": request.sender})),
        })?;
        let recipient = solana_sdk::pubkey::Pubkey::from_str(request.recipient.trim()).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid recipient pubkey: {}", e)),
            data: Some(json!({"recipient": request.recipient})),
        })?;

        let lamports: u64 = request.lamports.trim().parse().map_err(|_| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("lamports must be a u64 integer string"),
            data: Some(json!({"provided": request.lamports})),
        })?;

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            solana_sdk::pubkey::Pubkey::from_str(fp.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid fee_payer pubkey: {}", e)),
                data: Some(json!({"fee_payer": fp})),
            })?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            sender
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_build_transfer", e))?
        };

        let ix = solana_system_interface::instruction::transfer(&sender, &recipient, lamports);
        let msg = solana_sdk::message::Message::new(&[ix], Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(msg);
        tx.message.recent_blockhash = recent_blockhash;

        if let Some(ref k) = kp {
            tx.try_sign(&[k], recent_blockhash).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to sign tx: {}", e)),
                data: None,
            })?;
        }

        let bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize tx: {}", e)),
            data: None,
        })?;

        let tx_b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": request.network.clone().unwrap_or("mainnet".to_string()),
            "fee_payer": fee_payer.to_string(),
            "sender": sender.to_string(),
            "recipient": recipient.to_string(),
            "lamports": lamports,
            "signed": sign,
            "transaction_base64": tx_b64,
            "tx_bytes_len": bytes.len(),
            "note": "Use solana_send_transaction(confirm=false) to create a pending confirmation; then solana_confirm_transaction to broadcast (mainnet requires confirm_token)."
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: send a transaction (safe default: creates pending confirmation unless confirm=true)")]
    async fn solana_send_transaction(
        &self,
        Parameters(request): Parameters<SolanaSendTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref();
        let rpc_url = Self::solana_rpc_url_for_network(network)?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(request.transaction_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction_base64: {}", e)),
                data: None,
            })?;

        let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

        // Mainnet safety: even if confirm=true, do not directly broadcast from this tool.
        // Instead, create a pending confirmation and require a second-step confirm_token.
        if request.confirm.unwrap_or(false) && Self::solana_is_mainnet_network(network) {
            // Force safe default path.
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": request.network.clone().unwrap_or("mainnet".to_string()),
                "rpc_url": rpc_url,
                "tx_bytes_len": tx_bytes.len(),
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                request.transaction_base64.trim(),
                created,
                expires,
                &hash,
                "solana_send_transaction",
                Some(summary.clone()),
            )?;

            let token = crate::utils::solana_confirm_store::make_confirm_token(&confirmation_id, &hash);

            let response = Self::pretty_json(&json!({
                "ok": true,
                "stage": "send",
                "status": "pending",
                "rpc_url": rpc_url,
                "network": request.network.clone().unwrap_or("mainnet".to_string()),
                "pending_confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "confirm_token": token,
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Mainnet tx created. Broadcast requires explicit solana_confirm_transaction with confirm_token.",
                "next": {
                    "confirm": {
                        "tool": "solana_confirm_transaction",
                        "args": {
                            "id": confirmation_id,
                            "hash": hash,
                            "confirm_token": token,
                            "commitment": request.commitment.clone().unwrap_or("confirmed".to_string())
                        }
                    },
                    "how_to_confirm": format!(
                        "solana_confirm_transaction id:{} hash:{} confirm_token:{}",
                        confirmation_id, hash, token
                    )
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        if request.confirm.unwrap_or(false) && !request.allow_direct_send.unwrap_or(false) {
            return Self::guard_result(
                "solana_send_transaction",
                "SAFETY_GUARD_BLOCKED",
                "Direct broadcast is blocked by default",
                false,
                Some("Use confirm=false to create a pending confirmation, then solana_confirm_transaction (mainnet requires confirm_token); or set allow_direct_send=true only if you understand the risks"),
                Some(json!({
                    "tool": "solana_send_transaction",
                    "args": {
                        "network": request.network.clone().unwrap_or("mainnet".to_string()),
                        // Clone to avoid moving out of request.
                        "transaction_base64": request.transaction_base64.clone(),
                        "confirm": false
                    }
                })),
                Some(json!({
                    "tool_preview": "solana_tx_preview",
                    "tool_confirm": "solana_confirm_transaction",
                    "param": "allow_direct_send"
                })),
            );
        }

        if !request.confirm.unwrap_or(false) {
            // Safe default: do not broadcast.
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": request.network.clone().unwrap_or("mainnet".to_string()),
                "rpc_url": rpc_url,
                "tx_bytes_len": tx_bytes.len(),
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                request.transaction_base64.trim(),
                created,
                expires,
                &hash,
                "solana_send_transaction",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "ok": true,
                "stage": "send",
                "status": "pending",
                "rpc_url": rpc_url,
                "network": request.network.clone().unwrap_or("mainnet".to_string()),
                "pending_confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "summary": summary,
                "expires_in_ms": ttl,
                "note": "Not broadcast. Call solana_confirm_transaction to broadcast and wait.",
                "next": {
                    "confirm": {
                        "tool": "solana_confirm_transaction",
                        "args": {
                            "id": confirmation_id,
                            "hash": hash,
                            "commitment": request.commitment.clone().unwrap_or("confirmed".to_string())
                        }
                    },
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        let client = Self::solana_rpc(network)?;

        let mut tx: solana_sdk::transaction::Transaction =
            bincode::deserialize(&tx_bytes).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid transaction bytes: {}", e)),
                data: None,
            })?;

        // Try to sign if needed and keypair is available.
        let kp = Self::solana_keypair_path()
            .ok()
            .and_then(|p| Self::solana_read_keypair_from_json_file(&p).ok());
        Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());

        
        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let sig = client
            .send_transaction_with_config(
                &tx,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(request.commitment.as_deref())?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| {
                let msg = e.to_string();
                let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                ErrorData {
                    code: ErrorCode(-32000),
                    message: Cow::from(format!("solana_send_transaction send error: {}", msg)),
                    data: Some(json!({
                        "error_class": error_class,
                        "suggest_fix": suggest_fix,
                        "skip_preflight": skip_preflight
                    })),
                }
            })?;

        let timeout_ms = request.timeout_ms.unwrap_or(60_000);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms)
            .await
            .map_err(|e| {
                let msg = e.message.to_string();
                let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                ErrorData {
                    code: e.code,
                    message: e.message,
                    data: Some(json!({
                        "error_class": error_class,
                        "suggest_fix": suggest_fix,
                        "timeout_ms": timeout_ms
                    })),
                }
            })?;

        let status = waited
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");

        let response = Self::pretty_json(&json!({
            "ok": true,
            "stage": "send",
            "status": status,
            "rpc_url": rpc_url,
            "network": request.network.unwrap_or("mainnet".to_string()),
            "signature": sig.to_string(),
            "tx_summary_hash": hash,
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: list pending confirmations (file-backed)")]
    async fn solana_list_pending_confirmations(
        &self,
        Parameters(request): Parameters<SolanaListPendingConfirmationsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // Best-effort cleanup of expired
        let _ = crate::utils::solana_confirm_store::cleanup_expired();

        let status = request.status.as_deref().map(|s| s.trim().to_lowercase());
        if let Some(st) = status.as_deref() {
            let allowed = ["pending"];
            if !allowed.contains(&st) {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("status must be: pending"),
                    data: None,
                });
            }
        }

        let include_summary = request.include_summary.unwrap_or(true);
        let limit = request.limit.unwrap_or(20).min(200);
        let now = crate::utils::solana_confirm_store::now_ms();

        let mut items: Vec<Value> = Vec::new();
        let all = crate::utils::solana_confirm_store::list_pending()?;
        for p in all.into_iter().take(limit) {
            items.push(json!({
                "id": p.id,
                "created_ms": p.created_ms,
                "expires_ms": p.expires_ms,
                "expires_in_ms": p.expires_ms.saturating_sub(now),
                "tx_summary_hash": p.tx_summary_hash,
                "source_tool": p.source_tool,
                "status": "pending",
                "summary": if include_summary { p.summary } else { None }
            }));
        }

        let response = Self::pretty_json(&json!({
            "store_path": crate::utils::solana_confirm_store::store_path().to_string_lossy(),
            "count": items.len(),
            "items": items,
            "note": "Use solana_get_pending_confirmation for full record; use solana_confirm_transaction to broadcast."
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: get a pending confirmation by id (file-backed)")]
    async fn solana_get_pending_confirmation(
        &self,
        Parameters(request): Parameters<SolanaGetPendingConfirmationRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let _ = crate::utils::solana_confirm_store::cleanup_expired();
        let p = crate::utils::solana_confirm_store::get_pending(request.id.trim())?;
        let now = crate::utils::solana_confirm_store::now_ms();

        let response = Self::pretty_json(&json!({
            "store_path": crate::utils::solana_confirm_store::store_path().to_string_lossy(),
            "item": {
                "id": p.id,
                "created_ms": p.created_ms,
                "expires_ms": p.expires_ms,
                "expires_in_ms": p.expires_ms.saturating_sub(now),
                "tx_summary_hash": p.tx_summary_hash,
                "source_tool": p.source_tool,
                "status": "pending",
                "summary": p.summary,
                "tx_base64": p.tx_base64
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: cleanup pending confirmations (file-backed)")]
    async fn solana_cleanup_pending_confirmations(
        &self,
        Parameters(request): Parameters<SolanaCleanupPendingConfirmationsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let now = crate::utils::solana_confirm_store::now_ms();
        let res = crate::utils::solana_confirm_store::cleanup(request.delete_older_than_ms, now)?;

        let response = Self::pretty_json(&json!({
            "store_path": crate::utils::solana_confirm_store::store_path().to_string_lossy(),
            "result": res
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Solana: confirm and broadcast a pending transaction created by solana_send_transaction")]
    async fn solana_confirm_transaction(
        &self,
        Parameters(request): Parameters<SolanaConfirmTransactionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // Best-effort cleanup
        let _ = crate::utils::solana_confirm_store::cleanup_expired();

        let pending = crate::utils::solana_confirm_store::get_pending(&request.id)?;
        if pending.tx_summary_hash != request.hash {
            return Self::guard_result(
                "solana_confirm_transaction",
                "TX_SUMMARY_HASH_MISMATCH",
                "Hash mismatch for confirmation id",
                false,
                Some("Use the tx_summary_hash returned by solana_send_transaction for this confirmation id"),
                Some(json!({
                    "tool": "solana_confirm_transaction",
                    "args": {
                        "id": request.id.clone(),
                        "hash": pending.tx_summary_hash.clone(),
                        "confirm_token": request.confirm_token.clone(),
                        "network": request.network.clone()
                    }
                })),
                Some(json!({
                    "expected": pending.tx_summary_hash,
                    "provided": request.hash
                })),
            );
        }

        let network = request
            .network
            .clone()
            .or_else(|| {
                pending
                    .summary
                    .as_ref()
                    .and_then(|v| v.get("network").and_then(|x| x.as_str()).map(|s| s.to_string()))
            })
            .unwrap_or("mainnet".to_string());

        // Hard guard: if approval says blocked, require a whitelisted admin pubkey,
        // and require that the tx fee_payer (and best-effort authorities) match that pubkey.
        // This makes the override chain-verifiable (the tx must be signed by that fee_payer).
        let approval_status = pending
            .summary
            .as_ref()
            .and_then(|s| s.get("approval"))
            .and_then(|a| a.get("status"))
            .and_then(Value::as_str)
            .unwrap_or("");

        let admin_pubkey_str = request.admin_pubkey.as_deref().unwrap_or("").trim();

        if approval_status == "blocked" {
            let wl_raw = std::env::var("W3RT_SOLANA_BLOCKED_CONFIRM_ADMIN_PUBKEY_WHITELIST")
                .unwrap_or_default();
            let wl: std::collections::HashSet<String> = wl_raw
                .split(',')
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string())
                .collect();

            if wl.is_empty() || admin_pubkey_str.is_empty() || !wl.contains(admin_pubkey_str) {
                return Self::guard_result(
                    "solana_confirm_transaction",
                    "APPROVAL_BLOCKED",
                    "Confirmation is blocked by approval policy",
                    false,
                    Some("This pending transaction was marked blocked. Provide admin_pubkey that is in W3RT_SOLANA_BLOCKED_CONFIRM_ADMIN_PUBKEY_WHITELIST."),
                    None,
                    Some(json!({
                        "approval_status": approval_status,
                        "whitelist_env": "W3RT_SOLANA_BLOCKED_CONFIRM_ADMIN_PUBKEY_WHITELIST"
                    })),
                );
            }
        }

        // Mainnet safety: require a confirm_token.
        if Self::solana_is_mainnet_network(Some(&network)) {
            let expected = crate::utils::solana_confirm_store::make_confirm_token(&request.id, &request.hash);
            if request.confirm_token.as_deref() != Some(expected.as_str()) {
                return Self::guard_result(
                    "solana_confirm_transaction",
                    "CONFIRM_TOKEN_REQUIRED",
                    "Mainnet confirmation requires confirm_token",
                    false,
                    Some("Re-run solana_confirm_transaction with the expected confirm_token"),
                    Some(json!({
                        "tool": "solana_confirm_transaction",
                        "args": {
                            "id": request.id,
                            "hash": request.hash,
                            "confirm_token": expected,
                            "network": network
                        }
                    })),
                    Some(json!({
                        "expected_confirm_token": expected,
                        "how_to_confirm": format!(
                            "solana_confirm_transaction id:{} hash:{} confirm_token:{}",
                            request.id, request.hash, expected
                        )
                    })),
                );
            }
        }

        let rpc_url = Self::solana_rpc_url_for_network(Some(&network))?;
        let client = Self::solana_rpc(Some(&network))?;

        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(pending.tx_base64.trim())
            .map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid stored tx_base64: {}", e)),
                data: None,
            })?;

        // Decode as VersionedTransaction (v0+LUT) if possible; otherwise fall back to legacy Transaction.
        let vtx: Option<solana_transaction::versioned::VersionedTransaction> =
            bincode::deserialize(&tx_bytes).ok();

        // Helper: resolve full account keys for v0 transactions (includes LUT accounts).
        async fn solana_resolve_account_keys_for_confirm(
            client: &solana_client::nonblocking::rpc_client::RpcClient,
            vtx: &Option<solana_transaction::versioned::VersionedTransaction>,
            tx_bytes: &[u8],
        ) -> Result<
            (
                Vec<solana_sdk::pubkey::Pubkey>,
                Vec<solana_message::compiled_instruction::CompiledInstruction>,
                Option<solana_sdk::pubkey::Pubkey>,
            ),
            ErrorData,
        > {
            if let Some(v) = vtx.as_ref() {
                match &v.message {
                    solana_message::VersionedMessage::Legacy(msg) => {
                        let fp = msg.account_keys.first().cloned();
                        return Ok((msg.account_keys.clone(), msg.instructions.clone(), fp));
                    }
                    solana_message::VersionedMessage::V0(msg) => {
                        let mut keys = msg.account_keys.clone();
                        let fp = keys.first().cloned();

                        let mut loaded_writable: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();
                        let mut loaded_readonly: Vec<solana_sdk::pubkey::Pubkey> = Vec::new();

                        for l in &msg.address_table_lookups {
                            let lut_addr = l.account_key;
                            let addresses: Vec<solana_sdk::pubkey::Pubkey> = match client.get_account(&lut_addr).await {
                                Ok(a) => solana_address_lookup_table_interface::state::AddressLookupTable::deserialize(&a.data)
                                    .map(|alt| alt.addresses.to_vec())
                                    .unwrap_or_default(),
                                Err(_) => Vec::new(),
                            };

                            let w: Vec<solana_sdk::pubkey::Pubkey> = l
                                .writable_indexes
                                .iter()
                                .filter_map(|i| addresses.get(*i as usize).cloned())
                                .collect();
                            let r: Vec<solana_sdk::pubkey::Pubkey> = l
                                .readonly_indexes
                                .iter()
                                .filter_map(|i| addresses.get(*i as usize).cloned())
                                .collect();

                            loaded_writable.extend(w);
                            loaded_readonly.extend(r);
                        }

                        keys.extend(loaded_writable);
                        keys.extend(loaded_readonly);
                        return Ok((keys, msg.instructions.clone(), fp));
                    }
                }
            }

            let tx_legacy: solana_sdk::transaction::Transaction =
                bincode::deserialize(tx_bytes).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid stored transaction bytes: {}", e)),
                    data: None,
                })?;
            let fp = tx_legacy.message.account_keys.first().cloned();
            Ok((
                tx_legacy.message.account_keys.clone(),
                tx_legacy.message.instructions.clone(),
                fp,
            ))
        }

        // Resolve account keys (best-effort; v0 includes LUT).
        let (account_keys, instructions, fee_payer) =
            solana_resolve_account_keys_for_confirm(&client, &vtx, &tx_bytes).await?;

        // Blocked-approval admin check needs fee_payer + best-effort authorities from the message.
        if approval_status == "blocked" {
            use std::str::FromStr;

            let admin_pk = solana_sdk::pubkey::Pubkey::from_str(admin_pubkey_str).map_err(|e| {
                ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("invalid admin_pubkey: {e}")),
                    data: None,
                }
            })?;

            if fee_payer != Some(admin_pk) {
                return Self::guard_result(
                    "solana_confirm_transaction",
                    "APPROVAL_BLOCKED",
                    "Blocked tx requires admin_pubkey == fee_payer",
                    false,
                    Some("Set admin_pubkey to the transaction fee_payer and ensure it is whitelisted."),
                    None,
                    Some(json!({
                        "approval_status": approval_status,
                        "fee_payer": fee_payer.map(|p| p.to_string()),
                        "admin_pubkey": admin_pk.to_string()
                    })),
                );
            }

            let token_legacy = solana_sdk::pubkey::Pubkey::from_str(
                "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            )
            .ok();
            let token_2022 = solana_sdk::pubkey::Pubkey::from_str(
                "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
            )
            .ok();
            let system_program = solana_sdk::pubkey::Pubkey::from_str(
                "11111111111111111111111111111111",
            )
            .unwrap();

            // Best-effort authority enforcement for common ix layouts.
            for ix in &instructions {
                let pid = account_keys.get(ix.program_id_index as usize).cloned();
                if pid.is_none() {
                    continue;
                }
                let pid = pid.unwrap();

                // System transfer: from is accounts[0]
                if pid == system_program {
                    if let Some(from_idx) = ix.accounts.get(0) {
                        if let Some(from_pk) = account_keys.get(*from_idx as usize) {
                            if *from_pk != admin_pk {
                                return Self::guard_result(
                                    "solana_confirm_transaction",
                                    "APPROVAL_BLOCKED",
                                    "Blocked tx requires transfer authority to be admin_pubkey",
                                    false,
                                    Some("System transfer 'from' must equal admin_pubkey for blocked overrides."),
                                    None,
                                    Some(json!({
                                        "program": "system",
                                        "from": from_pk.to_string(),
                                        "admin_pubkey": admin_pk.to_string()
                                    })),
                                );
                            }
                        }
                    }
                }

                // SPL token authority positions (common):
                // - Transfer: authority at accounts[2]
                // - TransferChecked: authority at accounts[3]
                // - Approve: owner at accounts[2]
                // - ApproveChecked: owner at accounts[3]
                // - MintTo/Burn/Close: authority/owner at accounts[2]
                if token_legacy.as_ref() == Some(&pid) || token_2022.as_ref() == Some(&pid) {
                    if ix.data.is_empty() {
                        continue;
                    }
                    let tag = ix.data[0];
                    let auth_pos: Option<usize> = match tag {
                        3 | 4 | 7 | 8 | 9 => Some(2), // transfer/approve/mint_to/burn/close
                        12 | 13 => Some(3),          // transfer_checked/approve_checked
                        14 | 15 => Some(2),          // mint_to_checked/burn_checked (authority at 2)
                        5 => Some(1),                // revoke: owner at 1
                        _ => None,
                    };

                    if let Some(pos) = auth_pos {
                        if let Some(a_idx) = ix.accounts.get(pos) {
                            if let Some(a_pk) = account_keys.get(*a_idx as usize) {
                                if *a_pk != admin_pk {
                                    return Self::guard_result(
                                        "solana_confirm_transaction",
                                        "APPROVAL_BLOCKED",
                                        "Blocked tx requires token authority/owner to be admin_pubkey",
                                        false,
                                        Some("Token instruction authority/owner must equal admin_pubkey for blocked overrides."),
                                        None,
                                        Some(json!({
                                            "program": pid.to_string(),
                                            "token_tag": tag,
                                            "authority": a_pk.to_string(),
                                            "admin_pubkey": admin_pk.to_string()
                                        })),
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }

        // Confirm-time tx sanity check: enforce that stored summary matches tx content (best-effort).
        // If approval is blocked, only a whitelisted admin_pubkey can proceed (already enforced above).
        if let Some(summary) = pending.summary.as_ref() {
            if let Some(swap) = summary.get("swap") {
                let input_mint = swap.get("input_mint").and_then(Value::as_str);
                let output_mint = swap.get("output_mint").and_then(Value::as_str);
                let expected_user = swap.get("user_pubkey").and_then(Value::as_str);

                // fee_payer should match user_pubkey for swaps (unless blocked admin override path).
                if approval_status != "blocked" {
                    if let (Some(u), Some(fp)) = (expected_user, fee_payer.as_ref()) {
                        if fp.to_string() != u {
                            return Self::guard_result(
                                "solana_confirm_transaction",
                                "TX_SUMMARY_MISMATCH",
                                "fee_payer does not match summary.swap.user_pubkey",
                                false,
                                Some("Recreate the pending confirmation from the workflow; stored summary must match the tx."),
                                None,
                                Some(json!({
                                    "expected_user_pubkey": u,
                                    "fee_payer": fp.to_string()
                                })),
                            );
                        }
                    }
                }

                // mints should appear somewhere in the account keys (best-effort; v0 resolves LUT).
                let keys_set: std::collections::HashSet<String> =
                    account_keys.iter().map(|p| p.to_string()).collect();

                let mut missing: Vec<String> = Vec::new();
                if let Some(m) = input_mint {
                    if !keys_set.contains(m) {
                        missing.push(format!("input_mint:{m}"));
                    }
                }
                if let Some(m) = output_mint {
                    if !keys_set.contains(m) {
                        missing.push(format!("output_mint:{m}"));
                    }
                }

                if !missing.is_empty() {
                    let admin_ok = approval_status == "blocked";
                    if !admin_ok {
                        return Self::guard_result(
                            "solana_confirm_transaction",
                            "TX_SUMMARY_MISMATCH",
                            "tx does not contain expected mint accounts",
                            false,
                            Some("Recreate the pending confirmation from the workflow; stored summary must match the tx."),
                            None,
                            Some(json!({
                                "missing": missing,
                                "tx_version": if vtx.is_some() { "versioned" } else { "legacy" }
                            })),
                        );
                    }
                }

                // Program allow/deny enforcement at confirm-time (re-check, in case pending/summary was tampered).
                let deny_programs_raw = std::env::var("W3RT_SOLANA_TX_DENY_PROGRAMS").unwrap_or_default();
                let allow_programs_raw = std::env::var("W3RT_SOLANA_TX_ALLOWED_PROGRAMS").unwrap_or_default();

                let deny_set: std::collections::HashSet<String> = deny_programs_raw
                    .split(',')
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();
                let allow_set: std::collections::HashSet<String> = allow_programs_raw
                    .split(',')
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();

                if !deny_set.is_empty() || !allow_set.is_empty() {
                    let mut programs_used: std::collections::HashSet<String> = std::collections::HashSet::new();
                    for ix in &instructions {
                        if let Some(pid) = account_keys.get(ix.program_id_index as usize) {
                            programs_used.insert(pid.to_string());
                        }
                    }

                    let denied: Vec<String> = programs_used
                        .iter()
                        .filter(|p| deny_set.contains(*p))
                        .cloned()
                        .collect();

                    if !denied.is_empty() {
                        // Denylist is hard-block, unless admin override path is used.
                        if approval_status != "blocked" {
                            return Self::guard_result(
                                "solana_confirm_transaction",
                                "PROGRAM_DENIED",
                                "Transaction touches a denied program id",
                                false,
                                Some("This transaction was denied by policy. Adjust route/params or remove program from denylist."),
                                None,
                                Some(json!({
                                    "denied_programs": denied,
                                    "env": "W3RT_SOLANA_TX_DENY_PROGRAMS"
                                })),
                            );
                        }
                    }

                    if !allow_set.is_empty() {
                        let not_allowed: Vec<String> = programs_used
                            .iter()
                            .filter(|p| !allow_set.contains(*p))
                            .cloned()
                            .collect();

                        if !not_allowed.is_empty() {
                            // Allowlist mismatch is a hard-block at confirm-time (unless blocked admin override).
                            if approval_status != "blocked" {
                                return Self::guard_result(
                                    "solana_confirm_transaction",
                                    "PROGRAM_NOT_ALLOWED",
                                    "Transaction touches a program id not in allowlist",
                                    false,
                                    Some("This transaction is not allowed by policy. Expand allowlist or adjust route."),
                                    None,
                                    Some(json!({
                                        "not_allowed_programs": not_allowed,
                                        "env": "W3RT_SOLANA_TX_ALLOWED_PROGRAMS"
                                    })),
                                );
                            }
                        }
                    }

                    // Extra hard guard for swaps: block unexpected native SOL transfers at confirm-time.
                    // Swap txs should generally not include SystemProgram transfer of lamports (except 0).
                    // (best-effort; only checks classic System Transfer instruction)
                    if approval_status != "blocked" {
                        let mut suspicious: Vec<Value> = Vec::new();
                        for ix in &instructions {
                            let pid = account_keys.get(ix.program_id_index as usize);
                            if pid.is_none() {
                                continue;
                            }
                            let pid = pid.unwrap();
                            if pid.to_string() != "11111111111111111111111111111111" {
                                continue;
                            }
                            if ix.data.len() != 12 {
                                continue;
                            }
                            let mut tag = [0u8; 4];
                            tag.copy_from_slice(&ix.data[0..4]);
                            if u32::from_le_bytes(tag) != 2 {
                                continue;
                            }
                            let mut amt = [0u8; 8];
                            amt.copy_from_slice(&ix.data[4..12]);
                            let lamports = u64::from_le_bytes(amt);
                            if lamports == 0 {
                                continue;
                            }

                            let from = ix
                                .accounts
                                .get(0)
                                .and_then(|i| account_keys.get(*i as usize))
                                .map(|p| p.to_string());
                            let to = ix
                                .accounts
                                .get(1)
                                .and_then(|i| account_keys.get(*i as usize))
                                .map(|p| p.to_string());
                            suspicious.push(json!({
                                "lamports": lamports,
                                "from": from,
                                "to": to
                            }));
                        }

                        if !suspicious.is_empty() {
                            return Self::guard_result(
                                "solana_confirm_transaction",
                                "SUSPICIOUS_SYSTEM_TRANSFER",
                                "Swap tx contains native SOL transfer",
                                false,
                                Some("Refusing to broadcast because swap tx unexpectedly contains a SystemProgram transfer. Use tx_preview/tx_analyze to inspect."),
                                None,
                                Some(json!({
                                    "transfers": suspicious
                                })),
                            );
                        }
                    }
                }
            }
        }

        // Sign if needed.
        let kp_path = Self::solana_keypair_path().ok();
        let kp = kp_path
            .as_deref()
            .and_then(|p| Self::solana_read_keypair_from_json_file(p).ok());

        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let send_cfg = solana_client::rpc_config::RpcSendTransactionConfig {
            skip_preflight,
            preflight_commitment: Some(
                Self::solana_commitment_from_str(request.commitment.as_deref())?.commitment,
            ),
            encoding: None,
            max_retries: None,
            min_context_slot: None,
        };

        // Broadcast: support VersionedTransaction (v0+LUT) as well as legacy Transaction.
        let sig = if let Some(mut vt) = vtx {
            if let Some(ref k) = kp {
                // If signatures are missing/default, attempt to sign.
                let all_default = vt
                    .signatures
                    .iter()
                    .all(|s| *s == solana_sdk::signature::Signature::default());
                if vt.signatures.is_empty() || all_default {
                    let recent_blockhash = match &vt.message {
                        solana_message::VersionedMessage::Legacy(m) => m.recent_blockhash,
                        solana_message::VersionedMessage::V0(m) => m.recent_blockhash,
                    };
                    vt.try_sign(&[k], recent_blockhash).map_err(|e| ErrorData {
                        code: ErrorCode(-32603),
                        message: Cow::from(format!("Failed to sign versioned tx: {e}")),
                        data: None,
                    })?;
                }
            }

            client
                .send_transaction_with_config(&vt, send_cfg)
                .await
                .map_err(|e| {
                    let msg = e.to_string();
                    let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                    ErrorData {
                        code: ErrorCode(-32000),
                        message: Cow::from(format!("solana_confirm_transaction send error: {}", msg)),
                        data: Some(json!({
                            "error_class": error_class,
                            "suggest_fix": suggest_fix,
                            "skip_preflight": skip_preflight,
                            "tx_version": "versioned"
                        })),
                    }
                })?
        } else {
            let mut tx: solana_sdk::transaction::Transaction =
                bincode::deserialize(&tx_bytes).map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid stored transaction bytes: {}", e)),
                    data: None,
                })?;

            Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());

            client
                .send_transaction_with_config(&tx, send_cfg)
                .await
                .map_err(|e| {
                    let msg = e.to_string();
                    let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                    ErrorData {
                        code: ErrorCode(-32000),
                        message: Cow::from(format!("solana_confirm_transaction send error: {}", msg)),
                        data: Some(json!({
                            "error_class": error_class,
                            "suggest_fix": suggest_fix,
                            "skip_preflight": skip_preflight,
                            "tx_version": "legacy"
                        })),
                    }
                })?
        };

        let timeout_ms = request.timeout_ms.unwrap_or(60_000);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms)
            .await
            .map_err(|e| {
                let msg = e.message.to_string();
                let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                ErrorData {
                    code: e.code,
                    message: e.message,
                    data: Some(json!({
                        "error_class": error_class,
                        "suggest_fix": suggest_fix,
                        "timeout_ms": timeout_ms
                    })),
                }
            })?;

        // If we got ok, remove pending; if timeout, keep it for retry.
        if waited.get("status").and_then(|v| v.as_str()) == Some("ok") {
            let _ = crate::utils::solana_confirm_store::remove_pending(&request.id);
        }

        let status = waited
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");

        fn about_to_broadcast(summary: &Option<Value>, fallback_network: &str) -> Option<String> {
            let s = summary.as_ref()?;

            // transfer_native / transfer_spl
            if let Some(t) = s.get("transfer") {
                let kind = t.get("kind").and_then(Value::as_str).unwrap_or("transfer");
                let network = t
                    .get("network")
                    .and_then(Value::as_str)
                    .unwrap_or(fallback_network);
                let from = t.get("from").and_then(Value::as_str).unwrap_or("<from>");
                let to = t.get("to").and_then(Value::as_str).unwrap_or("<to>");

                if kind == "native" {
                    let amount_ui = t.get("amount_ui").and_then(Value::as_str).unwrap_or("?");
                    return Some(format!(
                        "About to broadcast: transfer {} SOL from {} to {} on {}",
                        amount_ui, from, to, network
                    ));
                }

                if kind == "spl" {
                    let asset = t.get("asset").and_then(Value::as_str).unwrap_or("SPL");
                    let amount_ui = t.get("amount_ui").and_then(Value::as_str).unwrap_or("?");
                    let mint = t.get("mint").and_then(Value::as_str).unwrap_or("<mint>");
                    let will_create_ata = t.get("will_create_ata").and_then(Value::as_bool).unwrap_or(false);
                    let ata_note = if will_create_ata { " (will create recipient ATA)" } else { "" };
                    return Some(format!(
                        "About to broadcast: transfer {} {} (mint {}) from {} to {} on {}{}",
                        amount_ui, asset, mint, from, to, network, ata_note
                    ));
                }

                return Some(format!(
                    "About to broadcast: {} from {} to {} on {}",
                    kind, from, to, network
                ));
            }

            // swap_exact_in
            if let Some(sw) = s.get("swap") {
                let network = sw
                    .get("network")
                    .and_then(Value::as_str)
                    .unwrap_or(fallback_network);
                let user = sw
                    .get("user_pubkey")
                    .and_then(Value::as_str)
                    .unwrap_or("<user>");
                let in_amt = sw
                    .get("amount_in_base")
                    .and_then(Value::as_str)
                    .unwrap_or("?");
                let out_amt = sw
                    .get("amount_out_base")
                    .and_then(Value::as_str)
                    .unwrap_or("?");
                let input_mint = sw
                    .get("input_mint")
                    .and_then(Value::as_str)
                    .unwrap_or("<in_mint>");
                let output_mint = sw
                    .get("output_mint")
                    .and_then(Value::as_str)
                    .unwrap_or("<out_mint>");
                let price_impact = sw
                    .get("price_impact_pct")
                    .and_then(Value::as_str)
                    .unwrap_or("?");
                let slippage_bps = sw.get("slippage_bps").and_then(Value::as_u64).unwrap_or(0);

                return Some(format!(
                    "About to broadcast: swap {} (mint {}) → {} (mint {}) for {} on {} (slippage {} bps, priceImpact {})",
                    in_amt, input_mint, out_amt, output_mint, user, network, slippage_bps, price_impact
                ));
            }

            None
        }

        // Best-effort: include the pending summary + a short human preview.
        let response = Self::pretty_json(&json!({
            "ok": true,
            "stage": "confirm",
            "status": status,
            "rpc_url": rpc_url,
            "network": network,
            "pending_confirmation_id": request.id,
            "tx_summary_hash": request.hash,
            "summary": pending.summary,
            "about_to_broadcast": about_to_broadcast(&pending.summary, &network),
            "signature": sig.to_string(),
            "skip_preflight": skip_preflight,
            "commitment": commitment,
            "wait": waited,
            "note": "If status==timeout you can call solana_confirm_transaction again with same id/hash."
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // ---------------- Solana IDL (Dynamic + Registry) ----------------

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: load an IDL dynamically (json/base64/url/path) into an in-memory cache. Optionally persist to abi_registry."))]
    async fn solana_idl_load(
        &self,
        Parameters(request): Parameters<SolanaIdlLoadRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // load bytes
        let mut idl_json: Option<String> = None;

        if let Some(s) = request.idl_json.clone().filter(|s| !s.trim().is_empty()) {
            idl_json = Some(s);
        } else if let Some(b64) = request.idl_base64.clone().filter(|s| !s.trim().is_empty()) {
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(b64.trim())
                .map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid idl_base64: {e}")),
                    data: None,
                })?;
            let s = String::from_utf8(bytes).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("idl_base64 is not valid UTF-8: {e}")),
                data: None,
            })?;
            idl_json = Some(s);
        } else if let Some(url) = request.idl_url.clone().filter(|s| !s.trim().is_empty()) {
            let url = url.trim().to_string();
            let resp = reqwest::Client::new()
                .get(&url)
                .send()
                .await
                .map_err(|e| Self::sdk_error("solana_idl_load", e))?;
            let status = resp.status();
            let body = resp.text().await.map_err(|e| Self::sdk_error("solana_idl_load", e))?;
            if !status.is_success() {
                return Err(ErrorData {
                    code: ErrorCode(-32603),
                    message: Cow::from(format!("Failed to fetch idl_url (status={status}): {url}")),
                    data: Some(json!({"status": status.as_u16(), "url": url})),
                });
            }
            idl_json = Some(body);
        } else if let Some(path) = request.idl_path.clone().filter(|s| !s.trim().is_empty()) {
            let data = std::fs::read_to_string(path.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("Failed to read idl_path: {e}")),
                data: Some(json!({"path": path})),
            })?;
            idl_json = Some(data);
        }

        let idl_json = idl_json.ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("Provide one of: idl_json|idl_base64|idl_url|idl_path"),
            data: None,
        })?;

        let idl: Value = serde_json::from_str(&idl_json).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid IDL JSON: {e}")),
            data: None,
        })?;

        // compute stable id
        let hash = solana_sdk::hash::hash(idl_json.as_bytes()).to_string();
        let idl_id = format!("idl_{}", &hash[..16]);

        self.solana_idl_cache.put(idl_id.clone(), idl.clone());

        // optional persist to registry
        let persisted = request.persist.unwrap_or(false);
        let mut persisted_path: Option<String> = None;
        let mut persisted_name: Option<String> = None;
        let mut persisted_program_id: Option<String> = None;

        if persisted {
            let program_id = request
                .program_id
                .as_deref()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("persist=true requires program_id"),
                    data: None,
                })?;
            let program_id = Self::solana_parse_program_id(&program_id)?.to_string();

            let inferred = crate::utils::solana_idl_registry::infer_name_from_idl_json(&idl)
                .unwrap_or_else(|| "default".to_string());
            let name_raw = request.name.clone().unwrap_or(inferred);
            let name = crate::utils::solana_idl_registry::sanitize_name(&name_raw);

            let overwrite = request.overwrite.unwrap_or(false);
            let path = crate::utils::solana_idl_registry::write_idl(&program_id, &name, &idl, overwrite)?;

            persisted_path = Some(path.to_string_lossy().to_string());
            persisted_name = Some(name);
            persisted_program_id = Some(program_id);
        }

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "idl_id": idl_id,
            "program_id": request.program_id,
            "persisted": persisted,
            "persisted_program_id": persisted_program_id,
            "persisted_name": persisted_name,
            "persisted_path": persisted_path
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: unload an in-memory IDL handle"))]
    async fn solana_idl_unload(
        &self,
        Parameters(request): Parameters<SolanaIdlUnloadRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let idl_id = request.idl_id.trim();
        let removed = self.solana_idl_cache.remove(idl_id);
        let response = Self::pretty_json(&json!({
            "status": "ok",
            "idl_id": idl_id,
            "removed": removed
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: list currently loaded in-memory IDL handles"))]
    async fn solana_idl_cache_list(&self) -> Result<CallToolResult, ErrorData> {
        let items = self.solana_idl_cache.list();
        let response = Self::pretty_json(&json!({
            "status": "ok",
            "count": items.len(),
            "idl_ids": items
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: clear all in-memory loaded IDLs"))]
    async fn solana_idl_cache_clear(&self) -> Result<CallToolResult, ErrorData> {
        self.solana_idl_cache.clear();
        let response = Self::pretty_json(&json!({
            "status": "ok",
            "cleared": true
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: list instructions for an in-memory IDL handle"))]
    async fn solana_idl_list_instructions(
        &self,
        Parameters(request): Parameters<SolanaIdlListInstructionsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let idl_id = request.idl_id.trim();
        let idl = self
            .solana_idl_cache
            .get(idl_id)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Unknown idl_id (not loaded)"),
                data: Some(json!({"idl_id": idl_id})),
            })?;

        let instructions = idl
            .get("instructions")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let out: Vec<Value> = instructions
            .iter()
            .filter_map(|ix| {
                let name = ix.get("name")?.as_str()?.to_string();
                let accounts_len = ix
                    .get("accounts")
                    .and_then(|a| a.as_array())
                    .map(|a| a.len())
                    .unwrap_or(0);
                let args = ix
                    .get("args")
                    .and_then(|a| a.as_array())
                    .cloned()
                    .unwrap_or_default();
                Some(json!({
                    "name": name,
                    "accounts_len": accounts_len,
                    "args": args
                }))
            })
            .collect();

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "idl_id": idl_id,
            "count": out.len(),
            "instructions": out
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    // ---------------- Solana IDL Registry ----------------

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL Registry: register an IDL JSON under abi_registry/solana/<program_id>/<name>.json"))]
    async fn solana_idl_register(
        &self,
        Parameters(request): Parameters<SolanaIdlRegisterRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        // validate program id
        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();

        let idl: Value = serde_json::from_str(&request.idl_json).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid IDL JSON: {}", e)),
            data: None,
        })?;

        let inferred = crate::utils::solana_idl_registry::infer_name_from_idl_json(&idl)
            .unwrap_or_else(|| "default".to_string());
        let name_raw = request.name.unwrap_or(inferred);
        let name = crate::utils::solana_idl_registry::sanitize_name(&name_raw);
        if name.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("IDL name is empty after sanitization"),
                data: Some(json!({ "provided": name_raw })),
            });
        }

        let overwrite = request.overwrite.unwrap_or(false);
        let path = crate::utils::solana_idl_registry::write_idl(&program_id, &name, &idl, overwrite)?;

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "program_id": program_id,
            "name": name,
            "path": path.to_string_lossy(),
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL Registry: register an IDL JSON from a local file path"))]
    async fn solana_idl_register_file(
        &self,
        Parameters(request): Parameters<SolanaIdlRegisterFileRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();

        let data = std::fs::read_to_string(&request.path).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to read file: {}", e)),
            data: Some(json!({ "path": request.path })),
        })?;
        let idl: Value = serde_json::from_str(&data).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid IDL JSON: {}", e)),
            data: Some(json!({ "path": request.path })),
        })?;

        let inferred = crate::utils::solana_idl_registry::infer_name_from_idl_json(&idl).or_else(|| {
            std::path::Path::new(&request.path)
                .file_stem()
                .and_then(|s| s.to_str())
                .map(|s| s.to_string())
        }).unwrap_or_else(|| "default".to_string());

        let name_raw = request.name.unwrap_or(inferred);
        let name = crate::utils::solana_idl_registry::sanitize_name(&name_raw);
        let overwrite = request.overwrite.unwrap_or(false);
        let path = crate::utils::solana_idl_registry::write_idl(&program_id, &name, &idl, overwrite)?;

        let response = Self::pretty_json(&json!({
            "status": "ok",
            "program_id": program_id,
            "name": name,
            "path": path.to_string_lossy(),
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL Registry: list registered programs and names"))]
    async fn solana_idl_list(
        &self,
        Parameters(request): Parameters<SolanaIdlListRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let items = crate::utils::solana_idl_registry::list_programs()?;

        let filter = request
            .program_id
            .as_deref()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let mut out: Vec<Value> = Vec::new();
        for (pid, names) in items {
            if let Some(ref f) = filter {
                if pid != *f {
                    continue;
                }
            }
            out.push(json!({
                "program_id": pid,
                "names": names
            }));
        }

        let response = Self::pretty_json(&json!({
            "root": crate::utils::solana_idl_registry::registry_root().to_string_lossy(),
            "count": out.len(),
            "items": out
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL Registry: get a registered IDL"))]
    async fn solana_idl_get(
        &self,
        Parameters(request): Parameters<SolanaIdlGetRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();
        let name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        if name.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("IDL name is empty after sanitization"),
                data: None,
            });
        }

        let idl = crate::utils::solana_idl_registry::read_idl(&program_id, &name)?;
        let response = Self::pretty_json(&json!({
            "program_id": program_id,
            "name": name,
            "idl": idl
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL Registry: search registered IDLs by program_id or name"))]
    async fn solana_idl_search(
        &self,
        Parameters(request): Parameters<SolanaIdlSearchRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let q = request.query.trim().to_lowercase();
        if q.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("query is required"),
                data: None,
            });
        }

        let limit = request.limit.unwrap_or(50).min(500) as usize;
        let items = crate::utils::solana_idl_registry::list_programs()?;
        let mut out: Vec<Value> = Vec::new();

        for (pid, names) in items {
            let pid_l = pid.to_lowercase();
            let pid_hit = pid_l.contains(&q);
            for n in names {
                let nl = n.to_lowercase();
                if pid_hit || nl.contains(&q) {
                    out.push(json!({
                        "program_id": pid,
                        "name": n,
                        "path": crate::utils::solana_idl_registry::idl_path(&pid, &n).to_string_lossy()
                    }));
                    if out.len() >= limit {
                        break;
                    }
                }
            }
            if out.len() >= limit {
                break;
            }
        }

        let response = Self::pretty_json(&json!({
            "query": q,
            "count": out.len(),
            "items": out
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: plan an instruction from registered IDL (offline; optional on-chain validation)"))]
    async fn solana_idl_plan_instruction(
        &self,
        Parameters(request): Parameters<SolanaIdlPlanInstructionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref().unwrap_or("mainnet");
        let rpc_url = Self::solana_rpc_url_for_network(Some(network))?;

        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();
        let name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction = request.instruction.trim().to_string();

        let idl = if let Some(ref idl_id) = request.idl_id {
            self.solana_idl_cache
                .get(idl_id.trim())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Unknown idl_id (not loaded)"),
                    data: Some(json!({"idl_id": idl_id})),
                })?
        } else {
            crate::utils::solana_idl_registry::read_idl(&program_id, &name)?
        };

        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction)?;

        let args_obj = request.args.unwrap_or_else(|| json!({}));
        let accounts_obj = request.accounts.unwrap_or_else(|| json!({}));

        let mut missing_args: Vec<String> = Vec::new();
        let mut args_schema: Vec<Value> = Vec::new();
        for a in &ix.args {
            let allowed_enum_variants =
                crate::utils::solana_idl_enum_hints::enum_variants_for_type(&idl, &a.ty);
            let example_value = crate::utils::solana_idl_arg_examples::example_for_type(&idl, &a.ty);
            args_schema.push(json!({
                "name": a.name,
                "type": a.ty,
                "allowed_enum_variants": allowed_enum_variants,
                "example": example_value
            }));
            if args_obj.get(&a.name).is_none() {
                missing_args.push(a.name.clone());
            }
        }

        let mut missing_accounts: Vec<String> = Vec::new();
        let mut accounts_needed: Vec<Value> = Vec::new();
        for a in &ix.accounts {
            let has = accounts_obj.get(&a.name).and_then(|v| v.as_str()).is_some();
            if !has {
                missing_accounts.push(a.name.clone());
            }
            accounts_needed.push(json!({
                "name": a.name,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut,
                "provided": accounts_obj.get(&a.name)
            }));
        }

        fn solana_is_default_pubkey(pk: &solana_sdk::pubkey::Pubkey) -> bool {
            *pk == solana_sdk::pubkey::Pubkey::default()
        }

        fn expected_program_id_for_account_name(name: &str) -> Option<solana_sdk::pubkey::Pubkey> {
            // Heuristics to help users avoid placeholder/mistmatched program ids.
            // This is intentionally conservative (best-effort hints, not hard validation).
            let n = name.to_lowercase();

            // Programs
            if n.contains("systemprogram") || n == "system_program" {
                // System Program
                return solana_sdk::pubkey::Pubkey::from_str("11111111111111111111111111111111").ok();
            }
            if n == "tokenprogram" || n.contains("spltokenprogram") || n.contains("token_program") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                )
                .ok();
            }
            if n.contains("token2022") || n.contains("token_2022") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
                )
                .ok();
            }
            if n.contains("associatedtokenprogram")
                || n.contains("associated_token_program")
                || n == "ata_program"
            {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
                )
                .ok();
            }

            if n.contains("memoprogram") || n.contains("memo_program") || n == "memo" {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
                )
                .ok();
            }

            if n.contains("computebudget") || n.contains("compute_budget") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "ComputeBudget111111111111111111111111111111",
                )
                .ok();
            }

            if n.contains("addresslookuptable") || n.contains("address_lookup_table") || n == "alt_program" {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "AddressLookupTab1e1111111111111111111111111",
                )
                .ok();
            }

            if n.contains("ed25519") || n.contains("ed_25519") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "Ed25519SigVerify111111111111111111111111111",
                )
                .ok();
            }

            if n.contains("secp256k1") || n.contains("secp_256k1") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "KeccakSecp256k11111111111111111111111111111",
                )
                .ok();
            }

            // Sysvars (note: these are accounts, not programs, but the hint is still useful)
            if n == "rent" || n.contains("sysvarrent") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "SysvarRent111111111111111111111111111111111",
                )
                .ok();
            }
            if n == "clock" || n.contains("sysvarclock") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "SysvarC1ock11111111111111111111111111111111",
                )
                .ok();
            }
            if n == "recentblockhashes" || n.contains("sysvarrecentblockhashes") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "SysvarRecentB1ockHashes11111111111111111111",
                )
                .ok();
            }
            if n == "instructions" || n.contains("sysvarinstructions") {
                return solana_sdk::pubkey::Pubkey::from_str(
                    "Sysvar1nstructions1111111111111111111111111",
                )
                .ok();
            }

            None
        }

        fn hint_for_account_name(name: &str) -> Option<String> {
            let n = name.to_lowercase();
            if n.contains("associatedtokenaccount") || n == "ata" || n.ends_with("_ata") {
                return Some(
                    "looks like an ATA (Associated Token Account). You typically derive it from (owner,mint[,token_program])."
                        .to_string(),
                );
            }
            if n.contains("addresslookuptable") || n.contains("address_lookup_table") || n == "alt" {
                return Some(
                    "looks related to Address Lookup Tables (ALT). Note: the ALT *program id* is fixed, but each lookup table itself is an account with its own pubkey."
                        .to_string(),
                );
            }
            if n == "instructions" || n.contains("sysvarinstructions") {
                return Some(
                    "this is the Instructions Sysvar. Many signature-verify/validation flows require it (e.g. checking other instructions in the same tx)."
                        .to_string(),
                );
            }
            if n.contains("user") && n.contains("token") && n.contains("account") {
                return Some(
                    "looks like a user token account. Usually this is an SPL token account (often the ATA)."
                        .to_string(),
                );
            }
            None
        }

        // Always provide offline hints (best-effort) to avoid common footguns.
        let mut hints: Vec<Value> = Vec::new();
        let mut suggested_defaults: serde_json::Map<String, Value> = serde_json::Map::new();

        for a in &ix.accounts {
            let expected = expected_program_id_for_account_name(&a.name).map(|p| p.to_string());
            let note = hint_for_account_name(&a.name);

            // If the account is missing and we can provide a safe, well-known default, suggest it.
            let is_missing = accounts_obj.get(&a.name).and_then(|v| v.as_str()).is_none();
            if is_missing {
                if let Some(ref pid) = expected {
                    suggested_defaults.insert(
                        a.name.clone(),
                        json!({
                            "kind": "well_known_program_id",
                            "pubkey": pid
                        }),
                    );
                }
            }

            if expected.is_some() || note.is_some() {
                hints.push(json!({
                    "name": a.name,
                    "expected_program_id": expected,
                    "note": note
                }));
            }
        }

        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(network))?;
            let mut checks: Vec<Value> = Vec::new();

            // Validate any provided accounts (do not error if missing; just report missing).
            for a in &ix.accounts {
                if let Some(pk_str) = accounts_obj.get(&a.name).and_then(|v| v.as_str()) {
                    let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", a.name))?;
                    let acc = client.get_account(&pk).await.ok();

                    let mut warnings: Vec<Value> = Vec::new();
                    if solana_is_default_pubkey(&pk) {
                        warnings.push(json!({
                            "kind": "placeholder_pubkey",
                            "message": "pubkey is 111111... (default). This is almost never valid for real instructions"
                        }));
                    }
                    if a.is_signer && solana_is_default_pubkey(&pk) {
                        warnings.push(json!({
                            "kind": "signer_placeholder",
                            "message": "signer account is placeholder (111111...). Provide a real signer pubkey"
                        }));
                    }

                    if let Some(expected_pid) = expected_program_id_for_account_name(&a.name) {
                        if pk != expected_pid {
                            warnings.push(json!({
                                "kind": "program_id_mismatch",
                                "message": "account name suggests this should be a well-known program id",
                                "expected": expected_pid.to_string()
                            }));
                        }
                    }

                    // If it's expected to be a program, it should be executable.
                    if expected_program_id_for_account_name(&a.name).is_some() {
                        if let Some(ref aa) = acc {
                            if !aa.executable {
                                warnings.push(json!({
                                    "kind": "expected_executable",
                                    "message": "expected executable program account, but executable=false"
                                }));
                            }
                        }
                    }

                    checks.push(json!({
                        "name": a.name,
                        "pubkey": pk.to_string(),
                        "exists": acc.is_some(),
                        "owner": acc.as_ref().map(|x| x.owner.to_string()),
                        "lamports": acc.as_ref().map(|x| x.lamports),
                        "data_len": acc.as_ref().map(|x| x.data.len()),
                        "executable": acc.as_ref().map(|x| x.executable),
                        "warnings": warnings
                    }));
                } else {
                    checks.push(json!({
                        "name": a.name,
                        "pubkey": null,
                        "exists": null,
                        "note": "not provided"
                    }));
                }
            }

            onchain = Some(json!({ "checks": checks }));
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network,
            "program_id": program_id,
            "idl_name": name,
            "instruction": ix.name,
            "args_schema": args_schema,
            "accounts_needed": accounts_needed,
            "missing": {
                "args": missing_args,
                "accounts": missing_accounts
            },
            "hints": hints,
            "suggested_defaults": suggested_defaults,
            "validate_on_chain": validate,
            "onchain": onchain,
            "tool_context": json!({
                "tool": "solana_idl_plan_instruction"
            }),
            "summary": json!({
                "program_id": program_id,
                "idl_name": name,
                "instruction": instruction,
                "missing_args": missing_args,
                "missing_accounts": missing_accounts
            })
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    fn solana_json_metas_to_account_metas(
        metas: &[Value],
    ) -> Result<Vec<solana_sdk::instruction::AccountMeta>, ErrorData> {
        let mut out: Vec<solana_sdk::instruction::AccountMeta> = Vec::new();
        for m in metas {
            let pk_str = m
                .get("pubkey")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("account meta missing pubkey"),
                    data: Some(json!({"meta": m})),
                })?;
            let is_signer = m
                .get("is_signer")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let is_writable = m
                .get("is_writable")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let pk = Self::solana_parse_pubkey(pk_str, "account pubkey")?;
            out.push(if is_writable {
                solana_sdk::instruction::AccountMeta::new(pk, is_signer)
            } else {
                solana_sdk::instruction::AccountMeta::new_readonly(pk, is_signer)
            });
        }
        Ok(out)
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: build an instruction (program_id + accounts metas + data_base64) from registered IDL"))]
    async fn solana_idl_build_instruction(
        &self,
        Parameters(request): Parameters<SolanaIdlBuildInstructionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network = request.network.as_deref().unwrap_or("mainnet");
        let rpc_url = Self::solana_rpc_url_for_network(Some(network))?;

        let program_id = Self::solana_parse_program_id(request.program_id.trim())?.to_string();
        let name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction = request.instruction.trim().to_string();

        let idl = if let Some(ref idl_id) = request.idl_id {
            self.solana_idl_cache
                .get(idl_id.trim())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Unknown idl_id (not loaded)"),
                    data: Some(json!({"idl_id": idl_id})),
                })?
        } else {
            crate::utils::solana_idl_registry::read_idl(&program_id, &name)?
        };
        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction)?;

        let args_obj = request.args;
        let accounts_obj = request.accounts;

        // args in order
        let mut args_pairs: Vec<(crate::utils::solana_idl::IdlArg, Value)> = Vec::new();
        let mut missing_args: Vec<String> = Vec::new();
        for a in &ix.args {
            let v = args_obj.get(&a.name).cloned();
            if v.is_none() {
                missing_args.push(a.name.clone());
                continue;
            }
            args_pairs.push((a.clone(), v.unwrap()));
        }
        if !missing_args.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required args"),
                data: Some(json!({"missing_args": missing_args})),
            });
        }

        let mut metas: Vec<Value> = Vec::new();
        let mut missing_accounts: Vec<String> = Vec::new();
        for a in &ix.accounts {
            let pk = accounts_obj.get(&a.name).and_then(|v| v.as_str()).map(|s| s.to_string());
            if pk.is_none() {
                missing_accounts.push(a.name.clone());
                continue;
            }
            // Validate pubkey format now
            let _ = Self::solana_parse_pubkey(pk.as_ref().unwrap(), &format!("account:{}", a.name))?;
            metas.push(json!({
                "name": a.name,
                "pubkey": pk,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut
            }));
        }
        if !missing_accounts.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required accounts"),
                data: Some(json!({"missing_accounts": missing_accounts})),
            });
        }

        let data = crate::utils::solana_idl::encode_anchor_ix_data(&idl, &ix.name, &args_pairs)?;
        let data_b64 = base64::engine::general_purpose::STANDARD.encode(&data);

        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(network))?;
            let mut checks: Vec<Value> = Vec::new();

            for m in &metas {
                let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let pk_str = m.get("pubkey").and_then(|v| v.as_str()).unwrap_or("");
                let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", name))?;

                let acc = client.get_account(&pk).await.ok();
                checks.push(json!({
                    "name": name,
                    "pubkey": pk.to_string(),
                    "exists": acc.is_some(),
                    "owner": acc.as_ref().map(|x| x.owner.to_string()),
                    "lamports": acc.as_ref().map(|x| x.lamports),
                    "data_len": acc.as_ref().map(|x| x.data.len()),
                    "executable": acc.as_ref().map(|x| x.executable),
                }));
            }

            onchain = Some(json!({
                "checks": checks
            }));
        }

        let response = Self::pretty_json(&json!({
            "rpc_url": rpc_url,
            "network": network,
            "program_id": program_id,
            "idl_name": name,
            "instruction": ix.name,
            "accounts": metas,
            "data_base64": data_b64,
            "validate_on_chain": validate,
            "onchain": onchain,
            "tool_context": json!({
                "tool": "solana_idl_build_instruction"
            }),
            "summary": json!({
                "program_id": program_id,
                "idl_name": name,
                "instruction": instruction,
                "accounts_count": ix.accounts.len(),
                "args_count": ix.args.len(),
                "data_len": data.len()
            })
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: build instruction+tx and simulate (no broadcast)"))]
    async fn solana_idl_simulate_instruction(
        &self,
        Parameters(request): Parameters<SolanaIdlSimulateInstructionRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let cfg = request.simulate_config.clone();
        let network = cfg
            .as_ref()
            .and_then(|c| c.network.as_deref())
            .or(request.network.as_deref());
        let network_str = network.unwrap_or("mainnet").to_string();
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;

        // Program id is always required for building the Instruction (program_id field), even if IDL is loaded dynamically.
        let program_id_pk = Self::solana_parse_program_id(request.program_id.trim())?;
        let program_id = program_id_pk.to_string();
        let idl_name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction_name = request.instruction.trim().to_string();

        // 1) Build instruction (IDL)
        let idl = if let Some(ref idl_id) = request.idl_id {
            self.solana_idl_cache
                .get(idl_id.trim())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Unknown idl_id (not loaded)"),
                    data: Some(json!({"idl_id": idl_id})),
                })?
        } else {
            crate::utils::solana_idl_registry::read_idl(&program_id, &idl_name)?
        };
        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction_name)?;

        // args in order
        let mut args_pairs: Vec<(crate::utils::solana_idl::IdlArg, Value)> = Vec::new();
        let mut missing_args: Vec<String> = Vec::new();
        for a in &ix.args {
            let v = request.args.get(&a.name).cloned();
            if v.is_none() {
                missing_args.push(a.name.clone());
                continue;
            }
            args_pairs.push((a.clone(), v.unwrap()));
        }
        if !missing_args.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required args"),
                data: Some(json!({"missing_args": missing_args})),
            });
        }

        let mut metas_json: Vec<Value> = Vec::new();
        let mut missing_accounts: Vec<String> = Vec::new();
        for a in &ix.accounts {
            let pk = request
                .accounts
                .get(&a.name)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            if pk.is_none() {
                missing_accounts.push(a.name.clone());
                continue;
            }
            let _ = Self::solana_parse_pubkey(pk.as_ref().unwrap(), &format!("account:{}", a.name))?;
            metas_json.push(json!({
                "name": a.name,
                "pubkey": pk,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut
            }));
        }
        if !missing_accounts.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required accounts"),
                data: Some(json!({"missing_accounts": missing_accounts})),
            });
        }

        let data = crate::utils::solana_idl::encode_anchor_ix_data(&idl, &ix.name, &args_pairs)?;
        let data_b64 = base64::engine::general_purpose::STANDARD.encode(&data);

        // Optional on-chain checks
        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(&network_str))?;
            let mut checks: Vec<Value> = Vec::new();
            for m in &metas_json {
                let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let pk_str = m.get("pubkey").and_then(|v| v.as_str()).unwrap_or("");
                let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", name))?;
                let acc = client.get_account(&pk).await.ok();
                checks.push(json!({
                    "name": name,
                    "pubkey": pk.to_string(),
                    "exists": acc.is_some(),
                    "owner": acc.as_ref().map(|x| x.owner.to_string()),
                    "lamports": acc.as_ref().map(|x| x.lamports),
                    "data_len": acc.as_ref().map(|x| x.data.len()),
                    "executable": acc.as_ref().map(|x| x.executable),
                }));
            }
            onchain = Some(json!({"checks": checks}));
        }

        // 2) Build transaction and simulate
        let client = Self::solana_rpc(Some(&network_str))?;
        let fee_payer = Self::solana_parse_pubkey(request.fee_payer.trim(), "fee_payer")?;

        let replace = cfg
            .as_ref()
            .and_then(|c| c.replace_recent_blockhash)
            .or(request.replace_recent_blockhash)
            .unwrap_or(true);

        let recent_blockhash = if replace {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_idl_simulate_instruction", e))?
        } else if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_idl_simulate_instruction", e))?
        };

        let account_metas = Self::solana_json_metas_to_account_metas(&metas_json)?;
        let account_metas_for_fee = account_metas.clone();
        let ixn = solana_sdk::instruction::Instruction {
            program_id: program_id_pk,
            accounts: account_metas,
            data: data.clone(),
        };

        let message = solana_sdk::message::Message::new(&[ixn], Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;

        let sig_verify = cfg
            .as_ref()
            .and_then(|c| c.sig_verify)
            .or(request.sig_verify)
            .unwrap_or(false);
        let strict_sig_verify = cfg
            .as_ref()
            .and_then(|c| c.strict_sig_verify)
            .unwrap_or(false);
        if sig_verify {
            let need_sign = tx.signatures.is_empty()
                || tx
                    .signatures
                    .iter()
                    .all(|s| *s == solana_sdk::signature::Signature::default());

            let kp = Self::solana_keypair_path()
                .ok()
                .and_then(|p| Self::solana_read_keypair_from_json_file(&p).ok());

            if strict_sig_verify && need_sign && kp.is_none() {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(
                        "sig_verify=true requires signatures but no local keypair is available. Set SOLANA_KEYPAIR_PATH or set simulate_config.strict_sig_verify=false",
                    ),
                    data: None,
                });
            }

            Self::solana_try_sign_if_needed(&mut tx, kp.as_ref());
        }

        let commitment = cfg
            .as_ref()
            .and_then(|c| c.commitment.clone())
            .or(request.commitment.clone())
            .unwrap_or("confirmed".to_string());

        let accounts_cfg = if let Some(ref c) = cfg {
            if let Some(ref addrs) = c.simulate_accounts {
                if addrs.is_empty() {
                    None
                } else {
                    let enc_str = c.accounts_encoding.as_deref().unwrap_or("base64");
                    let enc = Self::solana_ui_account_encoding_from_str(enc_str)?;
                    Some(solana_client::rpc_config::RpcSimulateTransactionAccountsConfig {
                        encoding: Some(enc),
                        addresses: addrs.clone(),
                    })
                }
            } else {
                None
            }
        } else {
            None
        };

        let sim = client
            .simulate_transaction_with_config(
                &tx,
                solana_client::rpc_config::RpcSimulateTransactionConfig {
                    sig_verify,
                    replace_recent_blockhash: replace,
                    commitment: Some(Self::solana_commitment_from_str(Some(&commitment))?),
                    encoding: None,
                    accounts: accounts_cfg,
                    min_context_slot: None,
                    inner_instructions: false,
                },
            )
            .await
            .map_err(|e| Self::sdk_error("solana_idl_simulate_instruction", e))?;

        let suggested_cu_limit = Self::solana_suggest_compute_unit_limit(sim.value.units_consumed);

        // -------- Error classification (best-effort) --------
        let ok = sim.value.err.is_none();
        let logs: Vec<String> = sim
            .value
            .logs
            .clone()
            .unwrap_or_default()
            .into_iter()
            .take(80)
            .collect();

        let (error_class, suggest_fix) = if let Some(ref err) = sim.value.err {
            let v = serde_json::to_value(err).unwrap_or_else(|_| json!({ "err": err.to_string() }));
            Self::solana_classify_simulation(&v, &logs)
        } else {
            (Self::SOLANA_ERROR_OK.to_string(), None)
        };

        let suggest_price = cfg
            .as_ref()
            .and_then(|c| c.suggest_compute_unit_price)
            .unwrap_or(false);
        let mut suggested_cu_price: Option<u64> = None;
        let mut price_sample: Option<Value> = None;
        if suggest_price {
            let addr_strs: Vec<String> = cfg
                .as_ref()
                .and_then(|c| c.simulate_accounts.clone())
                .unwrap_or_default();

            let mut addrs: Vec<solana_sdk::pubkey::Pubkey> = addr_strs
                .iter()
                .filter_map(|s| solana_sdk::pubkey::Pubkey::from_str(s.trim()).ok())
                .collect();

            if addrs.is_empty() {
                // Auto-sample addresses from the built instruction metas (max 16)
                addrs =
                    Self::solana_suggest_fee_sample_addresses_from_metas(&account_metas_for_fee, 16);
            }

            let fees_res = if !addrs.is_empty() {
                client.get_recent_prioritization_fees(&addrs).await
            } else {
                client.get_recent_prioritization_fees(&[]).await
            };

            if let Ok(fees) = fees_res {
                let vals: Vec<u64> = fees.iter().map(|f| f.prioritization_fee).collect();
                suggested_cu_price = Self::solana_percentile_u64(vals.clone(), 0.75);
                price_sample = Some(json!({
                    "scope": if !addrs.is_empty() { "addresses" } else { "cluster" },
                    "addresses_count": addrs.len(),
                    "addresses": addrs.iter().take(16).map(|p| p.to_string()).collect::<Vec<String>>(),
                    "count": fees.len(),
                    "p50": Self::solana_percentile_u64(vals.clone(), 0.50),
                    "p75": Self::solana_percentile_u64(vals.clone(), 0.75),
                    "p90": Self::solana_percentile_u64(vals, 0.90)
                }));
            }
        }

        let response = Self::pretty_json(&json!({
            "ok": ok,
            "stage": "simulate",
            "error_class": if ok { null } else { error_class },
            "suggest_fix": if ok { null } else { suggest_fix },
            "logs_excerpt": if logs.is_empty() { null } else { logs },

            "rpc_url": rpc_url,
            "network": network_str,
            "program_id": program_id,
            "idl_name": idl_name,
            "instruction": instruction_name,
            "fee_payer": request.fee_payer,
            "recent_blockhash": recent_blockhash.to_string(),
            "sig_verify": sig_verify,
            "replace_recent_blockhash": replace,
            "commitment": commitment,
            "built_instruction": {
                "program_id": program_id_pk.to_string(),
                "accounts": metas_json,
                "data_base64": data_b64,
                "validate_on_chain": validate,
                "onchain": onchain
            },
            "context": sim.context,
            "value": sim.value,
            "suggestions": {
                "compute_unit_limit": suggested_cu_limit,
                "compute_unit_price_micro_lamports": suggested_cu_price,
                "recent_prioritization_fees": price_sample
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[cfg(feature = "solana-extended-tools")]
    #[cfg_attr(feature = "solana-extended-tools", tool(description = "Solana IDL: build tx and (optionally) send it. Safe default: creates pending confirmation unless confirm=true"))]
    async fn solana_idl_execute(
        &self,
        Parameters(request): Parameters<SolanaIdlExecuteRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let network_str = request.network.clone().unwrap_or("mainnet".to_string());
        let rpc_url = Self::solana_rpc_url_for_network(Some(&network_str))?;

        // Program id is always required for building the Instruction (program_id field), even if IDL is loaded dynamically.
        let program_id_pk = Self::solana_parse_program_id(request.program_id.trim())?;
        let program_id = program_id_pk.to_string();
        let idl_name = crate::utils::solana_idl_registry::sanitize_name(request.name.trim());
        let instruction_name = request.instruction.trim().to_string();

        // 1) Build instruction (IDL)
        let idl = if let Some(ref idl_id) = request.idl_id {
            self.solana_idl_cache
                .get(idl_id.trim())
                .ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Unknown idl_id (not loaded)"),
                    data: Some(json!({"idl_id": idl_id})),
                })?
        } else {
            crate::utils::solana_idl_registry::read_idl(&program_id, &idl_name)?
        };
        let ix = crate::utils::solana_idl::normalize_idl_instruction(&idl, &instruction_name)?;

        // args in order
        let mut args_pairs: Vec<(crate::utils::solana_idl::IdlArg, Value)> = Vec::new();
        let mut missing_args: Vec<String> = Vec::new();
        for a in &ix.args {
            let v = request.args.get(&a.name).cloned();
            if v.is_none() {
                missing_args.push(a.name.clone());
                continue;
            }
            args_pairs.push((a.clone(), v.unwrap()));
        }
        if !missing_args.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required args"),
                data: Some(json!({"missing_args": missing_args})),
            });
        }

        let mut metas_json: Vec<Value> = Vec::new();
        let mut missing_accounts: Vec<String> = Vec::new();
        for a in &ix.accounts {
            let pk = request
                .accounts
                .get(&a.name)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            if pk.is_none() {
                missing_accounts.push(a.name.clone());
                continue;
            }
            let _ = Self::solana_parse_pubkey(pk.as_ref().unwrap(), &format!("account:{}", a.name))?;
            metas_json.push(json!({
                "name": a.name,
                "pubkey": pk,
                "is_signer": a.is_signer,
                "is_writable": a.is_mut
            }));
        }
        if !missing_accounts.is_empty() {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("Missing required accounts"),
                data: Some(json!({"missing_accounts": missing_accounts})),
            });
        }

        let data = crate::utils::solana_idl::encode_anchor_ix_data(&idl, &ix.name, &args_pairs)?;
        let data_b64 = base64::engine::general_purpose::STANDARD.encode(&data);

        // Optional on-chain checks
        let validate = request.validate_on_chain.unwrap_or(false);
        let mut onchain: Option<Value> = None;
        if validate {
            let client = Self::solana_rpc(Some(&network_str))?;
            let mut checks: Vec<Value> = Vec::new();
            for m in &metas_json {
                let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let pk_str = m.get("pubkey").and_then(|v| v.as_str()).unwrap_or("");
                let pk = Self::solana_parse_pubkey(pk_str, &format!("account:{}", name))?;
                let acc = client.get_account(&pk).await.ok();
                checks.push(json!({
                    "name": name,
                    "pubkey": pk.to_string(),
                    "exists": acc.is_some(),
                    "owner": acc.as_ref().map(|x| x.owner.to_string()),
                    "lamports": acc.as_ref().map(|x| x.lamports),
                    "data_len": acc.as_ref().map(|x| x.data.len()),
                    "executable": acc.as_ref().map(|x| x.executable),
                }));
            }
            onchain = Some(json!({"checks": checks}));
        }

        // 2) Build transaction
        let client = Self::solana_rpc(Some(&network_str))?;

        let sign = request.sign.unwrap_or(false);
        let kp_path = if sign { Some(Self::solana_keypair_path()?) } else { None };
        let kp = if sign {
            Some(Self::solana_read_keypair_from_json_file(kp_path.as_ref().unwrap())?)
        } else {
            None
        };

        let fee_payer = if let Some(fp) = request.fee_payer.as_deref() {
            Self::solana_parse_pubkey(fp.trim(), "fee_payer")?
        } else if let Some(ref k) = kp {
            solana_sdk::signature::Signer::pubkey(k)
        } else {
            return Err(ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from("fee_payer is required unless sign=true and SOLANA_KEYPAIR_PATH is set"),
                data: None,
            });
        };

        let recent_blockhash = if let Some(bh) = request.recent_blockhash.as_deref() {
            solana_sdk::hash::Hash::from_str(bh.trim()).map_err(|e| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Invalid recent_blockhash: {}", e)),
                data: None,
            })?
        } else {
            client
                .get_latest_blockhash()
                .await
                .map_err(|e| Self::sdk_error("solana_idl_execute", e))?
        };

        let account_metas = Self::solana_json_metas_to_account_metas(&metas_json)?;
        let ixn = solana_sdk::instruction::Instruction {
            program_id: program_id_pk,
            accounts: account_metas,
            data: data.clone(),
        };

        let message = solana_sdk::message::Message::new(&[ixn], Some(&fee_payer));
        let mut tx = solana_sdk::transaction::Transaction::new_unsigned(message);
        tx.message.recent_blockhash = recent_blockhash;
        if sign {
            let k = kp.as_ref().unwrap();
            tx.sign(&[k], recent_blockhash);
        }

        let tx_bytes = bincode::serialize(&tx).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Failed to serialize transaction: {}", e)),
            data: None,
        })?;
        let tx_base64 = base64::engine::general_purpose::STANDARD.encode(&tx_bytes);

        // 3) Send (or create pending)
        let confirm = request.confirm.unwrap_or(false);
        if !confirm {
            let created = crate::utils::solana_confirm_store::now_ms();
            let ttl = crate::utils::solana_confirm_store::default_ttl_ms();
            let expires = created + ttl;
            let hash = crate::utils::solana_confirm_store::tx_summary_hash(&tx_bytes);

            let id_seed = format!("{}:{}", created, hash);
            let id_suffix = crate::utils::solana_confirm_store::tx_summary_hash(id_seed.as_bytes());
            let confirmation_id = format!("solana_confirm_{}", &id_suffix[..16]);

            let summary = json!({
                "network": network_str,
                "rpc_url": rpc_url,
                "program_id": program_id,
                "idl_name": idl_name,
                "instruction": instruction_name,
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": sign
            });

            crate::utils::solana_confirm_store::insert_pending(
                &confirmation_id,
                &tx_base64,
                created,
                expires,
                &hash,
                "solana_idl_execute",
                Some(summary.clone()),
            )?;

            let response = Self::pretty_json(&json!({
                "ok": true,
                "stage": "send",
                "status": "pending",
                "rpc_url": rpc_url,
                "network": summary.get("network").unwrap(),
                "pending_confirmation_id": confirmation_id,
                "tx_summary_hash": hash,
                "instruction": {
                    "program_id": program_id,
                    "accounts": metas_json,
                    "data_base64": data_b64,
                    "validate_on_chain": validate,
                    "onchain": onchain
                },
                "transaction": {
                    "fee_payer": fee_payer.to_string(),
                    "recent_blockhash": recent_blockhash.to_string(),
                    "signed": sign,
                    "keypair_path": kp_path,
                    "transaction_base64": tx_base64,
                    "transaction_bytes_len": tx_bytes.len()
                },
                "expires_in_ms": ttl,
                "next": {
                    "confirm": {
                        "tool": "solana_confirm_transaction",
                        "args": {
                            "id": confirmation_id,
                            "hash": hash,
                            "commitment": request.commitment.clone().unwrap_or("confirmed".to_string())
                        }
                    },
                    "how_to_confirm": format!("solana_confirm_transaction id:{} hash:{}", confirmation_id, hash)
                }
            }))?;

            return Ok(CallToolResult::success(vec![Content::text(response)]));
        }

        // confirm=true: broadcast now
        let skip_preflight = request.skip_preflight.unwrap_or(false);
        let commitment = request.commitment.clone().unwrap_or("confirmed".to_string());
        let timeout_ms = request.timeout_ms.unwrap_or(60_000);

        // If tx isn't signed, attempt to sign if SOLANA_KEYPAIR_PATH exists.
        let mut tx2 = tx;
        Self::solana_try_sign_if_needed(&mut tx2, kp.as_ref());

        
        let sig = client
            .send_transaction_with_config(
                &tx2,
                solana_client::rpc_config::RpcSendTransactionConfig {
                    skip_preflight,
                    preflight_commitment: Some(
                        Self::solana_commitment_from_str(Some(&commitment))?.commitment,
                    ),
                    encoding: None,
                    max_retries: None,
                    min_context_slot: None,
                },
            )
            .await
            .map_err(|e| {
                let msg = e.to_string();
                let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                ErrorData {
                    code: ErrorCode(-32000),
                    message: Cow::from(format!("solana_idl_execute send error: {}", msg)),
                    data: Some(json!({
                        "error_class": error_class,
                        "suggest_fix": suggest_fix,
                        "skip_preflight": skip_preflight,
                        "commitment": commitment
                    })),
                }
            })?;

        let waited = Self::solana_wait_for_signature(&client, &sig, &commitment, timeout_ms)
            .await
            .map_err(|e| {
                // Preserve original error but add classification.
                let msg = e.message.to_string();
                let (error_class, suggest_fix) = Self::solana_classify_send_error(&msg);
                ErrorData {
                    code: e.code,
                    message: e.message,
                    data: Some(json!({
                        "error_class": error_class,
                        "suggest_fix": suggest_fix,
                        "timeout_ms": timeout_ms
                    })),
                }
            })?;

        let status = waited
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");

        let response = Self::pretty_json(&json!({
            "ok": true,
            "stage": "send",
            "status": status,
            "rpc_url": rpc_url,
            "network": network_str,
            "signature": sig.to_string(),
            "commitment": commitment,
            "wait": waited,
            "instruction": {
                "program_id": program_id,
                "accounts": metas_json,
                "data_base64": data_b64,
                "validate_on_chain": validate,
                "onchain": onchain
            },
            "transaction": {
                "fee_payer": fee_payer.to_string(),
                "recent_blockhash": recent_blockhash.to_string(),
                "signed": true,
                "keypair_path": kp_path,
                "transaction_base64": tx_base64,
                "transaction_bytes_len": tx_bytes.len()
            }
        }))?;

        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
