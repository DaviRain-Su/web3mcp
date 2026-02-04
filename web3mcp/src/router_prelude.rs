//! Names that must be in scope for the generated `router_impl.rs`.
//
// The MCP router code is generated and `include!`'d from `main.rs`, so it resolves
// identifiers against the `main.rs` module scope. Keep these re-exports here to
// avoid bloating `main.rs` with "magic" imports.
//
// CI runs clippy with `-D warnings`; this module is intentionally a broad prelude
// and may contain items not used by the current generated router.
#![allow(unused_imports)]

pub use base64::engine::general_purpose::STANDARD as Base64Engine;
pub use base64::Engine;

pub use serde_json::{json, Value};

pub use std::borrow::Cow;
pub use std::collections::HashMap;
pub use std::str::FromStr;

pub use fastcrypto_zkp::bn254::zk_login::ZkLoginInputs;

pub use move_core_types::identifier::Identifier;
pub use move_core_types::language_storage::{StructTag, TypeTag};

pub use sui_crypto::simple::SimpleVerifier;
pub use sui_crypto::Verifier;

pub use sui_graphql::Client as GraphqlClient;

pub use sui_json::SuiJsonValue;

pub use sui_json_rpc_types::{
    CheckpointId, DryRunTransactionBlockResponse, EventFilter, RPCTransactionRequestParams,
    SuiMoveNormalizedFunction, SuiMoveNormalizedModule, SuiObjectDataOptions,
    SuiObjectResponseQuery, SuiTransactionBlockEffectsAPI, SuiTransactionBlockResponse,
    SuiTransactionBlockResponseOptions, SuiTransactionBlockResponseQuery, SuiTypeTag,
    TransactionFilter, ZkLoginIntentScope,
};

pub use sui_keys::keystore::AccountKeystore;

pub use sui_rpc::proto::sui::rpc::v2::GetServiceInfoRequest as RpcGetServiceInfoRequest;
pub use sui_rpc::Client as RpcClient;

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

pub use ethers::signers::Signer as EthersSigner;
