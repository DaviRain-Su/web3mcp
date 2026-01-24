# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### Session 2026-01-23-003

**Date**: 2026-01-23
**Goal**: Start v0.3.0 EVM Basics - zabi integration and EVM tools

#### Completed Work
1. Added EVM runtime initialization using std.Io.Threaded
2. Implemented EVM network config + private key resolution helpers
3. Implemented get_evm_balance tool using zabi HttpProvider
4. Implemented evm_transfer tool with EIP-1559 + legacy support
5. Registered EVM tools in MCP registry
6. Updated documentation and v0.3.0 story progress

#### Test Results
- Build: `zig build` (pass)
- EVM RPC: Verified on local Anvil (get_evm_balance, evm_transfer)

#### Files Modified
- `omniweb3-mcp/src/core/evm_runtime.zig` - EVM Io runtime
- `omniweb3-mcp/src/core/evm_helpers.zig` - EVM config/key helpers
- `omniweb3-mcp/src/tools/evm_balance.zig` - EVM balance tool
- `omniweb3-mcp/src/tools/evm_transfer.zig` - EVM transfer tool
- `omniweb3-mcp/src/tools/registry.zig` - Tool registration
- `omniweb3-mcp/src/main.zig` - Init Io runtime
- `omniweb3-mcp/README.zig-0.16.md` - Tool list update
- `stories/v0.3.0-evm-basics.md` - Progress checklist

#### Next Steps
- [ ] Validate get_evm_balance on Sepolia
- [ ] Validate evm_transfer on Sepolia
- [ ] Multi-chain tests (Avalanche/BNB)

### Session 2026-01-23-004

**Date**: 2026-01-23
**Goal**: v0.3.1 Base Enhancements - Solana read-only tools

#### Completed Work
1. Added Solana account info tool (solana_account_info)
2. Added signature status tool (solana_signature_status)
3. Added transaction lookup tool (solana_transaction)
4. Added SPL token balance tool (solana_token_balance)
5. Added SPL token accounts tool (solana_token_accounts)
6. Added Solana helper utilities and tool registration
7. Updated README and v0.3.1 story progress

#### Test Results
- Build: `zig build` (pass)
- Solana RPC: Not yet validated on devnet/testnet

#### Files Modified
- `omniweb3-mcp/src/core/solana_helpers.zig` - Solana helper utilities
- `omniweb3-mcp/src/tools/solana_account_info.zig` - Account info tool
- `omniweb3-mcp/src/tools/solana_signature_status.zig` - Signature status tool
- `omniweb3-mcp/src/tools/solana_transaction.zig` - Transaction lookup tool
- `omniweb3-mcp/src/tools/solana_token_balance.zig` - Token balance tool
- `omniweb3-mcp/src/tools/solana_token_accounts.zig` - Token accounts tool
- `omniweb3-mcp/src/tools/registry.zig` - Tool registration
- `omniweb3-mcp/README.zig-0.16.md` - Tool list update
- `stories/v0.3.1-base-enhancements.md` - Story checklist

#### Next Steps
- [ ] Validate Solana tools on devnet

### Session 2026-01-23-005

**Date**: 2026-01-23
**Goal**: v0.3.2 Core Adapter Refactor - core/chain + wallet abstraction

#### Completed Work
1. Added Solana/EVM adapters under core/adapters
2. Refactored core/chain to provide adapter constructors
3. Consolidated key loading into core/wallet (Solana + EVM)
4. Updated Solana tools to use core adapters
5. Updated EVM tools to use core adapters + wallet
6. Added chain adapter design doc and story progress updates

#### Test Results
- Build: `zig build` (pass)

#### Files Modified
- `omniweb3-mcp/src/core/adapters/solana.zig` - Solana adapter
- `omniweb3-mcp/src/core/adapters/evm.zig` - EVM adapter
- `omniweb3-mcp/src/core/chain.zig` - Unified adapter init
- `omniweb3-mcp/src/core/wallet.zig` - Key loading abstraction
- `omniweb3-mcp/src/tools/*` - Tool refactor to core adapters
- `docs/design/chain-adapter-refactor.md` - Design doc
- `stories/v0.3.2-core-adapters.md` - Story checklist

#### Next Steps
- [ ] Validate Solana tools on devnet

### Session 2026-01-23-006

**Date**: 2026-01-23
**Goal**: v0.3.3 Unified Chain Tools - consolidate balance/transfer

