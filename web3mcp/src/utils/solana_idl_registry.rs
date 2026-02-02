use rmcp::model::{ErrorCode, ErrorData};
use serde_json::Value;
use std::borrow::Cow;

pub fn registry_root() -> std::path::PathBuf {
    if let Ok(dir) = std::env::var("SOLANA_IDL_REGISTRY_DIR") {
        return std::path::PathBuf::from(dir);
    }
    // mirror EVM default layout
    std::path::PathBuf::from("./abi_registry/solana")
}

pub fn sanitize_name(name: &str) -> String {
    // keep it filesystem-safe and deterministic
    name.trim()
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'a'..='z' | '0'..='9' | '-' | '_' | '.' => c,
            _ => '-',
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string()
}

pub fn infer_name_from_idl_json(idl: &Value) -> Option<String> {
    // Anchor-style: { "metadata": { "name": "..." } }
    idl.get("metadata")
        .and_then(|m| m.get("name"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| {
            // Some IDLs use top-level "name"
            idl.get("name")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        })
}

pub fn program_dir(program_id: &str) -> std::path::PathBuf {
    registry_root().join(program_id)
}

pub fn idl_path(program_id: &str, name: &str) -> std::path::PathBuf {
    program_dir(program_id).join(format!("{}.json", name))
}

pub fn write_idl(
    program_id: &str,
    name: &str,
    idl_json: &Value,
    overwrite: bool,
) -> Result<std::path::PathBuf, ErrorData> {
    let dir = program_dir(program_id);
    std::fs::create_dir_all(&dir).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to create idl registry dir: {}", e)),
        data: None,
    })?;

    let path = idl_path(program_id, name);
    if path.exists() && !overwrite {
        return Err(ErrorData {
            code: ErrorCode(-32602),
            message: Cow::from("IDL already exists (set overwrite=true to replace)"),
            data: Some(serde_json::json!({
                "program_id": program_id,
                "name": name,
                "path": path.to_string_lossy()
            })),
        });
    }

    let pretty = serde_json::to_string_pretty(idl_json).unwrap_or_else(|_| "{}".to_string());
    std::fs::write(&path, pretty).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to write IDL file: {}", e)),
        data: None,
    })?;

    Ok(path)
}

pub fn read_idl(program_id: &str, name: &str) -> Result<Value, ErrorData> {
    let path = idl_path(program_id, name);
    let data = std::fs::read_to_string(&path).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to read IDL file: {}", e)),
        data: Some(serde_json::json!({
            "program_id": program_id,
            "name": name,
            "path": path.to_string_lossy()
        })),
    })?;
    serde_json::from_str(&data).map_err(|e| ErrorData {
        code: ErrorCode(-32602),
        message: Cow::from(format!("Invalid IDL JSON: {}", e)),
        data: Some(serde_json::json!({
            "program_id": program_id,
            "name": name,
            "path": path.to_string_lossy()
        })),
    })
}

pub fn list_programs() -> Result<Vec<(String, Vec<String>)>, ErrorData> {
    let root = registry_root();
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut out: Vec<(String, Vec<String>)> = Vec::new();
    let entries = std::fs::read_dir(&root).map_err(|e| ErrorData {
        code: ErrorCode(-32603),
        message: Cow::from(format!("Failed to read registry dir: {}", e)),
        data: None,
    })?;

    for ent in entries.flatten() {
        let p = ent.path();
        if !p.is_dir() {
            continue;
        }
        let program_id = ent.file_name().to_string_lossy().to_string();
        let mut names: Vec<String> = Vec::new();
        if let Ok(files) = std::fs::read_dir(&p) {
            for f in files.flatten() {
                let fp = f.path();
                if fp.is_file() {
                    if let Some(ext) = fp.extension().and_then(|s| s.to_str()) {
                        if ext.eq_ignore_ascii_case("json") {
                            if let Some(stem) = fp.file_stem().and_then(|s| s.to_str()) {
                                names.push(stem.to_string());
                            }
                        }
                    }
                }
            }
        }
        names.sort();
        out.push((program_id, names));
    }

    out.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(out)
}
