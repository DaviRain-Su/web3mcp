    /// Auto-generated tool: graphql helper
    #[tool(description = "Auto-generated tool: graphql helper")]
    async fn graphql_helper(
        &self,
        Parameters(request): Parameters<GraphqlHelperRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let endpoint = request
            .endpoint
            .or_else(|| std::env::var("SUI_GRAPHQL_URL").ok())
            .unwrap_or_else(|| "https://graphql.mainnet.sui.io/graphql".to_string());
        let client = GraphqlClient::new(&endpoint).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("GraphQL client error: {}", e)),
            data: None,
        })?;

        let selection = request.selection.clone();
        let (query, variables) = match request.helper.as_str() {
            "chain_info" => {
                let selection = selection.unwrap_or_else(|| "chainIdentifier".to_string());
                (format!("query {{ {} }}", selection), json!({}))
            }
            "object" => {
                let object_id = request.object_id.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("object_id is required for object helper"),
                    data: None,
                })?;
                let selection = selection.unwrap_or_else(|| "address digest version".to_string());
                (
                    format!("query($id: SuiAddress!) {{ object(address: $id) {{ {} }} }}", selection),
                    json!({"id": object_id}),
                )
            }
            "balance" => {
                let address = request.address.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("address is required for balance helper"),
                    data: None,
                })?;
                let selection = selection.unwrap_or_else(|| "totalBalance coinType".to_string());
                (
                    format!("query($address: SuiAddress!) {{ address(address: $address) {{ balances {{ {} }} }} }}", selection),
                    json!({"address": address}),
                )
            }
            "transaction" => {
                let digest = request.digest.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("digest is required for transaction helper"),
                    data: None,
                })?;
                let selection = selection.unwrap_or_else(|| "digest effects { status }".to_string());
                (
                    format!("query($digest: String!) {{ transactionBlock(digest: $digest) {{ {} }} }}", selection),
                    json!({"digest": digest}),
                )
            }
            "checkpoint" => {
                let checkpoint = request.checkpoint.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("checkpoint is required for checkpoint helper"),
                    data: None,
                })?;
                let selection = selection.unwrap_or_else(|| "sequenceNumber digest".to_string());
                (
                    format!("query($sequence: BigInt!) {{ checkpoint(sequenceNumber: $sequence) {{ {} }} }}", selection),
                    json!({"sequence": checkpoint}),
                )
            }
            "events" => {
                let selection = selection.unwrap_or_else(|| "edges { node { id } }".to_string());
                let limit = request.limit.unwrap_or(10);
                (
                    format!("query($limit: Int!) {{ events(first: $limit) {{ {} }} }}", selection),
                    json!({"limit": limit}),
                )
            }
            "coins" => {
                let address = request.address.ok_or_else(|| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("address is required for coins helper"),
                    data: None,
                })?;
                let selection = selection.unwrap_or_else(|| "nodes { balance coinType }".to_string());
                (
                    format!("query($address: SuiAddress!) {{ address(address: $address) {{ coins {{ {} }} }} }}", selection),
                    json!({"address": address}),
                )
            }
            other => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Unknown helper: {}", other)),
                    data: None,
                })
            }
        };

        let response = client
            .query::<Value>(&query, variables)
            .await
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("GraphQL query failed: {}", e)),
                data: None,
            })?;

        let errors = response
            .errors()
            .iter()
            .map(|err| {
                let locations = err.locations().map(|locs| {
                    locs.iter()
                        .map(|loc| json!({"line": loc.line, "column": loc.column}))
                        .collect::<Vec<_>>()
                });
                let path = err.path().map(|path| {
                    path.iter()
                        .map(|fragment| match fragment {
                            sui_graphql::PathFragment::Key(key) => json!(key),
                            sui_graphql::PathFragment::Index(index) => json!(index),
                        })
                        .collect::<Vec<_>>()
                });

                json!({
                    "message": err.message(),
                    "locations": locations,
                    "path": path,
                    "extensions": err.extensions(),
                    "code": err.code()
                })
            })
            .collect::<Vec<_>>();

        let payload = json!({
            "endpoint": endpoint,
            "helper": request.helper,
            "query": query,
            "data": response.data().cloned(),
            "errors": errors,
            "has_errors": response.has_errors()
        });
        let response = Self::pretty_json(&payload)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Execute a GraphQL query
    #[tool(description = "Execute a GraphQL query against a Sui GraphQL endpoint")]
    async fn graphql_query(
        &self,
        Parameters(request): Parameters<GraphqlQueryRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let endpoint = request
            .endpoint
            .or_else(|| std::env::var("SUI_GRAPHQL_URL").ok())
            .unwrap_or_else(|| "https://graphql.mainnet.sui.io/graphql".to_string());
        let client = GraphqlClient::new(&endpoint).map_err(|e| ErrorData {
            code: ErrorCode(-32603),
            message: Cow::from(format!("GraphQL client error: {}", e)),
            data: None,
        })?;
        let variables = request.variables.unwrap_or_else(|| json!({}));
        let response = client
            .query::<Value>(&request.query, variables)
            .await
            .map_err(|e| ErrorData {
                code: ErrorCode(-32603),
                message: Cow::from(format!("GraphQL query failed: {}", e)),
                data: None,
            })?;

        let errors = response
            .errors()
            .iter()
            .map(|err| {
                let locations = err.locations().map(|locs| {
                    locs.iter()
                        .map(|loc| json!({"line": loc.line, "column": loc.column}))
                        .collect::<Vec<_>>()
                });
                let path = err.path().map(|path| {
                    path.iter()
                        .map(|fragment| match fragment {
                            sui_graphql::PathFragment::Key(key) => json!(key),
                            sui_graphql::PathFragment::Index(index) => json!(index),
                        })
                        .collect::<Vec<_>>()
                });

                json!({
                    "message": err.message(),
                    "locations": locations,
                    "path": path,
                    "extensions": err.extensions(),
                    "code": err.code()
                })
            })
            .collect::<Vec<_>>();

        let payload = json!({
            "endpoint": endpoint,
            "data": response.data().cloned(),
            "errors": errors,
            "has_errors": response.has_errors()
        });
        let response = Self::pretty_json(&payload)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
