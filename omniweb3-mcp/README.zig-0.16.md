# OmniWeb3 MCP - Zig 0.16 版本

这是一个使用 Zig 0.16 构建的跨链 Web3 MCP Server。

## 系统要求

- **Zig 版本**: 0.16.0-dev.2261+d6b3dd25a 或更高
- **操作系统**: Linux (当前仅支持 Linux，因为使用了 Linux 系统调用)
- **依赖**: libc (自动链接)

## 快速开始

### 1. 检查 Zig 版本

```bash
zig version
# 应该输出: 0.16.0-dev.2261+d6b3dd25a 或更高
```

### 2. 构建项目

```bash
cd omniweb3-mcp
zig build
```

### 3. 运行测试

```bash
./test_build.sh
```

### 4. 本地 Anvil EVM 测试

```bash
# 另一个终端启动 Anvil
anvil --chain-id 1

# 运行 EVM 测试脚本（会执行余额查询和转账）
./scripts/evm_anvil_test.py
```

### 5. 运行程序

```bash
./zig-out/bin/omniweb3-mcp
```

## 项目结构

```
omniweb3-mcp/
├── build.zig              # Zig 0.16 build 配置
├── build.zig.zon          # 依赖管理 (zig-0.16 分支)
├── src/
│   ├── main.zig          # 主入口
│   ├── server.zig        # MCP 服务器
│   ├── core/             # 核心功能
│   │   ├── evm_helpers.zig      # EVM 配置与密钥
│   │   ├── evm_runtime.zig      # EVM I/O runtime
│   │   └── solana_helpers.zig   # Solana 公共工具
│   └── tools/            # 工具模块
│       ├── common/           # 通用工具（ping）
│       ├── unified/          # 跨链工具（balance/transfer/etc）
│       ├── solana/           # Solana-only 工具
│       ├── evm/              # EVM-only 工具
│       └── registry.zig      # 工具注册
├── deps/
│   └── mcp.zig/          # MCP 协议实现 (已适配 Zig 0.16)
├── ZIG_0.16_MIGRATION.md # Zig 0.16 迁移文档
└── test_build.sh         # 构建测试脚本
```

## 依赖

所有依赖已更新到 zig-0.16 分支：

- **mcp.zig**: MCP 协议实现 (本地修改，适配 Zig 0.16)
- **solana-client-zig**: Solana RPC 客户端 (zig-0.16 分支)
- **solana-sdk-zig**: Solana SDK (zig-0.16 分支)
- **zabi**: Ethereum ABI 编解码

## 钱包配置

OmniWeb3 MCP 支持两种钱包类型：

### Privy 钱包（默认，当提供 wallet_id 时）
- **自动检测**: 当您提供 `wallet_id` 参数时，自动使用 Privy 钱包
- **无需显式指定**: `wallet_id` 隐含 `wallet_type=privy`
- **环境变量**: 需要设置 `PRIVY_APP_ID` 和 `PRIVY_APP_SECRET`

```json
{
  "wallet_id": "your-privy-wallet-id"
}
```

### 本地钱包（显式指定）
- **Solana**: 使用 `wallet_type=local` + `keypair_path`
- **EVM**: 使用 `wallet_type=local` + `private_key`

```json
{
  "wallet_type": "local",
  "keypair_path": "~/.config/solana/id.json"
}
```

**详细文档**: 参见 [WALLET_CONFIGURATION.md](./WALLET_CONFIGURATION.md)

## 已支持工具

### Unified Chain Tools
- `get_balance`: 统一余额查询（Solana + EVM）
- `transfer`: 统一转账（Solana + EVM，支持 EIP-1559/Legacy）
  - **钱包配置**: `wallet_id` (Privy) 或 `wallet_type=local` + `keypair_path`/`private_key`
  - Solana: amount=lamports
  - EVM: amount=wei
- `get_block_number`: 统一区块高度/编号
- `get_block`: 统一区块查询（Solana slot / EVM block）
- `get_transaction`: 统一交易查询（Solana signature / EVM tx_hash）
- `token_balance`: 统一 Token 余额（Solana token_account 或 owner+mint / EVM token_address+owner）

### EVM-only
- `get_receipt`: 交易回执
- `get_nonce`: 地址 nonce
- `get_gas_price`: gas price
- `estimate_gas`: 估算 gas
- `call`: eth_call
- `get_chain_id`: 链 ID
- `get_fee_history`: fee history
- `get_logs`: 日志查询

