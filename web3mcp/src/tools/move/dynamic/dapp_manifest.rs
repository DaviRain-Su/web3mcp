    #[tool(description = "List dapps from the manifest")]
    async fn list_dapps(
        &self,
        Parameters(request): Parameters<DappManifestRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let manifest = self.load_dapp_manifest(request.path.as_deref())?;
        let dapps = manifest
            .dapps
            .into_iter()
            .map(|entry| {
                json!({
                    "name": entry.name,
                    "package": entry.package,
                    "modules": entry.modules,
                    "functions": entry.functions
                })
            })
            .collect::<Vec<_>>();
        let response = Self::pretty_json(&json!({"dapps": dapps}))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    #[tool(description = "Generate an auto-filled move_call payload from a dapp manifest")]
    async fn dapp_move_call_payload(
        &self,
        Parameters(request): Parameters<DappMoveCallRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let manifest = self.load_dapp_manifest(request.manifest_path.as_deref())?;
        let entry = manifest
            .dapps
            .iter()
            .find(|entry| entry.name == request.dapp)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Dapp not found: {}", request.dapp)),
                data: None,
            })?;

        let fill_request = AutoFillMoveCallRequest {
            sender: request.sender.clone(),
            package: entry.package.clone(),
            module: request.module.clone(),
            function: request.function.clone(),
            type_args: request.type_args.clone(),
            arguments: request.arguments.clone(),
            gas_budget: request.gas_budget,
            gas_object_id: request.gas_object_id.clone(),
            gas_price: request.gas_price,
        };

        let filled = self.auto_fill_move_call_internal(&fill_request).await?;
        let payload = json!({
            "sender": fill_request.sender,
            "package": entry.package,
            "module": fill_request.module,
            "function": fill_request.function,
            "type_args": filled.type_args,
            "arguments": filled.arguments,
            "gas_budget": filled.gas_budget,
            "gas_object_id": filled.gas_object_id,
            "gas_price": filled.gas_price
        });

        let response = Self::pretty_json(&json!({
            "payload": payload,
            "warnings": filled.warnings,
            "gas": filled.gas
        }))?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    fn load_dapp_manifest(
        &self,
        path: Option<&str>,
    ) -> Result<DappManifest, ErrorData> {
        let manifest_path = if let Some(path) = path {
            std::path::PathBuf::from(path)
        } else if let Ok(env_path) = std::env::var("SUI_DAPP_MANIFEST") {
            std::path::PathBuf::from(env_path)
        } else {
            std::path::PathBuf::from("dapps.json")
        };

        let contents = std::fs::read_to_string(&manifest_path).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!(
                "Failed to read dapp manifest {}: {}",
                manifest_path.display(),
                e
            )),
            data: None,
        })?;

        serde_json::from_str::<DappManifest>(&contents).map_err(|e| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!(
                "Invalid dapp manifest {}: {}",
                manifest_path.display(),
                e
            )),
            data: None,
        })
    }
