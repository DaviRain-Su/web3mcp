# Naming note

This repository folder is now `web3mcp/`.

The Rust crate/binary name is now `web3mcp` (see `Cargo.toml`). If you still have older configs/scripts referencing `sui-mcp`, update them to `web3mcp`.

- existing Claude Desktop MCP configs
- scripts/examples that reference `target/release/web3mcp`

If you want to rename the binary to `web3mcp`, do it in a dedicated PR (Cargo.toml + docs + release artifacts), potentially shipping a compatibility shim.
