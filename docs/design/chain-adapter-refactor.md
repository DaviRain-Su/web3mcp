# Chain Adapter Refactor (v0.3.2)

## Goal

建立统一的链适配器与钱包抽象层，使 tools 只依赖 core，并且未来接入新链时不需要修改 tool 层代码。

## Design Principles

- **Tools 只调用 core**：不直接调用 RPC/SDK
- **Adapters 解耦链逻辑**：Solana/EVM 各自实现 adapter
- **Wallet 统一签名接口**：Ed25519 / secp256k1 归一
- **可扩展性优先**：新增链只需新增 adapter 和 wallet 实现

## Core Structure

```
core/
├── chain.zig                # unified entry
├── wallet.zig               # key & signing abstraction
└── adapters/
    ├── solana.zig           # Solana adapter
    └── evm.zig              # EVM adapter
```

## Adapter Interface (conceptual)

- `get_balance`
- `get_account`
- `get_transaction`
- `get_signature_status`
- `get_token_balance`
- `get_token_accounts`
- `send_transfer`

## Wallet Interface (conceptual)

- `load_sol_keypair`
- `load_evm_private_key`
- `sign_message`
- `verify_signature`

## Migration Plan

1. 新增 adapters 实现 (Solana/EVM)
2. 将工具调用迁移到 core/adapters
3. 抽离 keypair/privkey 加载到 core/wallet
4. 保持工具接口不变

## Non-goals

- 不新增新工具
- 不改变 tool 参数/返回结构
