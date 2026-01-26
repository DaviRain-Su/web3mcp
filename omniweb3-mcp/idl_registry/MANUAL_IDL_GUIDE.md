# 手动获取 IDL 指南

由于许多 Solana 程序的 IDL 文件不在标准位置，需要手动获取。本文档提供详细步骤。

## 方法 1: 使用 Anchor CLI (最可靠)

### 前置条件
```bash
# 安装 Solana CLI
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"

# 安装 Anchor CLI
cargo install --git https://github.com/coral-xyz/anchor avm --locked
avm install latest
avm use latest
```

### 获取 IDL
```bash
# 设置 RPC URL
export SOLANA_RPC_URL=https://api.mainnet-beta.solana.com

# 获取程序 IDL
anchor idl fetch PROGRAM_ID -o idl_registry/PROGRAM_ID.json

# 示例：获取 Orca Whirlpool IDL
anchor idl fetch whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc \
  -o idl_registry/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json
```

## 方法 2: 从程序的 GitHub 仓库

### 1. Orca Whirlpool

**仓库**: https://github.com/orca-so/whirlpools

**步骤**:
1. 访问 Releases 页面找到最新版本
2. 下载 release artifacts 或查看 assets
3. 或者克隆仓库并构建：
   ```bash
   git clone https://github.com/orca-so/whirlpools
   cd whirlpools
   anchor build
   cp target/idl/whirlpool.json /path/to/idl_registry/whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc.json
   ```

### 2. Metaplex Token Metadata

**仓库**: https://github.com/metaplex-foundation/mpl-token-metadata

**步骤**:
1. 检查 releases 或 npm 包
2. 或使用 Metaplex CLI:
   ```bash
   npm install -g @metaplex-foundation/js
   # 然后使用 Metaplex SDK 提取 IDL
   ```

### 3. Marinade Finance

**仓库**: https://github.com/marinade-finance/liquid-staking-program

**步骤**:
1. 克隆并构建：
   ```bash
   git clone https://github.com/marinade-finance/liquid-staking-program
   cd liquid-staking-program
   anchor build
   cp target/idl/marinade_finance.json /path/to/idl_registry/MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD.json
   ```

### 4. Raydium AMM v4

**注意**: Raydium v4 可能不使用 Anchor，可能需要其他方法。

**替代方案**: 使用 Raydium v3 或 CLMM (使用 Anchor)
- Raydium CLMM: `CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK`

## 方法 3: 使用 Solana FM (需要 API Key)

1. 注册 Solana FM 账号: https://solana.fm/
2. 获取 API Key
3. 使用 API:
   ```bash
   curl -H "Authorization: Bearer YOUR_API_KEY" \
     "https://api.solanafm.com/v0/accounts/PROGRAM_ID/idl"
   ```

## 方法 4: 从社区/Discord 获取

许多项目在 Discord 或 Telegram 中分享 IDL 文件。

### 联系方式
- **Orca**: https://discord.gg/orca
- **Metaplex**: https://discord.gg/metaplex
- **Marinade**: https://discord.gg/marinade
- **Raydium**: https://discord.gg/raydium

## 方法 5: 使用 Solscan 的 IDL

某些程序在 Solscan 上有 IDL：
1. 访问 https://solscan.io/account/PROGRAM_ID
2. 查找 "Program IDL" 或 "Anchor IDL" 标签
3. 复制 JSON 内容

## 验证 IDL

下载 IDL 后，验证格式：
```bash
# 检查 JSON 格式
jq empty idl_registry/PROGRAM_ID.json

# 查看基本信息
jq '.name, .version, (.instructions | length)' idl_registry/PROGRAM_ID.json

# 示例输出：
# "whirlpool"
# "0.1.0"
# 42
```

## 启用程序

1. 确保 IDL 文件存在：
   ```bash
   ls -lh idl_registry/PROGRAM_ID.json
   ```

2. 编辑 `programs.json`：
   ```json
   {
     "id": "PROGRAM_ID",
     "enabled": true  // 改为 true
   }
   ```

3. 重启服务器

## 常见问题

### Q: 为什么不能直接从链上获取 IDL?
A: Anchor IDL 通常存储在链上，但需要正确的工具来提取。使用 `anchor idl fetch` 是最可靠的方法。

### Q: 程序没有 IDL 怎么办?
A: 一些老程序或非 Anchor 程序可能没有 IDL。这种情况下：
- 检查程序是否有更新版本（使用 Anchor）
- 考虑为这些程序创建静态工具（手动编码）
- 等待程序团队提供 IDL

### Q: IDL 版本如何管理?
A:
- 程序升级时，IDL 可能会改变
- 建议定期检查更新
- 可以在 `programs.json` 的 `note` 字段记录 IDL 版本

## 贡献 IDL

如果您成功获取了某个程序的 IDL，欢迎贡献：
1. Fork 仓库
2. 添加 IDL 文件到 `idl_registry/`
3. 更新 `programs.json`（设置 `enabled: true`）
4. 提交 Pull Request

## 当前状态

| 程序 | IDL 状态 | 获取方法 |
|------|---------|---------|
| Jupiter v6 | ✅ 已有 | 本地文件 |
| Metaplex | ❌ 待获取 | 推荐方法 1 或 2 |
| Raydium | ❌ 待获取 | 可能不适用（非 Anchor）|
| Orca | ❌ 待获取 | 推荐方法 1 或 2 |
| Marinade | ❌ 待获取 | 推荐方法 1 或 2 |

## 下一步

1. 优先使用**方法 1（Anchor CLI）**，最可靠
2. 从 Orca 和 Marinade 开始（已知使用 Anchor）
3. 跳过 Raydium v4（考虑使用 CLMM 代替）
4. Metaplex 可以从 npm 包中提取

## 自动化计划

未来改进：
- [ ] 集成 Anchor CLI 到下载脚本
- [ ] 自动检查程序是否支持 Anchor
- [ ] IDL 版本追踪和自动更新
- [ ] 建立 IDL 镜像库
