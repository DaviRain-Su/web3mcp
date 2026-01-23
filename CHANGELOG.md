# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.0] - 2026-01-23

### Added
- Solana RPC integration via solana-client-zig dependency
- Ed25519 signing via solana-sdk-zig dependency
- Real `get_balance` tool: Query native SOL balance on devnet/testnet/mainnet/localhost
- `transfer` tool: Transfer native SOL with secure keypair loading
- Keypair loading from file (SOLANA_KEYPAIR env or ~/.config/solana/id.json)
- Network selection support: devnet, testnet, mainnet, localhost
- Gzip response decompression for Solana RPC (upstream fix in solana-client-zig)

### Security
- Keypair loaded from file instead of API parameter to prevent secret exposure
- Dynamic home directory resolution for portable keypair path

### Session 2026-01-23-002

**Date**: 2026-01-23
**Goal**: Complete v0.2.0 Solana Basics - RPC integration and SOL transfers

#### Completed Work
1. Integrated solana-client-zig and solana-sdk-zig dependencies
2. Fixed gzip decompression issue in solana-client-zig (upstream fix)
3. Implemented real get_balance tool with RPC calls
4. Implemented transfer tool with System Program instruction building
5. Added secure keypair loading (env var → config file)
6. Verified transfer on local Solana validator

#### Test Results
- get_balance: Verified on devnet and localhost
- transfer: 1 SOL + 0.5 SOL + 0.1 SOL transfers verified on localhost validator
- All transactions confirmed successfully

#### Files Modified
- `omniweb3-mcp/src/tools/balance.zig` - Real Solana RPC balance queries
- `omniweb3-mcp/src/tools/transfer.zig` - SOL transfer with keypair loading
- `omniweb3-mcp/src/tools/registry.zig` - Updated tool descriptions
- `omniweb3-mcp/build.zig.zon` - Added Solana dependencies
- `stories/v0.2.0-solana-basics.md` - Updated completion status

#### Next Steps
- [ ] Start v0.3.0 - SPL Token support (token balance, token transfers)

## [v0.1.0] - 2026-01-23

### Added
- Initial MCP Server skeleton with Zig 0.15 + mcp.zig
- Core abstractions: ChainAdapter (vtable pattern), Wallet interface, Transaction structure
- Ping tool: Health check returning "pong from omniweb3-mcp"
- Get balance tool: Mock implementation with chain/address parameter support
- Build system: build.zig / build.zig.zon with proper Zig 0.15 configuration
- Tool registry pattern for MCP tool registration
- MCP protocol support: initialize, tools/list, tools/call

### Session 2026-01-23-001

**Date**: 2026-01-23
**Goal**: Complete v0.1.0 MCP Skeleton - Fix build issues and verify MCP protocol

#### Completed Work
1. Fixed build.zig.zon for Zig 0.15 compatibility (added fingerprint, paths fields)
2. Fixed tool handlers to match mcp.zig API signature
3. Fixed import paths in tools (using `@import("mcp")` instead of relative paths)
4. Fixed memory issue in balance.zig (stack buffer -> allocPrint)
5. Verified MCP protocol: initialize, tools/list, tools/call (ping, get_balance)

#### Test Results
- Build: `zig build` compiles without errors
- MCP Protocol: All endpoints verified working
  - initialize → returns server info and capabilities
  - tools/list → returns ping and get_balance tools
  - tools/call ping → returns "pong from omniweb3-mcp"
  - tools/call get_balance → returns mock JSON with chain/address/balance

#### Files Modified
- `omniweb3-mcp/build.zig.zon` - Added fingerprint and paths for Zig 0.15
- `omniweb3-mcp/src/main.zig` - Simplified to use correct mcp.zig API
- `omniweb3-mcp/src/tools/ping.zig` - Fixed handler signature and imports
- `omniweb3-mcp/src/tools/balance.zig` - Fixed handler signature and memory handling
- `omniweb3-mcp/src/tools/registry.zig` - Fixed to match mcp.zig Tool API
- `stories/v0.1.0-mcp-skeleton.md` - Marked all criteria complete
- `ROADMAP.md` - Updated v0.1.0 status to ✅ Completed

#### Next Steps
- [ ] Start v0.2.0 - Solana Basics (RPC integration, real balance queries)
