# Solana AI Agent 中间层 - 项目文件结构说明

## 📁 当前文件说明

本项目目前处于**调研和设计阶段**，已完成的文档包括：

```
web3mpc/
├── README.md                    # 项目总览和快速开始指南
├── RESEARCH.md                  # 深度调研报告（核心技术分析）
├── ARCHITECTURE.md              # 技术架构设计（代码级设计）
├── QUICKSTART.md                # 2小时 MVP 实现教程
├── ECOSYSTEM_ANALYSIS.md        # 竞品分析和市场定位
├── ROADMAP.md                   # 产品路线图（12个月计划）
├── ACTION_PLAN.md               # 执行行动计划（2周冲刺）
└── PROJECT_STRUCTURE.md         # 本文件
```

---

## 📖 文档阅读顺序

### 对于决策者（CTO/创始人）

1. **README.md** (5 分钟) - 了解项目概况
2. **ECOSYSTEM_ANALYSIS.md** (15 分钟) - 市场机会评估
3. **ROADMAP.md** (10 分钟) - 投资回报预期
4. **ACTION_PLAN.md** (5 分钟) - 执行计划

**总耗时**: ~35 分钟  
**决策依据**: 市场 + 技术 + 回报

---

### 对于技术负责人（架构师）

1. **RESEARCH.md** (20 分钟) - 技术可行性验证
2. **ARCHITECTURE.md** (30 分钟) - 架构设计评审
3. **QUICKSTART.md** (10 分钟) - 实施复杂度评估

**总耗时**: ~60 分钟  
**输出**: 技术风险评估报告

---

### 对于开发者（执行者）

1. **QUICKSTART.md** (边读边做 2 小时) - 动手验证
2. **ARCHITECTURE.md** (30 分钟) - 深入理解设计
3. **ACTION_PLAN.md** (10 分钟) - 制定个人计划

**总耗时**: ~3 小时  
**输出**: 可运行的 MVP

---

## 🗂️ 未来代码结构（待创建）

### 完整项目结构预览

```
solana-agent-mcp/
├── README.md                    # 项目总览
├── LICENSE                      # MIT License
├── .gitignore                   # Git 忽略规则
│
├── docs/                        # 文档目录
│   ├── RESEARCH.md              # 调研报告
│   ├── ARCHITECTURE.md          # 架构设计
│   ├── QUICKSTART.md            # 快速开始
│   ├── ECOSYSTEM_ANALYSIS.md    # 生态分析
│   ├── ROADMAP.md               # 路线图
│   ├── ACTION_PLAN.md           # 行动计划
│   ├── API.md                   # API 文档
│   └── CONTRIBUTING.md          # 贡献指南
│
├── zig-core/                    # Zig 核心引擎
│   ├── build.zig                # 构建配置
│   ├── build.zig.zon            # 依赖管理
│   ├── src/
│   │   ├── main.zig             # FFI 导出入口
│   │   ├── agent.zig            # Agent 核心逻辑
│   │   ├── rpc/
│   │   │   ├── client.zig       # RPC 客户端
│   │   │   ├── pool.zig         # 连接池
│   │   │   └── types.zig        # 类型定义
│   │   ├── tx/
│   │   │   ├── builder.zig      # 交易构建器
│   │   │   ├── signer.zig       # 签名器
│   │   │   └── simulation.zig   # 模拟执行
│   │   ├── protocols/
│   │   │   ├── jupiter.zig      # Jupiter DEX
│   │   │   ├── marginfi.zig     # Marginfi Lending
│   │   │   ├── drift.zig        # Drift Protocol
│   │   │   └── mod.zig          # 协议接口
│   │   ├── privacy/
│   │   │   ├── zk.zig           # ZK 证明
│   │   │   └── elusiv.zig       # Elusiv 集成
│   │   ├── utils/
│   │   │   ├── keypair.zig      # 密钥对
│   │   │   ├── pubkey.zig       # 公钥
│   │   │   ├── base58.zig       # Base58 编解码
│   │   │   └── whitelist.zig    # 白名单验证
│   │   └── c_api.zig            # C API 定义
│   └── tests/
│       ├── rpc_test.zig
│       ├── tx_test.zig
│       └── integration_test.zig
│
├── mcp-server/                  # MCP 服务器 (TypeScript)
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   ├── index.ts             # 服务器入口
│   │   ├── zig-bridge.ts        # Zig FFI 桥接
│   │   ├── tools/               # MCP Tools
│   │   │   ├── balance.ts       # 余额查询
│   │   │   ├── transfer.ts      # 转账
│   │   │   ├── swap.ts          # Swap
│   │   │   ├── lend.ts          # 借贷
│   │   │   └── registry.ts      # 工具注册表
│   │   ├── context/             # Context Providers
│   │   │   ├── account.ts       # 账户上下文
│   │   │   ├── market.ts        # 市场数据
│   │   │   └── protocol.ts      # 协议状态
│   │   ├── safety/              # 安全模块
│   │   │   ├── guard.ts         # 安全守卫
│   │   │   ├── simulation.ts    # 模拟执行
│   │   │   └── limits.ts        # 限额检查
│   │   └── utils/
│   │       ├── logger.ts        # 日志
│   │       └── config.ts        # 配置管理
│   └── tests/
│       ├── integration.test.ts
│       └── unit.test.ts
│
├── examples/                    # 使用示例
│   ├── basic-query.md           # 基础查询
│   ├── simple-swap.md           # 简单 Swap
│   ├── complex-strategy.yml     # 复杂策略
│   └── claude-conversation.md   # Claude 对话示例
│
├── scripts/                     # 工具脚本
│   ├── setup.sh                 # 环境搭建
│   ├── build-all.sh             # 一键构建
│   ├── test-all.sh              # 全量测试
│   └── deploy.sh                # 部署脚本
│
├── benchmarks/                  # 性能测试
│   ├── rpc_bench.zig
│   ├── tx_bench.zig
│   └── results/
│
└── infra/                       # 基础设施配置
    ├── docker/
    │   ├── Dockerfile
    │   └── docker-compose.yml
    ├── k8s/
    │   ├── deployment.yaml
    │   └── service.yaml
    └── terraform/
        └── main.tf
```

