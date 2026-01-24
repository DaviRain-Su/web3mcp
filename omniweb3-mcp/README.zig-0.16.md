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
│       ├── balance.zig       # 统一余额查询
│       ├── transfer.zig      # 统一转账
│       ├── block_number.zig  # 统一区块高度/编号
│       ├── transaction.zig   # 统一交易查询
│       ├── token_balance.zig # 统一 Token 余额
│       └── ...               # 其他链级基础工具
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

## 已支持工具

### Unified Chain Tools
- `get_balance`: 统一余额查询（Solana + EVM）
- `transfer`: 统一转账（Solana + EVM，支持 EIP-1559/Legacy）
  - Solana: amount=lamports, keypair_path 可选
  - EVM: amount=wei, private_key/keypair_path 可选
- `get_block_number`: 统一区块高度/编号
- `get_transaction`: 统一交易查询（Solana signature / EVM tx_hash）
- `token_balance`: 统一 Token 余额（Solana token_account / EVM token_address+owner）

### EVM-only
- `get_block`: 区块信息
- `get_receipt`: 交易回执
- `get_nonce`: 地址 nonce
- `get_gas_price`: gas price
- `estimate_gas`: 估算 gas
- `call`: eth_call

### Solana-only
- `account_info`: 账户信息
- `signature_status`: 交易状态
- `token_accounts`: 列出 Token 账户

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
