use serde_json::Value;
use std::collections::HashMap;
use std::sync::RwLock;

#[derive(Default)]
pub struct SolanaIdlCache {
    // idl_id -> idl json
    inner: RwLock<HashMap<String, Value>>,
}

impl SolanaIdlCache {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn put(&self, idl_id: String, idl: Value) {
        let mut g = self.inner.write().expect("idl cache write lock");
        g.insert(idl_id, idl);
    }

    pub fn get(&self, idl_id: &str) -> Option<Value> {
        let g = self.inner.read().expect("idl cache read lock");
        g.get(idl_id).cloned()
    }

    pub fn remove(&self, idl_id: &str) -> bool {
        let mut g = self.inner.write().expect("idl cache write lock");
        g.remove(idl_id).is_some()
    }

    pub fn list(&self) -> Vec<String> {
        let g = self.inner.read().expect("idl cache read lock");
        let mut keys: Vec<String> = g.keys().cloned().collect();
        keys.sort();
        keys
    }

    pub fn clear(&self) {
        let mut g = self.inner.write().expect("idl cache write lock");
        g.clear();
    }
}
