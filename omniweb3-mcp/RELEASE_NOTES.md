# Release Notes - v0.2.0

## 🎉 主要功能: MCP Apps UI集成

### 新功能

#### 1. MCP Resources支持 (ui://协议)
- ✅ 实现完整的ui://协议资源服务器
- ✅ 注册4个UI资源: transaction, swap, balance, assets
- ✅ UI文件通过`@embedFile()`完全嵌入到二进制
- ✅ 支持HTML, JavaScript, CSS资源服务

**文件**:
- `src/ui/server.zig` - UI资源服务器
- `src/ui/resources.zig` - 嵌入式资源声明
- `src/ui/meta.zig` - UI元数据生成器

#### 2. 工具UI元数据集成
- ✅ `get_transaction` - 返回带有`_meta.ui.resourceUri`的响应
- ✅ `get_balance` - 返回带有`_meta.ui.resourceUri`的响应

**示例响应**:
```json
{
  "chain": "bsc",
  "transaction": {...},
  "_meta": {
    "ui": {
      "resourceUri": "ui://transaction?chain=bsc&txHash=0x..."
    }
  }
}
```

#### 3. React UI组件

**Transaction Viewer** (`ui/src/components/TransactionViewer/`)
- 交易状态指示器
- 可视化流程图 (From → Amount → To)
- 详细信息表格
- Gas分析图表
- 复制和浏览器跳转按钮

**Swap Interface** (`ui/src/components/SwapInterface/`)
- 代币选择器（支持搜索）
- 实时价格报价
- 滑点容差设置 (0.1% - 5%)
- 价格影响警告
- 交换执行按钮

**Balance Dashboard** (`ui/src/components/BalanceDashboard/`)
- 总资产价值显示
- 原生币余额
- 代币列表与价格
- 24h涨跌幅指示器
- 资产分布环形图

### 技术栈

- **UI框架**: React 18.2
- **组件库**: Mantine 7.4
- **构建工具**: Vite 5.4
- **类型系统**: TypeScript 5.6
- **图标库**: Tabler Icons
- **通信协议**: JSON-RPC 2.0 + postMessage

### 性能指标

**Bundle大小**:
- Transaction Viewer: 23 KB (8 KB gzipped)
- Swap Interface: 82 KB (27 KB gzipped)
- Balance Dashboard: 10 KB (4 KB gzipped)
- 共享样式: 470 KB (115 KB gzipped)
- **总计**: 585 KB (154 KB gzipped)

**运行时性能**:
- 首次渲染: < 100ms
- 交互响应: < 50ms
- MCP工具调用: < 2s (取决于RPC延迟)

### 开发体验

#### Mock模式
```bash
cd ui && npm run dev
# 访问 http://localhost:5175/src/transaction/?mock=true
```

无需后端即可开发和测试UI组件，使用模拟数据进行快速迭代。

#### 热重载
Vite提供毫秒级的HMR (Hot Module Replacement)，极大提升开发效率。

### 部署

#### 单一二进制
```bash
# 构建UI
cd ui && npm run build

# 复制到src目录
cp -r ui/dist/* src/ui/dist/

# 构建Zig服务器（UI自动嵌入）
zig build

# 产物
./zig-out/bin/omniweb3-mcp  # ~20MB，包含所有UI资源
```

#### Claude Desktop集成
```json
{
  "mcpServers": {
    "omniweb3": {
      "command": "/path/to/omniweb3-mcp/zig-out/bin/omniweb3-mcp"
    }
  }
}
```

### 文档

新增文档:
- `UI_INTEGRATION_COMPLETE.md` - 完整集成文档
- `INTEGRATION_STATUS.md` - 集成状态和已知问题
- `CLAUDE_DESKTOP_SETUP.md` - Claude Desktop配置指南
- `ui/MCP_INTEGRATION.md` - 技术实现细节
- `ui/COMPONENTS.md` - UI组件文档
- `claude-desktop-config.json` - 配置示例

### 破坏性变更

无

### 已知问题

1. **Debug模式内存泄漏警告** - 非关键，仅影响开发环境
2. **Bundle大小较大** - 计划优化到100KB (gzipped)
3. **资源路径硬编码** - 计划支持动态manifest

### 升级指南

从v0.1.x升级到v0.2.0:

1. 重新构建项目:
   ```bash
   cd ui && npm run build && cd ..
   cp -r ui/dist/* src/ui/dist/
   zig build
   ```

2. 更新Claude Desktop配置（如果使用）

3. 无需其他配置更改

### 下一步计划

- [ ] 实现`get_swap_quote`和`execute_swap` UI集成
- [ ] Bundle大小优化
- [ ] 支持更多链 (Ethereum, Polygon, Avalanche)
- [ ] NFT Viewer组件
- [ ] PWA功能

### 致谢

- MCP SDK: https://github.com/anthropics/mcp-zig-sdk
- Mantine UI: https://mantine.dev
- React: https://react.dev

---

**发布日期**: 2026-01-29
**版本**: v0.2.0
**标签**: mcp-apps, ui-integration, react, zig
