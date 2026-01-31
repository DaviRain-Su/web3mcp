    /// Auto-generated tool: verify simple signature
    #[tool(description = "Auto-generated tool: verify simple signature")]
    async fn verify_simple_signature(
        &self,
        Parameters(request): Parameters<VerifySimpleSignatureRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let message = Self::decode_base64("message_base64", &request.message_base64)?;
        let signature: SimpleSignature = serde_json::from_str(&format!(
            "\"{}\"",
            request.signature_base64
        ))
        .map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Invalid signature: {}", e)),
            data: None,
        })?;

        let verifier = SimpleVerifier;
        verifier.verify(&message, &signature).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("Signature verification failed: {}", e)),
            data: None,
        })?;

        let response = Self::pretty_json(&json!({
            "valid": true
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
