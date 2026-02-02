    /// Auto-generated tool: get checkpoint
    #[tool(description = "Auto-generated tool: get checkpoint")]
    async fn get_checkpoint(
        &self,
        Parameters(request): Parameters<GetCheckpointRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let checkpoint_id = match (request.sequence_number, request.digest) {
            (Some(seq), None) => CheckpointId::SequenceNumber(seq),
            (None, Some(digest)) => {
                let digest = Self::parse_checkpoint_digest(&digest)?;
                CheckpointId::Digest(digest)
            }
            _ => {
                return Err(ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from("Provide either sequence_number or digest"),
                    data: None,
                })
            }
        };

        let result = self
            .client
            .read_api()
            .get_checkpoint(checkpoint_id)
            .await
            .map_err(|e| Self::sdk_error("get_checkpoint", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }

    /// Get checkpoints page
    #[tool(description = "Get a page of checkpoints")]
    async fn get_checkpoints(
        &self,
        Parameters(request): Parameters<GetCheckpointsRequest>,
    ) -> Result<CallToolResult, ErrorData> {
        let cursor = request.cursor.map(BigInt::from);
        let limit = request.limit.map(|limit| Self::clamp_limit(Some(limit), limit, 100));
        let descending = request.descending_order.unwrap_or(false);

        let result = self
            .client
            .read_api()
            .get_checkpoints(cursor, limit, descending)
            .await
            .map_err(|e| Self::sdk_error("get_checkpoints", e))?;

        let response = Self::pretty_json(&result)?;
        Ok(CallToolResult::success(vec![Content::text(response)]))
    }
