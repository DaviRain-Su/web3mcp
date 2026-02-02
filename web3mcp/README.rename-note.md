# Naming note

This repository folder is now `web3mcp/`.

The Rust crate/binary name is still `sui-mcp` (see `Cargo.toml`). Renaming the crate/binary is possible but is a breaking change for:

- existing Claude Desktop MCP configs
- scripts/examples that reference `target/release/sui-mcp`

If you want to rename the binary to `web3mcp`, do it in a dedicated PR (Cargo.toml + docs + release artifacts), potentially shipping a compatibility shim.
