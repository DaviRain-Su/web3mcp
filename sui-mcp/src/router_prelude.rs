//! Names that must be in scope for the generated `router_impl.rs`.
//
// The MCP router code is generated and `include!`'d from `main.rs`, so it resolves
// identifiers against the `main.rs` module scope. Keep these re-exports here to
// avoid bloating `main.rs` with "magic" imports.

pub use base64::engine::general_purpose::STANDARD as Base64Engine;
pub use base64::Engine;

pub use move_core_types::language_storage::{StructTag, TypeTag};

pub use sui_json_rpc_types::{
    CheckpointId,
    DryRunTransactionBlockResponse,
    EventFilter,
    RPCTransactionRequestParams,
    // (Move normalized types live in move_schema.rs; keep router prelude minimal)
    SuiObjectDataOptions,
    SuiObjectResponseQuery,
    SuiTransactionBlockEffectsAPI,
    SuiTransactionBlockResponse,
    SuiTransactionBlockResponseOptions,
    SuiTransactionBlockResponseQuery,
    SuiTypeTag,
    TransactionFilter,
    ZkLoginIntentScope,
};

pub use sui_sdk_types::SimpleSignature;

pub use sui_types::base_types::{ObjectID, SequenceNumber, SuiAddress};
pub use sui_types::crypto::{Signature, ToFromBytes};
pub use sui_types::object::Owner;
pub use sui_types::programmable_transaction_builder::ProgrammableTransactionBuilder;
pub use sui_types::signature::GenericSignature;
pub use sui_types::sui_serde::BigInt;
pub use sui_types::transaction::{
    CallArg, ObjectArg, Transaction, TransactionData, TransactionDataAPI,
};
pub use sui_types::zk_login_authenticator::ZkLoginAuthenticator;
