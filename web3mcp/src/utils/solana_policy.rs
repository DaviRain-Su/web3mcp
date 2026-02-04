use rmcp::model::{ErrorCode, ErrorData};
use serde::Deserialize;
use std::borrow::Cow;

#[derive(Debug, Clone, Deserialize)]
pub struct SolanaConfirmPolicy {
    #[serde(default = "default_mode")]
    pub mode: String, // off|warn|block

    #[serde(default)]
    pub swap: SwapPolicy,

    #[serde(default)]
    pub program_policy: ProgramPolicy,

    #[serde(default)]
    pub admin_override: AdminOverridePolicy,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SwapPolicy {
    #[serde(default)]
    pub block_system_transfer: BlockSystemTransferPolicy,

    #[serde(default)]
    pub ata_owner_mint: AtaOwnerMintPolicy,

    #[serde(default)]
    pub token_authority: TokenAuthorityPolicy,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BlockSystemTransferPolicy {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub max_lamports: u64,
}
impl Default for BlockSystemTransferPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            max_lamports: 0,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct AtaOwnerMintPolicy {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_ata_mint_mode")]
    pub mint_mode: String, // input_output|any
}
impl Default for AtaOwnerMintPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            mint_mode: "input_output".to_string(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct TokenAuthorityPolicy {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_token_authority_mode")]
    pub mode: String, // strict|relaxed
}
impl Default for TokenAuthorityPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            mode: "strict".to_string(),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProgramPolicy {
    #[serde(default)]
    pub deny: Vec<String>,
    #[serde(default)]
    pub allow: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AdminOverridePolicy {
    #[serde(default)]
    pub blocked_confirm_admin_pubkeys: Vec<String>,

    #[serde(default = "default_true")]
    pub require_fee_payer_match: bool,

    #[serde(default = "default_true")]
    pub require_authority_match: bool,
}
impl Default for AdminOverridePolicy {
    fn default() -> Self {
        Self {
            blocked_confirm_admin_pubkeys: vec![],
            require_fee_payer_match: true,
            require_authority_match: true,
        }
    }
}

fn default_true() -> bool {
    true
}
fn default_mode() -> String {
    "block".to_string()
}
fn default_ata_mint_mode() -> String {
    "input_output".to_string()
}
fn default_token_authority_mode() -> String {
    "strict".to_string()
}

fn policy_path_from_cwd() -> Result<std::path::PathBuf, ErrorData> {
    let cwd = std::env::current_dir().map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to get current_dir: {e}")),
        data: None,
    })?;
    Ok(cwd.join("policies").join("solana_confirm_policy.json"))
}

pub fn load_solana_confirm_policy() -> SolanaConfirmPolicy {
    let path = match policy_path_from_cwd() {
        Ok(p) => p,
        Err(_) => return SolanaConfirmPolicy::default_fallback(),
    };

    let s = match std::fs::read_to_string(&path) {
        Ok(v) => v,
        Err(_) => return SolanaConfirmPolicy::default_fallback(),
    };

    serde_json::from_str::<SolanaConfirmPolicy>(&s)
        .unwrap_or_else(|_| SolanaConfirmPolicy::default_fallback())
}

impl SolanaConfirmPolicy {
    pub fn default_fallback() -> Self {
        Self {
            mode: default_mode(),
            swap: SwapPolicy::default(),
            program_policy: ProgramPolicy::default(),
            admin_override: AdminOverridePolicy::default(),
        }
    }

    pub fn is_mode_off(&self) -> bool {
        self.mode.trim().eq_ignore_ascii_case("off")
    }

    pub fn is_mode_block(&self) -> bool {
        self.mode.trim().eq_ignore_ascii_case("block")
    }
}
