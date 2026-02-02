use anyhow::Result;
use rmcp::service::RequestContext;
use rmcp::RoleServer;

#[path = "intent/adapters.rs"]
mod intent_adapters;
// (moved) Base64Engine/Engine + various chain/tool types imported via router_prelude
use rmcp::{
    handler::server::wrapper::Parameters, model::*, prompt_handler, tool, tool_handler,
    tool_router, ServerHandler, ServiceExt,
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
// SuiClient is part of Web3McpServer in src/server.rs
// (moved) digests parsing in utils/sui_parse.rs
// (moved) dynamic_field helpers in src/sui/dynamic_fields.rs
use tracing::info;
use tracing_subscriber::EnvFilter;

// Web3McpServer struct moved to src/server.rs

impl Web3McpServer {
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
mod prompts;
mod router_prelude;
mod server;
mod sui;
mod types;
mod types_solana_idl_dynamic;
mod utils;

// Bring required identifiers for generated router into scope.
use router_prelude::*;

// AutoFilledMoveCall type lives in move_auto_fill.rs (router_impl can still see it via crate path)

pub use server::Web3McpServer;
pub use types::*;
pub use types_solana_idl_dynamic::*;

// AutoFilledMoveCall moved to src/move_auto_fill.rs

include!(concat!(env!("OUT_DIR"), "/router_impl.rs"));

#[tool_handler]
#[prompt_handler(router = self.prompt_router)]
impl ServerHandler for Web3McpServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::V_2024_11_05,
            capabilities: ServerCapabilities::builder()
                .enable_tools()
                .enable_prompts()
                .build(),
            server_info: Implementation::from_build_env(),
            instructions: Some(
                "A multi-chain Web3 MCP server (Sui + Solana + EVM).\n\n".to_string(),
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

    // Create Web3MCP server
    let server = Web3McpServer::new(rpc_url, network).await?;

    info!("Starting Web3MCP Server");
    info!("Using RPC URL: {}", server.rpc_url);

    // Transport selection
    let mut args = std::env::args().skip(1);
    let mut use_sse = false;
    let mut sse_bind: Option<String> = None;
    let mut sse_path: Option<String> = None;
    let mut post_path: Option<String> = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--sse" => use_sse = true,
            "--sse-bind" => sse_bind = args.next(),
            "--sse-path" => sse_path = args.next(),
            "--post-path" => post_path = args.next(),
            "-h" | "--help" => {
                println!(concat!(
                    "web3mcp\n\n",
                    "USAGE:\n",
                    "  web3mcp                # stdio (default)\n",
                    "  web3mcp --sse           # SSE server (HTTP)\n\n",
                    "SSE OPTIONS:\n",
                    "  --sse-bind <addr>       # default: 127.0.0.1:8000\n",
                    "  --sse-path <path>       # default: /sse\n",
                    "  --post-path <path>      # default: /message\n\n",
                    "ENV (Sui):\n",
                    "  SUI_RPC_URL / SUI_NETWORK\n"
                ));
                return Ok(());
            }
            other => {
                // Unknown args are ignored for now to keep integration flexible.
                tracing::debug!(arg = other, "Ignoring unknown CLI arg");
            }
        }
    }

    if use_sse {
        use rmcp::transport::sse_server::SseServerConfig;
        use rmcp::transport::SseServer;
        use tokio_util::sync::CancellationToken;

        let bind = sse_bind
            .or_else(|| std::env::var("WEB3MCP_SSE_BIND").ok())
            .unwrap_or_else(|| "127.0.0.1:8000".to_string());
        let bind = bind.parse()?;
        let sse_path = sse_path.unwrap_or_else(|| "/sse".to_string());
        let post_path = post_path.unwrap_or_else(|| "/message".to_string());

        let sse = SseServer::serve_with_config(SseServerConfig {
            bind,
            sse_path: sse_path.clone(),
            post_path: post_path.clone(),
            ct: CancellationToken::new(),
            sse_keep_alive: None,
        })
        .await?;

        let server_clone = server.clone();
        let ct = sse.with_service(move || server_clone.clone());

        info!(
            "Web3MCP SSE server running on http://{}{} (POST to {}?sessionId=...)",
            bind, sse_path, post_path
        );

        tokio::signal::ctrl_c().await?;
        ct.cancel();
        Ok(())
    } else {
        // Default: serve via stdio
        let service = server.serve(rmcp::transport::stdio()).await?;
        info!("Web3MCP Server running and ready to accept requests");
        service.waiting().await?;
        Ok(())
    }
}
