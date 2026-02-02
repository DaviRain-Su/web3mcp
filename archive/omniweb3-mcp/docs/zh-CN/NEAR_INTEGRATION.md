# NEAR 集成 - 通过 MPC 实现链抽象

> **NEAR 链签名如何将 web3mcp 转变为真正的通用网关**

## 目录
- [愿景](#愿景)
- [NEAR 作为通用账户网关](#near-作为通用账户网关)
- [为什么选择 NEAR 链抽象？](#为什么选择-near-链抽象)
- [链签名如何工作](#链签名如何工作)
- [AI + MCP + NEAR 架构](#ai--mcp--near-架构)
- [对 AI 代理的优势](#对-ai-代理的优势)
- [技术集成](#技术集成)
- [基于意图的执行流程](#基于意图的执行流程)
- [实施路线图](#实施路线图)
- [解锁的用例](#解锁的用例)

---

## 愿景

**问题**: 跨多条区块链操作的 AI 代理面临一个不可能的挑战：
- 必须安全管理 Bitcoin、Ethereum、Solana 等的私钥
- 每条链都有不同的签名算法（ECDSA、Ed25519、Schnorr）
- 丢失一个密钥意味着失去该链上的资产访问权
- 密钥管理复杂性随着每条新链呈指数增长

**NEAR 的解决方案**: **一个 NEAR 账户 = 全链通用访问**

通过**链签名（多方计算）**，单个 NEAR 账户可以：
- 签署 Bitcoin 交易
- 签署 Ethereum 交易
- 签署 Solana 交易
- 签署任何使用 ECDSA 或 Ed25519 的区块链交易

**web3mcp 的角色**: 成为位于 NEAR 账户抽象之上的**意图层**

```
[用户/AI 说自然语言]
         ↓
[web3mcp 转换为意图]
         ↓
[NEAR 通过链签名执行]
         ↓
[所有区块链响应]
```

---

## NEAR 作为通用账户网关

### 传统多链模型（破碎）

```
用户想在 5 条链上操作：

┌─────────────┐
│   Bitcoin   │ ← 需要 BTC 私钥（Schnorr）
└─────────────┘

┌─────────────┐
│  Ethereum   │ ← 需要 ETH 私钥（ECDSA secp256k1）
└─────────────┘

┌─────────────┐
│   Solana    │ ← 需要 SOL 私钥（Ed25519）
└─────────────┘

┌─────────────┐
│   Cosmos    │ ← 需要 ATOM 私钥（secp256k1）
└─────────────┘

┌─────────────┐
│  Arbitrum   │ ← 需要 ARB 私钥（ECDSA secp256k1）
└─────────────┘

总计：需要管理 5 个私钥（对 AI 来说是噩梦）
```

### NEAR 链抽象模型（优雅）

```
用户有一个 NEAR 账户：

┌─────────────────────────────────────────┐
│       NEAR 账户（alice.near）           │
│                                         │
│  持有：一个 NEAR 私钥（Ed25519）        │
└─────────────────────────────────────────┘
                    ↓
          （MPC 网络签名）
                    ↓
    ┌───────────────┼───────────────┐
    ↓               ↓               ↓
┌─────────┐   ┌─────────┐   ┌─────────┐
│ Bitcoin │   │Ethereum │   │ Solana  │  ...（所有链）
└─────────┘   └─────────┘   └─────────┘

结果：AI 只需要管理一个密钥
```

### 类比

**传统方法**: 就像需要为每个国家准备不同的护照
**NEAR 方法**: 就像拥有一本**"通用护照"**，全球认可

---

## 为什么选择 NEAR 链抽象？

### 对 AI 代理：大幅简化

#### 没有 NEAR

```zig
// AI Agent 需要为每条链管理密钥
pub const AIAgent = struct {
    bitcoin_key: BitcoinPrivateKey,
    ethereum_key: EthereumPrivateKey,
    solana_key: SolanaPrivateKey,
    cosmos_key: CosmosPrivateKey,
    // ... 50 条更多链 ...

    // 每条链不同的签名逻辑
    pub fn signBitcoin(self: *Self, tx: BitcoinTx) !Signature {
        return schnorr.sign(self.bitcoin_key, tx);
    }

    pub fn signEthereum(self: *Self, tx: EthTx) !Signature {
        return ecdsa.sign(self.ethereum_key, tx);
    }

    // 安全噩梦：50+ 个私钥需要保护
};
```

#### 有 NEAR

```zig
// AI Agent 只管理一个 NEAR 账户
pub const AIAgent = struct {
    near_account: NEARAccount,  // 单一账户

    // 通过 MPC 的通用签名
    pub fn signForChain(
        self: *Self,
        chain: ChainType,
        payload: []const u8,
    ) !Signature {
        // 从 NEAR MPC 网络请求签名
        return near.requestChainSignature(.{
            .account = self.near_account,
            .chain = chain,
            .payload = payload,
        });
    }

    // 一个密钥保护所有链的访问
};
```

**安全优势**:
- 一个密钥需要备份
- 一个密钥需要轮换
- 一个密钥可能丢失（vs. 50 个密钥可能丢失）

---

## 链签名如何工作

### 多方计算（MPC）入门

**传统签名**:
```
私钥 + 消息 → 签名
```

如果私钥被盗，所有资金都会丢失。

**MPC 签名**:
```
密钥分片 1（节点 A）┐
密钥分片 2（节点 B）├─→ 签名
密钥分片 3（节点 C）┘
```

没有单个节点拥有完整私钥。它们共同计算签名而不需要组合分片。

### NEAR 的实现

1. **账户推导**: 对于每条链，NEAR 推导唯一地址
   ```
   Bitcoin 地址  = derive(NEAR 账户, "bitcoin", 路径)
   Ethereum 地址 = derive(NEAR 账户, "ethereum", 路径)
   Solana 地址   = derive(NEAR 账户, "solana", 路径)
   ```

2. **签名请求**: 用户调用 NEAR 智能合约
   ```rust
   // NEAR 智能合约（Rust）
   pub fn sign_bitcoin_tx(
       &mut self,
       tx_data: Vec<u8>,
       path: String,
   ) -> Promise {
       // 从 MPC 网络请求签名
       mpc::sign(SignRequest {
           payload: tx_data,
           path,
           key_version: 0,
       })
   }
   ```

3. **MPC 节点执行**:
   - 8+ 验证器节点参与
   - 每个都有主密钥的分片
   - 它们运行安全多方计算协议
   - 输出：目标链的有效签名

4. **签名返回**: 合约接收签名，用户广播到目标链

### 安全保证

- **无单点故障**: 需要攻破 8 个节点中的 5+
- **无需信任**: 没有节点知道你的完整私钥
- **非托管**: 你通过 NEAR 账户控制
- **已审计**: Trail of Bits、Kudelski 审查的协议

---

## AI + MCP + NEAR 架构

### 系统图

```
┌──────────────────────────────────────────────────────────────┐
│                    用户 / AI 大脑                            │
│         "把我的 USDC 换成 BTC 并发送到我的钱包"              │
└────────────────────────┬─────────────────────────────────────┘
                         │ 自然语言
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                   web3mcp（意图层）                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  意图解析器与规划器                                    │ │
│  │  - 理解："交换 USDC → BTC"                            │ │
│  │  - 规划：获取报价、批准、交换、桥接                   │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  NEAR Provider（ChainProvider 接口）                  │ │
│  │  - 构建意图 payload                                    │ │
│  │  - 请求链签名                                          │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────┬─────────────────────────────────────┘
                         │ 意图 + 签名请求
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              NEAR 协议（结算层）                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  意图智能合约                                          │ │
│  │  - 接收意图："交换 1000 USDC → BTC"                  │ │
│  │  - 发布给 Solver                                       │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  MPC 签名服务                                          │ │
│  │  - 签署 Ethereum 交易（批准 USDC）                    │ │
│  │  - 签署 Bitcoin 交易（接收 BTC）                      │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────┬─────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Ethereum   │  │   Bitcoin    │  │   Solana     │
│  （执行）    │  │  （执行）    │  │  （执行）    │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 关键组件

1. **意图层（web3mcp）**:
   - 将自然语言转换为结构化意图
   - 通过 NEAR Provider 与 NEAR 交互
   - 管理用户会话和偏好

2. **结算层（NEAR）**:
   - 存储用户的通用账户
   - 管理 MPC 签名生成
   - 协调 Solver 完成意图

3. **执行层（所有链）**:
   - 接收签名的交易
   - 执行链上操作
   - 向 NEAR 报告结果

---

## 对 AI 代理的优势

### 1. 单一账户管理

**有 NEAR 之前**:
```javascript
// AI 需要每条链的钱包
const agent = {
  ethereumWallet: new Wallet(ETHEREUM_KEY),
  solanaWallet: new Wallet(SOLANA_KEY),
  bitcoinWallet: new Wallet(BITCOIN_KEY),
  // ... 20 个更多钱包
};

// 风险：如果 AI 服务器被黑，所有密钥都被泄露
```

**有 NEAR**:
```javascript
// AI 只需要一个 NEAR 账户
const agent = {
  nearAccount: new Account(NEAR_KEY),
};

// 风险：只有一个密钥需要保护
// 好处：可以为这一个账户添加 2FA、硬件安全、session key
```

### 2. 基于意图的执行（非基于交易）

**传统（基于交易）**:
```
AI 必须知道：
- 确切的合约地址
- 确切的函数签名
- 确切的参数编码
- Gas 估算
- Nonce 管理

结果：脆弱、复杂、易出错
```

**NEAR 基于意图**:
```
AI 只需指定：
- 他们想要实现什么（意图）
- 约束（最高价格、截止时间）

Solver 弄清楚如何执行

结果：健壮、简单、适应性强
```

### 3. Gas 抽象

**传统**:
```
AI 需要：
- 持有用于 gas 的原生代币（ETH、SOL、BTC）
- 估算 gas 价格
- 处理失败的交易（gas 不足）
- 跨 50 条链管理 gas 代币
```

**NEAR**:
```
AI 支付 gas：
- NEAR 代币（通用）
- 或让 Solver 支付 gas（无 gas 交易）

Solver 处理所有链特定的 gas 逻辑
```

### 4. 即时多链支持

**传统**:
```
新链启动（例如 Monad）

添加支持需要：
- 学习 Monad 文档（1 周）
- 实现 Monad RPC 客户端（2 周）
- 添加 Monad 交易构建器（1 周）
- 在 Monad 测试网测试（1 周）

总计：5 周添加一条链
```

**NEAR**:
```
新链启动（例如 Monad）

如果 NEAR MPC 添加 Monad 支持：
- AI 获得即时访问（0 周）

如果 NEAR 尚未支持：
- 只有 NEAR 团队需要添加（不是每个 AI 开发者）
```

---

## 技术集成

### 步骤 1: 为 AI Agent 设置 NEAR 账户

```zig
// 初始化 NEAR 账户
pub fn setupNearAccount(allocator: std.mem.Allocator) !NEARAccount {
    const account_id = "ai-agent.near";
    const private_key = try loadFromSecureStorage("NEAR_PRIVATE_KEY");

    return NEARAccount.init(allocator, .{
        .account_id = account_id,
        .private_key = private_key,
        .network = .mainnet,
    });
}
```

### 步骤 2: 推导链特定地址

```zig
// 从一个 NEAR 账户推导所有链的地址
pub fn deriveAddresses(near_account: *NEARAccount) !AddressSet {
    return .{
        .ethereum = try near_account.deriveAddress(.ethereum, "m/44'/60'/0'/0/0"),
        .bitcoin = try near_account.deriveAddress(.bitcoin, "m/44'/0'/0'/0/0"),
        .solana = try near_account.deriveAddress(.solana, "m/44'/501'/0'/0'"),
        // ... 所有链
    };
}
```

### 步骤 3: 请求链签名

```zig
// 为任何链签署交易
pub fn signTransaction(
    near_account: *NEARAccount,
    chain: ChainType,
    tx_data: []const u8,
) !Signature {
    // 调用 NEAR MPC 合约
    const payload = try std.json.stringifyAlloc(allocator, .{
        .transaction = tx_data,
        .path = getDerivationPath(chain),
        .key_version = 0,
    }, .{});

    const result = try near_account.callContract(.{
        .contract_id = "v1.signer.near",
        .method_name = "sign",
        .args = payload,
        .gas = 300_000_000_000_000,  // 300 TGas
        .deposit = 0,
    });

    return parseSignature(result);
}
```

---

## 基于意图的执行流程

### 示例："交换 1000 USDC 为 BTC"

#### 步骤 1: 用户意图（自然语言）

```
用户 → AI: "我想把 1000 USDC 换成比特币"
```

#### 步骤 2: AI 解析意图（通过 web3mcp）

```zig
const intent = Intent{
    .action = .swap,
    .from_asset = .{ .chain = .ethereum, .token = "USDC", .amount = 1000 },
    .to_asset = .{ .chain = .bitcoin, .token = "BTC" },
    .constraints = .{
        .max_slippage = 0.01,  // 1%
        .deadline = now() + 600,  // 10 分钟
    },
};
```

#### 步骤 3: web3mcp 提交意图到 NEAR

```zig
// 提交意图到 NEAR 合约
const intent_id = try near_account.callContract(.{
    .contract_id = "intents.near",
    .method_name = "submit_intent",
    .args = try std.json.stringifyAlloc(allocator, intent, .{}),
    .deposit = attachedNEAR(0.1),  // Solver 激励
});
```

#### 步骤 4: NEAR 发布意图，Solver 竞争

```rust
// NEAR 智能合约（Rust）
#[near_bindgen]
impl IntentContract {
    pub fn submit_intent(&mut self, intent: Intent) -> IntentId {
        let intent_id = self.next_intent_id;
        self.intents.insert(intent_id, intent);

        // 发出事件供 Solver 查看
        env::log_str(&format!("NEW_INTENT: {}", intent_id));

        intent_id
    }
}
```

链下，Solver 看到意图并竞争：
```
Solver A: "我可以用 0.0245 BTC 完成（1inch → Wormhole）"
Solver B: "我可以用 0.0248 BTC 完成（Uniswap → 原生桥）"
Solver C: "我可以用 0.0250 BTC 完成（Curve → Li.Fi）"
```

选择最佳 Solver（C）。

#### 步骤 5: NEAR 签署所需交易

Solver C 需要：
1. Ethereum 交易：`approve(USDC, Curve)`
2. Ethereum 交易：`swap(USDC, wrapped BTC, Curve)`
3. Bitcoin 交易：`receive(BTC, user_bitcoin_address)`

NEAR MPC 签署所有三笔：

```zig
// 签署 Ethereum 批准
const eth_approval_sig = try signTransaction(
    near_account,
    .ethereum,
    buildApprovalTx(USDC, Curve, 1000),
);

// 签署 Ethereum 交换
const eth_swap_sig = try signTransaction(
    near_account,
    .ethereum,
    buildSwapTx(Curve, USDC, 1000),
);

// 接收的 Bitcoin 地址
const btc_address = try near_account.deriveAddress(.bitcoin, "m/44'/0'/0'/0/0");
```

#### 步骤 6: Solver 执行

```
1. 向 Ethereum 广播 eth_approval_sig
   ✅ 已确认

2. 向 Ethereum 广播 eth_swap_sig
   ✅ 已确认 → 接收 0.0250 wrapped BTC

3. 解包为原生 BTC

4. 发送 BTC 到用户的 btc_address
   ✅ 已确认
```

---

## 实施路线图

### 阶段 1: NEAR 账户集成（4 周）

**目标**:
- AI 可以创建和管理 NEAR 账户
- 为 Ethereum 和 Bitcoin 推导地址

**任务**:
- [ ] 在 Zig 中实现 NEAR RPC 客户端
- [ ] 添加 NEAR 账户创建流程
- [ ] 实现地址推导（Ethereum、Bitcoin）
- [ ] 在 NEAR 测试网上测试签名请求

**交付成果**: web3mcp 可以通过 NEAR MPC 签署 Ethereum 交易

### 阶段 2: 意图合约（4 周）

**目标**:
- 在 NEAR 上部署意图结算合约
- 支持基本交换意图

**任务**:
- [ ] 编写用于意图匹配的 NEAR 智能合约（Rust）
- [ ] 实现 Solver 注册系统
- [ ] 向 web3mcp 添加意图提交 API
- [ ] 构建简单的 Solver 机器人（用于测试）

**交付成果**: ETH → BTC 交换的端到端流程有效

### 阶段 3: 多链扩展（6 周）

**目标**:
- 支持 Solana、Arbitrum、Base、Optimism

**任务**:
- [ ] 为新链添加推导路径
- [ ] 实现链特定的交易构建器
- [ ] 为每条链测试 MPC 签名
- [ ] 添加多链意图（例如"5 条链上的最佳收益"）

**交付成果**: 通过一个 NEAR 账户支持 6+ 条链的通用网关

### 阶段 4: 高级功能（6 周）

**目标**:
- Session key、无 gas 交易、Solver 市场

**任务**:
- [ ] 实现 session key（限定范围的签名）
- [ ] 添加无 gas 交易支持（Solver 支付 gas）
- [ ] 构建 Solver 信誉系统
- [ ] 创建 Solver 市场 UI

**交付成果**: 生产就绪的意图结算层

---

## 解锁的用例

### 1. 真正的一键跨链交换

```
用户: "把我的 Ethereum USDC 换成 Solana SOL"

传统：
- 桥接 USDC 到 Solana（Wormhole UI）
- 等待 10 分钟
- 交换 USDC 为 SOL（Jupiter UI）
- 总计：2 个 UI，15 分钟，2 次批准

有 NEAR + web3mcp：
- AI 向 NEAR 提交意图
- Solver 处理桥接 + 交换
- 总计：1 条命令，3 分钟，1 次批准
```

### 2. 统一投资组合管理

```
用户: "显示我在所有链上的所有资产"

AI（通过 web3mcp + NEAR）：
- 从一个 NEAR 账户为 20 条链推导你的地址
- 并行查询所有链上的余额
- 呈现统一视图

Ethereum: 2.5 ETH, 5000 USDC
Bitcoin:  0.1 BTC
Solana:   100 SOL, 1000 USDC
...
总价值：125,340 美元
```

### 3. 自动跨链收益耕作

```
用户: "把我的稳定币放在收益最高的地方，
       每天重新平衡"

AI（通过 web3mcp + NEAR）：
- 检查 Aave（Ethereum）、Kamino（Solana）、Morpho（Base）的收益
- 提交意图："存入最高收益"
- Solver 跨链执行存款
- 每日：AI 检查是否存在更好的机会
- 如果是：自动提交重新平衡意图
```

无需手动桥接、交换或批准。

---

## 对比：有 vs 无 NEAR

| 方面 | 无 NEAR | 有 NEAR |
|--------|--------------|-----------|
| **密钥管理** | 50+ 个私钥 | 1 个 NEAR 账户 |
| **新链支持** | 手动集成（数周）| 自动（如果 NEAR 支持）|
| **交易模型** | 构建确切交易 | 指定意图（目标）|
| **Gas 支付** | 每条链需要原生代币 | 用 NEAR 支付或无 gas |
| **跨链操作** | 手动协调 | Solver 处理 |
| **安全风险** | 丢失一个密钥 = 丢失一条链 | 丢失 NEAR 密钥 = 可恢复 |
| **AI 复杂性** | 非常高 | 非常低 |

---

## 结论

### NEAR 是缺失的一环

**没有 NEAR**: web3mcp 是一个强大的多链工具，但仍需要管理许多密钥

**有 NEAR**: web3mcp 成为**真正的通用网关**，其中：
- AI 管理一个账户
- 用户说一种语言（意图）
- 所有链无缝访问

### 下一步

1. **原型**: 构建概念验证 NEAR 集成（Ethereum + Bitcoin）
2. **合作**: 联系 NEAR 基金会寻求资助/合作
3. **扩展**: 随着 NEAR MPC 支持添加更多链
4. **规模**: 启动意图市场和 Solver 网络

**这是 AI x Web3 的终极架构。**

---

## 资源

- [NEAR 链签名文档](https://docs.near.org/concepts/abstraction/chain-signatures)
- [NEAR MPC GitHub](https://github.com/near/mpc-recovery)
- [基于意图的架构（研究）](https://www.paradigm.xyz/2023/06/intents)
- [web3mcp 架构](./ARCHITECTURE.md)
- [web3mcp 用例](./USE_CASES.md)
- [web3mcp 商业模式](./BUSINESS_MODEL.md)
