# Design: MCP Skeleton (v0.1.0)

## Objective
构建基于 Zig 0.15 + mcp.zig 的最小可运行 MCP Server 骨架，支持：
- 工程化：build.zig / build.zig.zon
- MCP Server 启动（stdio），可 listTools
- 基础工具：ping（回声）、get_balance（占位）
- 核心抽象：链/协议/交易/钱包接口，便于后续扩展到 Solana/Avalanche/BNB

## Scope
- 只做骨架，不接入真实链 RPC
- 确认编译与运行闭环：`zig build run` 启动 server
- 提供占位工具与抽象，后续版本逐步填充业务逻辑

## Architecture
```
src/
├── main.zig        # 入口：加载配置、注册工具、启动 MCP server (stdio)
├── server.zig      # mcp.zig 封装：创建 Server、注册 tools/resources
├── core/
│   ├── chain.zig   # ChainAdapter trait: ChainId/ChainType/Address/Transaction/vtable
│   ├── wallet.zig  # Wallet 抽象：ed25519 / secp256k1 占位
│   ├── transaction.zig # 统一交易结构，chain_specific union { solana, evm }
│   └── types.zig   # 通用类型（TxHash, Balance 等）
├── tools/
│   ├── ping.zig       # 返回固定文本
│   ├── balance.zig    # 占位：返回 mock balance
│   └── registry.zig   # 统一注册所有工具
└── utils/          # (可选) config/log/http/json 占位
```

## MCP Tool Surface (v0.1.0)
- `ping`: 返回 "pong from defi-anywhere"
- `get_balance`: 参数 { chain, address }，返回 mock 数值；保证编译与调用链畅通

## Build & Run
- Zig 0.15.2
- 依赖：mcp.zig（以 submodule / fetch / 本地路径集成，方案待定，优先使用本地路径导入）
- 目标：`zig build run` 通过，启动后可由 MCP 客户端 listTools 并调用 `ping`

## Out of Scope (后续版本)
- 真实链 RPC（v0.2 Solana / v0.3 EVM）
- 签名与交易广播
- DEX/Lending/Bridge 协议集成
- 跨链比较/套利

## Risks & Notes
- mcp.zig API 版本需与 Zig 0.15.2 兼容
- std.io 新接口 (Writergate) 需注意 buffer/writer 适配
- ArrayList/HashMap 需传 allocator（0.15 变更）

## Acceptance (aligned with Story v0.1.0)
- 构建通过：`zig build` / `zig build run`
- 工具可 list 并可调用 `ping`
- 抽象文件存在并通过编译（即便内含 TODO 实现）
- 文档：Roadmap、Story、Design 就绪