---

## 📊 代码行数估算

### MVP 阶段 (Week 2)

| 模块 | 文件数 | 代码行数 | 复杂度 |
|------|--------|---------|--------|
| **Zig Core** | 5 | ~800 | 中 |
| **MCP Server** | 4 | ~500 | 低 |
| **Tests** | 3 | ~200 | 低 |
| **文档** | 5 | ~1000 | 低 |
| **总计** | **17** | **~2500** | **中等** |

### 完整版本 (Month 6)

| 模块 | 文件数 | 代码行数 | 复杂度 |
|------|--------|---------|--------|
| **Zig Core** | 25 | ~5000 | 高 |
| **MCP Server** | 15 | ~3000 | 中 |
| **Tests** | 20 | ~2000 | 中 |
| **Dashboard** | 30 | ~4000 | 中 |
| **文档** | 15 | ~3000 | 低 |
| **总计** | **105** | **~17000** | **中高** |

---

## 🛠️ 关键文件说明

### 1. zig-core/src/main.zig
**职责**: FFI 导出层，Node.js ↔ Zig 桥梁

**示例代码**:
```zig
export fn agent_init(rpc_url: [*:0]const u8) c_int;
export fn agent_get_balance(address: [*:0]const u8) u64;
export fn agent_swap_tokens(...) ?[*:0]const u8;
```

### 2. zig-core/src/agent.zig
**职责**: Agent 核心业务逻辑

**关键结构**:
```zig
pub const Agent = struct {
    rpc: RpcClient,
    keypair: Keypair,
    
    pub fn executeIntent(intent: Intent) !Result;
};
```

### 3. mcp-server/src/index.ts
**职责**: MCP 协议服务器

**核心逻辑**:
```typescript
server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const { name, arguments } = req.params;
    const result = await zigCore.execute(name, arguments);
    return { content: [{ type: "text", text: result }] };
});
```

### 4. mcp-server/src/zig-bridge.ts
**职责**: FFI 绑定和类型转换

**关键代码**:
```typescript
const zigLib = ffi.Library(libPath, {
    'agent_swap_tokens': ['string', ['string', 'string', 'uint64', 'uint16']]
});
```

---

## 📝 文档维护策略

### 文档更新频率

| 文档 | 更新频率 | 触发条件 |
|------|---------|---------|
| **README.md** | 每次发版 | 功能变化 |
| **API.md** | 每次添加工具 | 新工具上线 |
| **ARCHITECTURE.md** | 重大重构时 | 架构变更 |
| **ROADMAP.md** | 每月 | 里程碑完成 |
| **CHANGELOG.md** | 每次提交 | 所有变更 |

---

## 🚀 下一步行动

### 立即创建的文件

```bash
# 1. 创建 GitHub 仓库
gh repo create solana-agent-mcp --public

# 2. 创建项目骨架
mkdir -p solana-agent-mcp/{zig-core/src,mcp-server/src,examples,scripts,docs}
cd solana-agent-mcp

# 3. 复制现有文档
cp ../web3mpc/*.md docs/

# 4. 创建关键配置文件
touch zig-core/build.zig
touch mcp-server/package.json
touch mcp-server/tsconfig.json
touch .gitignore LICENSE

# 5. 第一次提交
git init
git add .
git commit -m "chore: Initial project structure"
git push
```

---

## 📌 总结

### 当前状态
✅ **调研阶段完成** - 所有文档已准备好  
🚧 **代码阶段未开始** - 等待执行

### 下一个里程碑
🎯 **2 周后**: 可运行的 MVP  
📊 **衡量指标**: 能在 Claude Code 中查询 Solana 余额

### 立即行动
1. 创建 GitHub 仓库
2. 编写第一行 Zig 代码
3. 分享到社交媒体

**现在就开始吧！** 🚀
