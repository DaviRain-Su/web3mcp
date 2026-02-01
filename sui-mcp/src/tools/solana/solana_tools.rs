    fn solana_rpc_url() -> String {
        // Priority:
        // 1) SOLANA_RPC_URL
        // 2) default to mainnet-beta public endpoint (safe, but rate-limited)
        std::env::var("SOLANA_RPC_URL")
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

    #[tool(description = "Solana: get wallet address from SOLANA_KEYPAIR_PATH JSON")]
    async fn solana_get_wallet_address(&self) -> Result<CallToolResult, ErrorData> {
        let kp_path = Self::solana_keypair_path()?;
        let kp = Self::solana_read_keypair_from_json_file(&kp_path)?;
        let addr = solana_sdk::signature::Signer::pubkey(&kp).to_string();
        let response = Self::pretty_json(&json!({
            "rpc_url": Self::solana_rpc_url(),
            "keypair_path": kp_path,
            "address": addr
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
