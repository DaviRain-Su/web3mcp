# Meteora 集成状态

## 概述

本文档描述了 omniweb3-mcp 中 Meteora 协议集成的当前状态和已知限制。

## 当前状态

### ✅ 正常工作
- 工具可通过 MCP 访问并能获取链上账户数据
- 池账户发现正常（通过地址查找 DLMM、DAMM 池）
- 程序 ID 验证正确工作
- 从 Solana RPC 获取基本账户结构

### ⚠️  部分正常 / 已知问题
- **链上数据解析不正确**：当前实现在硬编码的字节偏移量处读取账户数据（类似 `std.mem.readInt(i32, data[8..12], .little)` 的代码行），这些偏移量与实际的 Meteora 程序账户布局不匹配。
- 这导致关键字段返回垃圾值：
  - `active_bin_id`：应该在 -443,636 到 443,636 范围内，但返回类似 -1,543,503,728 的值
  - `bin_step`：返回意外值如 29,787
  - `price`：返回 0 或无穷大而不是实际市场价格

## 根本原因

Meteora DLMM 程序使用 Borsh 序列化，具有随时间演变的复杂账户结构。当前实现：

1. **使用手动字节偏移量**而非正确的 Borsh 反序列化
2. **账户结构已更改**：Meteora SDK 的问题 #247 提到"IDL 太旧，LbPair 与 IDL 的新版本不匹配"
3. **无判别器处理**：Anchor 账户包含必须考虑的 8 字节判别器
4. **字段顺序未知**：没有确切的 Borsh 模式，字节偏移量不可靠

## 正确的账户结构（来自 IDL）

LbPair 账户应包含（以 Borsh 序列化格式）：
- `parameters`：池参数结构
- `v_parameters`：附加参数
- `bump_seed`：PDA bump seeds
- `bin_step_seed`：Bin step 值
- `pair_type`：池类型枚举
- `active_id`：当前活跃 bin ID（i24）
- `bin_step`：每个 bin 的价格增量（u16）
- `status`：池状态
- `padding`：保留字节
- `token_x_mint`：代币 X mint 地址（32 字节）
- `token_y_mint`：代币 Y mint 地址（32 字节）
- `reserve_x`：代币 X 储备地址（32 字节）
- `reserve_y`：代币 Y 储备地址（32 字节）
- `protocol_fee`：协议费用配置
- `oracle`：预言机地址（32 字节）
- `reward_infos`：奖励配置数组

**另外**：开头有 8 字节 Anchor 判别器

## 推荐解决方案

### 方案 1：使用 Meteora REST API（最简单）
使用官方 Meteora API 而不是解析链上数据：
- **DLMM 交易对**：`https://dlmm-api.meteora.ag/pair/all`
- **池信息**：`https://dlmm-api.meteora.ag/pair/{pool_address}`
- **交换报价**：内置在 API 端点中

**优势**：
- 准确的数据
- 无需反序列化
- 包含计算字段（APY、交易量、TVL）

**实现**：添加调用这些 HTTP 端点的新工具

### 方案 2：实现正确的 Borsh 反序列化
使用 Borsh 正确解析账户数据：
1. 向 Zig 项目添加 Borsh 反序列化库
2. 定义与 IDL 匹配的 Meteora 账户结构
3. 正确处理判别器
4. 解析嵌套结构

**优势**：
- 可离线使用任何 RPC
- 无 API 速率限制

**挑战**：
- 需要 Zig 的 Borsh 库（或手动实现）
- 必须保持结构与 Meteora 程序更新同步
- 复杂的嵌套结构

### 方案 3：通过 Node 进程使用 TypeScript SDK
调用官方 `@meteora-ag/dlmm` SDK：
1. 创建 Node.js 辅助脚本
2. 使用进程执行从 Zig 调用 SDK 方法
3. 解析 JSON 输出

**优势**：
- 使用官方维护的代码
- 始终与程序更改保持最新

**挑战**：
- 需要安装 Node.js
- 性能开销
- 复杂的错误处理

## 测试结果

### 测试池
- **地址**：`BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y`
- **类型**：DLMM SOL-USDC
- **来源**：[Meteora App](https://www.meteora.ag/dlmm/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y)

### 当前输出 vs 预期

| 字段 | 当前输出 | 预期 | 问题 |
|-------|---------------|----------|-------|
| active_bin_id | -1,543,503,728 | ~24,000 到 25,000 | 错误的偏移量 |
| bin_step | 29,787 | 1-100 | 错误的偏移量 |
| price | 0 | ~$125（SOL 价格）| 从错误的 bin_id 派生 |
| program_id | ✅ 正确 | ✅ | 正常工作 |
| data_len | ✅ 1208 字节 | ✅ | 正常工作 |

## 受影响的工具

所有 42 个读取链上数据的 Meteora 工具：

### DLMM（9 个工具）
- `meteora_dlmm_get_pool` ⚠️  返回不正确的数据
- `meteora_dlmm_get_active_bin` ⚠️  返回不正确的数据
- `meteora_dlmm_get_bins` ⚠️  返回不正确的数据
- `meteora_dlmm_get_positions` ⚠️  返回不正确的数据
- `meteora_dlmm_swap_quote` ⚠️  返回不正确的数据
- 写操作（交换、添加/移除流动性、领取）❌ 由于数据错误无法使用

### DAMM V2（7 个工具）
链上数据解析存在类似问题

### 其他协议
- DBC、Alpha Vault、M3M3、Vault：相同的问题模式

## 参考资料

- [Meteora 文档](https://docs.meteora.ag)
- [Meteora DLMM SDK](https://github.com/MeteoraAg/dlmm-sdk)
- [Meteora API 端点](https://dlmm-api.meteora.ag/pair/all)
- [IDL 结构问题 #247](https://github.com/MeteoraAg/dlmm-sdk/issues/247)
- [Meteora 上的 DLMM 池](https://www.meteora.ag/dlmm/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y)
- [DexScreener SOL-USDC](https://dexscreener.com/solana/bgm1tav58ogcsqjehl9wxbfxf7d27vzskefj4xjkd5y)

## 下一步

**推荐**：实现方案 1（REST API 集成），因为它提供：
- 立即的准确结果
- 无维护负担
- 额外的计算指标
- 生产就绪的端点

**长期**：如果 Zig 的 Borsh 反序列化库可用，考虑方案 2 以实现完整的链上解决方案。

## API 使用示例

```bash
# 获取所有 DLMM 交易对
curl https://dlmm-api.meteora.ag/pair/all

# 获取特定池信息
curl https://dlmm-api.meteora.ag/pair/BGm1tav58oGcsQJehL9WXBFXF7D27vZsKefj4xJKD5Y

# 获取交换报价
curl "https://dlmm-api.meteora.ag/swap/quote?inputMint=So11111111111111111111111111111111111111112&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&amount=100000000&slippage=1"
```