### Solana-only
- `account_info`: 账户信息
- `signature_status`: 交易状态
- `parse_transaction`: 解析交易详情（日志/Token 余额）
- `token_accounts`: 列出 Token 账户
- `token_balances`: 列出钱包所有 SPL Token 余额
- `request_airdrop`: 请求测试网空投
- `get_tps`: 获取近期 TPS
- `get_slot`: 获取当前 slot
- `get_block_height`: 获取当前 block height
- `get_epoch_info`: 获取 epoch 信息
- `get_version`: 获取版本信息
- `get_supply`: 获取 supply 信息
- `get_token_supply`: 获取 SPL token supply
- `get_token_largest_accounts`: 获取 SPL 最大账户列表
- `get_signatures_for_address`: 获取地址交易签名列表
- `get_block_time`: 获取 slot 对应区块时间
- `get_wallet_address`: 获取钱包地址
- `close_empty_token_accounts`: 关闭空 Token 账户
- `get_latest_blockhash`: 获取最新 blockhash
- `get_minimum_balance_for_rent_exemption`: 获取租金豁免最小余额
- `get_fee_for_message`: 获取消息费用
- `get_program_accounts`: 获取 program accounts
- `get_vote_accounts`: 获取 vote accounts
- `get_jupiter_quote`: 获取 Jupiter swap 报价（支持 endpoint/api_key/insecure 覆盖）
- `get_jupiter_price`: 获取 Jupiter token 价格（支持 endpoint/api_key/insecure 覆盖）

### Solana DeFi 工具（支持钱包配置）

以下 DeFi 工具支持统一的钱包配置：当提供 `wallet_id` 时，自动使用 Privy 钱包；否则可显式指定 `wallet_type=local`。

#### Jupiter 协议
- `jupiter_execute_swap`: 完整 swap 流程（报价 + 构建 + 签名 + 发送）
  - **钱包配置**: `wallet_id` (默认 Privy) 或 `wallet_type=local` + `keypair_path`
- `jupiter_swap`: 构建 swap 交易
- `jupiter_ultra_order`: 创建 Ultra 订单
- `jupiter_create_trigger_order`: 创建限价订单
- `jupiter_cancel_trigger_order`: 取消限价订单
- `jupiter_cancel_trigger_orders`: 批量取消限价订单
- `jupiter_create_recurring_order`: 创建 DCA 定投订单
- `jupiter_cancel_recurring_order`: 取消 DCA 订单
- `jupiter_lend_deposit`: Jupiter Lend 存款
- `jupiter_lend_withdraw`: Jupiter Lend 提款
- `jupiter_lend_mint`: Jupiter Lend 铸造份额
- `jupiter_lend_redeem`: Jupiter Lend 赎回份额
- `jupiter_craft_send`: Jupiter Send 转账
- `jupiter_craft_clawback`: Jupiter Send 退款
- `jupiter_claim_dbc_fee`: 领取 DBC 池费用
- `jupiter_create_dbc_pool`: 创建 DBC 池

#### Meteora 协议
- 所有 Meteora DeFi 操作支持相同的钱包配置模式

#### dFlow 协议
- 所有 dFlow 交易操作支持相同的钱包配置模式

**注意**: 所有 DeFi 工具的钱包参数：
- `wallet_id` → 自动使用 Privy（默认行为）
- `wallet_type=local` + `keypair_path` → 使用本地密钥对
- 详细配置请参见 [WALLET_CONFIGURATION.md](./WALLET_CONFIGURATION.md)

## Zig 0.16 API 变更

本项目已适配 Zig 0.16 的以下重大 API 变更：

### 1. File I/O
- 使用 `std.os.linux` 系统调用替代 `std.fs.File` 的 `writeAll()`/`read()`
- stdin/stdout/stderr 通过文件描述符直接操作

### 2. 环境变量
- 使用 C 的 `getenv()` 替代 `std.posix.getenv()`
- 需要链接 libc

### 3. 文件系统
- 使用 Linux 系统调用 `open()`/`read()` 替代 `std.fs.openFileAbsolute()`

详细迁移文档请参见 [ZIG_0.16_MIGRATION.md](./ZIG_0.16_MIGRATION.md)

## 开发

### 清理构建

```bash
rm -rf zig-out .zig-cache
```

### 重新构建

```bash
zig build
```

### 运行 release 版本

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/omniweb3-mcp
```

## 已知限制

1. **仅支持 Linux**: 当前使用 `std.os.linux` 系统调用，不支持 Windows/macOS
2. **需要 libc**: 使用 C 的 `getenv()` 函数
3. **Debug 构建较大**: 30MB (包含调试信息)

## 故障排除

### 构建失败

如果遇到构建错误，请：

1. 确认 Zig 版本是 0.16.x
   ```bash
   zig version
   ```

2. 清理缓存重新构建
   ```bash
   rm -rf ~/.cache/zig .zig-cache zig-out
   zig build
   ```

3. 检查依赖是否正确获取
   ```bash
   ls ~/.cache/zig/p/
   ```

### 运行时错误

- **环境变量问题**: 确保设置了必要的环境变量（如 `HOME`）
- **文件权限**: 确保 keypair 文件可读
- **libc 缺失**: 确保系统已安装 glibc

## 贡献

欢迎提交 Issue 和 Pull Request！

特别关注：
- Windows/macOS 支持
- 移除 libc 依赖（使用纯 Zig 实现）
- 性能优化
- 更多测试

## 许可证

MIT License

## 相关链接

- [Zig 0.16 Release Notes](https://ziglang.org/download/0.16.0/release-notes.html)
- [solana-sdk-zig (zig-0.16 branch)](https://github.com/DaviRain-Su/solana-sdk-zig/tree/zig-0.16)
- [solana-client-zig (zig-0.16 branch)](https://github.com/DaviRain-Su/solana-client-zig/tree/zig-0.16)