#### Completed Work
1. Unified `get_balance` across Solana/EVM
2. Unified `transfer` across Solana/EVM
3. Removed evm_balance/evm_transfer tool registrations
4. Updated README and v0.3.3 story progress
5. Updated Anvil test script and added Solana devnet script

#### Test Results
- Build: `zig build` (pass)
- EVM Anvil: `scripts/evm_anvil_test.py` (pass)
- Solana local: `scripts/solana_devnet_test.py` balance+transfer (pass; auto-recipient)

#### Files Modified
- `omniweb3-mcp/src/tools/balance.zig` - unified balance
- `omniweb3-mcp/src/tools/transfer.zig` - unified transfer
- `omniweb3-mcp/src/tools/registry.zig` - removed EVM tool entries
- `omniweb3-mcp/README.zig-0.16.md` - tool list update
- `stories/v0.3.3-unified-tools.md` - progress checklist

#### Next Steps
- [ ] Validate unified transfer on Solana devnet (non-local)

### Session 2026-01-23-007

**Date**: 2026-01-23
**Goal**: v0.3.1 EVM base tools unified naming

#### Completed Work
1. Added unified EVM core adapter methods (block, tx, receipt, nonce, call)
2. Implemented unified tools: block_number/block/transaction/receipt/nonce/gas_price/estimate_gas/call/token_balance
3. Added Solana support for get_block (slot)
4. Renamed Solana tools to unified names (account_info/signature_status/token_accounts)
5. Added Solana-only tool docs (account_info/signature_status/token_accounts)
6. Updated tool registry and README to unified names
7. Added Solana token_balance support for owner+mint
8. Added Solana tools: token_balances/request_airdrop/get_tps
9. Added Solana tools: get_slot/get_block_height
10. Added Solana parse_transaction tool
11. Updated solana_devnet_test.py to exercise request_airdrop/parse_transaction
12. Updated v0.3.1 story tool list for unified naming

#### Test Results
- Build: `zig build` (pass)

#### Next Steps
- [ ] Verify EVM tools on Anvil

### Session 2026-01-23-009

**Date**: 2026-01-23
**Goal**: Add additional Solana base RPC tools

#### Completed Work
1. Added Solana tools: get_epoch_info, get_version, get_supply
2. Added Solana token tools: get_token_supply, get_token_largest_accounts
3. Added Solana query tools: get_signatures_for_address, get_block_time
4. Updated registry, README, and v0.3.1 story

#### Test Results
- Build: `zig16 build` (pass)

#### Next Steps
- [ ] Verify EVM tools on Anvil

### Session 2026-01-23-010

**Date**: 2026-01-23
**Goal**: Extend Solana devnet test coverage for new base tools

#### Completed Work
1. Added Solana script coverage for epoch/version/supply/token_supply/token_largest_accounts/signatures/block_time
2. Added localhost/surfpool support with optional mint creation

#### Test Results
- Build: `zig16 build` (pass)
- Solana: `python3 scripts/solana_devnet_test.py` (localhost/surfpool, pass)

#### Next Steps
- [ ] Plan next milestone (v0.4.0 protocols)

### Session 2026-01-23-012

**Date**: 2026-01-23
**Goal**: Add Solana utility tools (wallet address + close empty token accounts)

#### Completed Work
1. Added get_wallet_address tool
2. Added close_empty_token_accounts tool
3. Updated tool registry and README
4. Added v0.3.4 story + roadmap entry

#### Test Results
- Build: `zig16 build` (pass)

#### Next Steps
- [ ] Run Solana utility tools locally

### Session 2026-01-23-011

**Date**: 2026-01-23
**Goal**: Validate EVM base tools on Anvil

#### Completed Work
1. Extended `scripts/evm_anvil_test.py` with block_number/gas_price/nonce/token_balance checks
2. Deployed a local ERC20 test token for token_balance verification

#### Test Results
- EVM: `python3 scripts/evm_anvil_test.py` (Anvil, pass)

#### Next Steps
- [ ] Plan next milestone (v0.4.0 protocols)

### Session 2026-01-23-008

**Date**: 2026-01-23
**Goal**: Fix parse_transaction output and run Solana devnet tests

#### Completed Work
1. Fixed mcp tools textResult/errorResult to copy response text (avoid freed buffers)
2. Adjusted Solana parse_transaction/transaction outputs to avoid invalid data slices
3. Ran Solana devnet script with airdrop + parse_transaction

#### Test Results
- Build: `zig16 build` (pass)
- Solana local: `scripts/solana_devnet_test.py` (pass; airdrop + parse_transaction)

#### Next Steps
- [ ] Verify EVM tools on Anvil

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
