# 依赖修改说明

本项目对第三方依赖进行了必要的修改以支持测试网。

## zabi 库修改

**文件**: `deps/zabi/src/types/ethereum.zig`

**修改内容**: 添加测试网 chain_id 到 `PublicChains` 枚举

```zig
pub const PublicChains = enum(usize) {
    ethereum = 1,
    goerli = 5,
    op_mainnet = 10,
    cronos = 25,
    bnb = 56,
    bnb_testnet = 97,              // ✅ 新增
    ethereum_classic = 61,
    op_kovan = 69,
    gnosis = 100,
    polygon = 137,
    fantom = 250,
    boba = 288,
    op_goerli = 420,
    base = 8543,
    anvil = 31337,
    arbitrum = 42161,
    arbitrum_nova = 42170,
    celo = 42220,
    avalanche_fuji = 43113,        // ✅ 新增
    avalanche = 43114,
    polygon_amoy = 80002,          // ✅ 新增
    zora = 7777777,
    sepolia = 11155111,
    op_sepolia = 11155420,
};
```

**原因**:
- 原始 zabi 库只包含主网 chain_id
- BSC Testnet (97) 等测试网不在枚举中
- 导致 `@enumFromInt(97)` 调用时 panic

**影响**:
- ✅ BSC Testnet 正常工作
- ✅ Avalanche Fuji Testnet 支持
- ✅ Polygon Amoy Testnet 支持

**后续计划**:
- [ ] 考虑向 zabi 上游提交 PR
- [ ] 或维护自己的 zabi fork
- [ ] 定期同步上游更新

## 其他修改

### http.zig (macOS 支持)

见提交记录中的 macOS 兼容性修复。

### zkLogin sidecar (Rust)

使用 `deps/sui-rust-sdk` 的 `sui-zklogin-ffi` 提供 HTTP 验证服务，主程序自动拉起。
文档见 `docs/zklogin_sidecar.md`。

## 注意事项

**deps 目录已纳入版本控制**:
- 关键依赖（包括 `deps/sui-sdk-zig` 与 `deps/sui-rust-sdk`）已 vendor 进仓库
- 依赖修改会随仓库提交

**如何重新应用修改**:
```bash
# 如果 deps/zabi 被重置，重新添加测试网 chain_id:
# 编辑 deps/zabi/src/types/ethereum.zig
# 在 bnb = 56 后添加: bnb_testnet = 97
# 在 avalanche = 43114 前添加: avalanche_fuji = 43113
# 添加: polygon_amoy = 80002
```

**版本信息**:
- zabi: 本地依赖 (deps/zabi)
- http.zig: 本地依赖 (deps/http.zig)
- 修改日期: 2026-01-28
