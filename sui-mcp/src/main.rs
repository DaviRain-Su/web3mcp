use anyhow::Result;

#[path = "intent/adapters.rs"]
mod intent_adapters;
// (moved) Base64Engine/Engine + various chain/tool types imported via router_prelude
use rmcp::{
    handler::server::wrapper::Parameters, model::*, tool, tool_handler, tool_router, ServerHandler,
    ServiceExt,
};
// (moved) tool request schemas live in src/types.rs
// (moved) Future used in src/sui/dynamic_fields.rs
// (moved) std::io::Write used in utils/audit.rs
// (moved) Pin used in src/sui/dynamic_fields.rs
// (moved) FromStr used by some helpers
// (moved) SystemTime/UNIX_EPOCH used in utils/audit.rs
// (moved) SimpleVerifier/Verifier + GraphQL client imported via router_prelude
// (moved) SuiJsonValue parsing in utils/sui_parse.rs
// (moved) Many Sui/Sui-types imports are provided via router_prelude for generated router_impl.rs
// SuiClient is part of SuiMcpServer in src/server.rs
// (moved) digests parsing in utils/sui_parse.rs
// (moved) dynamic_field helpers in src/sui/dynamic_fields.rs
use tracing::info;
use tracing_subscriber::EnvFilter;

// SuiMcpServer struct moved to src/server.rs

impl SuiMcpServer {
    // Utilities moved to src/utils/* (json/errors)

    async fn preflight_tx_data(
        &self,
        tx_data: &TransactionData,
    ) -> Result<DryRunTransactionBlockResponse, ErrorData> {
        self.client
            .read_api()
            .dry_run_transaction_block(tx_data.clone())
            .await
            .map_err(|e| Self::sdk_error("preflight_tx", e))
    }

    // Utilities moved to src/utils/errors.rs

    // Utilities moved to src/utils/audit.rs

    // Utilities moved to src/utils/base64.rs

    // Utilities moved to src/utils/sui_parse.rs and src/utils/json.rs

    // Sui tx/object helpers moved to src/sui/tx.rs

    // Dynamic field helpers moved to src/sui/dynamic_fields.rs

    // Move schema/helpers moved to src/move_schema.rs

    // resolve_network moved to src/utils/network.rs

    // auto_fill_move_call_internal moved to src/move_auto_fill.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move schema/helpers moved to src/move_schema.rs

    // Move type-arg inference helpers moved to src/move_type_args.rs

    // Dynamic field helpers moved to src/sui/dynamic_fields.rs
}

mod move_auto_fill;
mod move_schema;
mod move_type_args;
mod router_prelude;
mod server;
mod sui;
mod types;
mod types_solana_idl_dynamic;
mod utils;

// Bring required identifiers for generated router into scope.
use router_prelude::*;

// AutoFilledMoveCall type lives in move_auto_fill.rs (router_impl can still see it via crate path)

pub use server::SuiMcpServer;
pub use types::*;
pub use types_solana_idl_dynamic::*;

// AutoFilledMoveCall moved to src/move_auto_fill.rs

include!(concat!(env!("OUT_DIR"), "/router_impl.rs"));
#[tool_handler]
impl ServerHandler for SuiMcpServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::V_2024_11_05,
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            server_info: Implementation::from_build_env(),
            instructions: Some(
                "A Sui blockchain MCP server providing tools for querying the Sui network. \
                 Use the available tools to get balances, objects, transactions, and other blockchain data."
                    .to_string(),
            ),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    // Get RPC URL or network from environment variable if provided
    let rpc_url = std::env::var("SUI_RPC_URL").ok();
    let network = std::env::var("SUI_NETWORK").ok();

    // Create Sui MCP server
    let server = SuiMcpServer::new(rpc_url, network).await?;

    info!("Starting Sui MCP Server");
    info!("Using RPC URL: {}", server.rpc_url);

    // Serve the MCP server via stdio
    let service = server.serve(rmcp::transport::stdio()).await?;

    info!("Sui MCP Server running and ready to accept requests");

    // Wait for server to finish
    service.waiting().await?;

    Ok(())
}
