// Intentionally separated to keep types.rs manageable.
// Re-exported from types.rs.

use serde::Deserialize;

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlLoadRequest {
    #[schemars(description = "Program id (base58). Optional; used for metadata only")]
    pub program_id: Option<String>,

    #[schemars(description = "IDL JSON string")]
    pub idl_json: Option<String>,

    #[schemars(description = "IDL JSON base64 (STANDARD)")]
    pub idl_base64: Option<String>,

    #[schemars(description = "IDL URL (http/https)")]
    pub idl_url: Option<String>,

    #[schemars(description = "Local IDL file path")]
    pub idl_path: Option<String>,

    #[schemars(
        description = "If true, also write into abi_registry/solana/<program_id>/<name>.json (requires program_id)"
    )]
    pub persist: Option<bool>,

    #[schemars(description = "If persist=true, optional registry name key")]
    pub name: Option<String>,

    #[schemars(description = "If persist=true, allow overwrite")]
    pub overwrite: Option<bool>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlUnloadRequest {
    #[schemars(description = "IDL handle returned by solana_idl_load")]
    pub idl_id: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SolanaIdlListInstructionsRequest {
    #[schemars(description = "IDL handle returned by solana_idl_load")]
    pub idl_id: String,
}
