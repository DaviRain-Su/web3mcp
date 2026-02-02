#![allow(dead_code)]

pub trait ChainAdapter {
    fn name(&self) -> &'static str;
    fn supports(&self, action: &str) -> bool;
}

pub struct SuiAdapter;

impl ChainAdapter for SuiAdapter {
    fn name(&self) -> &'static str {
        "sui"
    }

    fn supports(&self, action: &str) -> bool {
        matches!(
            action,
            "transfer" | "swap" | "stake" | "unstake" | "pay" | "query"
        )
    }
}

pub struct EvmAdapter;

impl ChainAdapter for EvmAdapter {
    fn name(&self) -> &'static str {
        "evm"
    }

    fn supports(&self, _action: &str) -> bool {
        false
    }
}

pub struct SolanaAdapter;

impl ChainAdapter for SolanaAdapter {
    fn name(&self) -> &'static str {
        "solana"
    }

    fn supports(&self, _action: &str) -> bool {
        false
    }
}
