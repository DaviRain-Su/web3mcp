# MCP App UI Components

完成了三个核心UI组件的实现，支持Mock模式开发和真实MCP Host集成。

## 已实现组件

### 1. Transaction Viewer (交易查看器)
**路径**: `/src/transaction/`
**功能**:
- 交易状态显示 (成功/失败/pending)
- 可视化交易流程 (From → Amount → To)
- 详细信息表格 (区块高度、时间戳、Nonce等)
- Gas分析与可视化
- 复制交易哈希、跳转区块浏览器

**预览**:
```
http://localhost:5175/src/transaction/?chain=bsc&txHash=0x5ad4...&network=testnet&mock=true
```

### 2. Swap Interface (交换界面)
**路径**: `/src/swap/`
**功能**:
- 代币选择器 (支持搜索)
- 实时报价获取
- 价格影响显示
- 滑点容差设置 (0.1% - 5%)
- 交换执行与结果显示
- 代币余额显示

**预览**:
```
http://localhost:5175/src/swap/?chain=bsc&network=testnet&mock=true
```

### 3. Balance Dashboard (余额仪表板)
**路径**: `/src/balance/`
**功能**:
- 总资产价值展示
- 原生币余额
- 代币列表与价格
- 24小时涨跌幅
- 资产分布环形图
- 刷新功能

**预览**:
```
http://localhost:5175/src/balance/?chain=bsc&address=0xc520...&network=testnet&mock=true
```

## 技术栈

- **框架**: React 18.2
- **UI库**: Mantine 7.4 (现代化、简洁风格)
- **图标**: Tabler Icons
- **构建工具**: Vite 5.4
- **类型系统**: TypeScript 5.6

## 开发模式

### Mock模式
在本地开发时，使用Mock数据进行测试：

```bash
cd ui
npm run dev
```

访问时添加 `?mock=true` 参数：
```
http://localhost:5175/src/transaction/?mock=true
http://localhost:5175/src/swap/?mock=true
http://localhost:5175/src/balance/?mock=true
```

或在 `.env.development` 中设置：
```
VITE_USE_MOCK=true
```

### 真实MCP Host模式
当UI在MCP Host iframe中运行时，自动使用postMessage通信：

```typescript
// MCP Client自动检测环境
const mcp = await getMCPClient();

// 调用MCP工具
const result = await mcp.callTool('get_transaction', {
  chain: 'bsc',
  tx_hash: '0x...',
  network: 'testnet',
});
```

## URL参数

### Transaction Viewer
- `chain`: 链名称 (bsc, eth, polygon等)
- `txHash`: 交易哈希
- `network`: 网络 (mainnet, testnet)
- `mock`: 是否使用Mock模式 (true/false)

### Swap Interface
- `chain`: 链名称
- `network`: 网络
- `mock`: 是否使用Mock模式

### Balance Dashboard
- `chain`: 链名称
- `address`: 钱包地址
- `network`: 网络
- `mock`: 是否使用Mock模式

## Mock数据

Mock数据位于 `/src/lib/mcp-mock.ts`，包含：

- **get_transaction**: BSC testnet真实交易数据
- **get_tokens**: 4种代币 (BNB, USDT, BUSD, CAKE)
- **get_swap_quote**: BNB → USDT交换报价
- **execute_swap**: 交换执行结果
- **get_wallet_balance**: 钱包余额与代币持仓

## 构建产物

```bash
npm run build
```

输出位置: `dist/`

- Transaction: ~23KB (gzipped: ~8KB)
- Swap: ~82KB (gzipped: ~27KB)
- Balance: ~10KB (gzipped: ~4KB)
- 共享样式: ~270KB (gzipped: ~85KB)

## 集成到Zig服务器

### 1. 嵌入HTML资源

将 `dist/` 目录中的文件嵌入到Zig二进制：

```zig
// 在build.zig中添加
const ui_transaction = b.addModule("ui_transaction", .{
    .source_file = .{ .path = "ui/dist/src/transaction/index.html" },
});
```

### 2. 添加Tool元数据

在工具响应中添加 `_meta.ui.resourceUri`：

```zig
const response = .{
    .content = .{
        .{ .type = "text", .text = json_result },
    },
    ._meta = .{
        .ui = .{
            .resourceUri = "ui://transaction?chain=bsc&txHash=0x...",
        },
    },
};
```

### 3. 支持的MCP工具

需要在Zig服务器中实现：

- `get_transaction` - 获取交易详情
- `get_tokens` - 获取可用代币列表
- `get_swap_quote` - 获取交换报价
- `execute_swap` - 执行代币交换
- `get_wallet_balance` - 获取钱包余额

## 下一步

1. ✅ Transaction Viewer - 已完成
2. ✅ Swap Interface - 已完成
3. ✅ Balance Dashboard - 已完成
4. ⏭️ 集成到Zig服务器
5. ⏭️ 添加Tool元数据
6. ⏭️ 测试MCP Host集成
7. ⏭️ (可选) Contract Interaction Panel

## 设计风格

- **配色**: Uniswap风格 (粉色主题 Transaction, Swap界面；紫色主题 Balance)
- **布局**: 简洁卡片式
- **交互**: 流畅动画过渡
- **响应式**: 支持桌面和移动端

## 实时预览

启动开发服务器后访问：

```bash
npm run dev

# 然后在浏览器打开:
# http://localhost:5175/src/transaction/?mock=true
# http://localhost:5175/src/swap/?mock=true
# http://localhost:5175/src/balance/?mock=true
```
