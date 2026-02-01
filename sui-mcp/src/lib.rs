// Library entrypoint to enable unit/integration testing of internal helpers.
//
// The binary (src/main.rs) remains the primary executable.

pub mod types;

// Keep the library surface minimal: many utils are implemented as `impl SuiMcpServer` methods
// and therefore only compile in the binary crate.
#[path = "utils/evm_confirm_store.rs"]
pub mod evm_confirm_store;

#[path = "utils/evm_calldata.rs"]
pub mod evm_calldata;

#[path = "utils/evm_confirm_ux.rs"]
pub mod evm_confirm_ux;

pub mod utils {
    pub use crate::evm_calldata;
    pub use crate::evm_confirm_store;
    pub use crate::evm_confirm_ux;
}
