// Helper methods for Move resolution tools.
//
// This file is stitched into `router_impl.rs` by build.rs in a plain `impl SuiMcpServer { ... }`
// block (NOT the #[tool_router] impl), so it can freely define helper methods.

    async fn load_normalized_move_modules(
        &self,
        package: ObjectID,
        context: &str,
    ) -> Result<std::collections::BTreeMap<String, SuiMoveNormalizedModule>, ErrorData> {
        self.client
            .read_api()
            .get_normalized_move_modules_by_package(package)
            .await
            .map_err(|e| Self::sdk_error(context, e))
    }

    fn get_normalized_move_function_def<'a>(
        modules: &'a std::collections::BTreeMap<String, SuiMoveNormalizedModule>,
        module: &str,
        function: &str,
    ) -> Result<(&'a SuiMoveNormalizedModule, &'a SuiMoveNormalizedFunction), ErrorData> {
        let module_def = modules.get(module).ok_or_else(|| ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from(format!("Module not found: {}", module)),
            data: None,
        })?;

        let function_def = module_def
            .exposed_functions
            .get(function)
            .ok_or_else(|| ErrorData {
                code: ErrorCode(-32602),
                message: Cow::from(format!("Function not found: {}", function)),
                data: None,
            })?;

        Ok((module_def, function_def))
    }

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
