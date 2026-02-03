use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug)]
pub struct RunStore {
    root: PathBuf,
}

impl RunStore {
    pub fn new() -> Self {
        // Keep default location stable and local.
        // Users can override with WEB3MCP_RUNS_DIR.
        let root = std::env::var("WEB3MCP_RUNS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = std::env::var("HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|_| PathBuf::from("."));
                home.join(".web3mcp").join("runs")
            });
        Self { root }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn new_run_id(&self) -> String {
        // Deterministic enough for local runs; not security-sensitive.
        let now_ms = crate::utils::evm_confirm_store::now_ms();
        let rand = (now_ms ^ 0x9e3779b97f4a7c15) & 0xfffff;
        format!("run_{}_{}", now_ms, rand)
    }

    pub fn ensure_run_dir(&self, run_id: &str) -> Result<PathBuf, std::io::Error> {
        let dir = self.root.join(run_id);
        fs::create_dir_all(&dir)?;
        Ok(dir)
    }

    pub fn write_stage_artifact(
        &self,
        run_id: &str,
        stage: &str,
        value: &Value,
    ) -> Result<PathBuf, std::io::Error> {
        let dir = self.ensure_run_dir(run_id)?;
        let path = dir.join(format!("stage_{}.json", stage));
        let bytes = serde_json::to_vec_pretty(value).unwrap_or_else(|_| b"{}".to_vec());
        fs::write(&path, bytes)?;
        Ok(path)
    }
}
