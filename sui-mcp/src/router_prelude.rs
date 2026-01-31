//! Names that must be in scope for the generated `router_impl.rs`.
//
// The MCP router code is generated and `include!`'d from `main.rs`, so it resolves
// identifiers against the `main.rs` module scope. Keep these re-exports here to
// avoid bloating `main.rs` with "magic" imports.

pub use base64::engine::general_purpose::STANDARD as Base64Engine;
pub use base64::Engine;

pub use move_core_types::language_storage::{StructTag, TypeTag};

pub use sui_json_rpc_types::{SuiObjectDataOptions, SuiObjectResponseQuery};

pub use sui_types::base_types::ObjectID;
pub use sui_types::object::Owner;
