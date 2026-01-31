// Helper methods for Move resolution tools.
//
// This file is stitched into `router_impl.rs` by build.rs in a plain `impl SuiMcpServer { ... }`
// block (NOT the #[tool_router] impl), so it can freely define helper methods.

    fn parse_type_args_to_typetag(type_args: Vec<String>) -> Result<Vec<TypeTag>, ErrorData> {
        type_args
            .into_iter()
            .enumerate()
            .map(|(index, arg)| {
                SuiTypeTag::new(arg).try_into().map_err(|e| ErrorData {
                    code: ErrorCode(-32602),
                    message: Cow::from(format!("Invalid type arg at index {}: {}", index, e)),
                    data: None,
                })
            })
            .collect::<Result<Vec<TypeTag>, _>>()
    }
