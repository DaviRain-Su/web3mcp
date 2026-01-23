# Solana AI Agent 中间层技术架构

## 🎨 核心设计理念

**三层架构，职责分离**：
1. **协议层 (MCP)**: 标准化的 AI ↔ Blockchain 通信
2. **执行层 (Zig)**: 高性能交易构建与签名
3. **适配层 (Protocols)**: DeFi 协议抽象接口

---

## 📐 详细技术设计

### 1. MCP Server 设计

#### 1.1 Server 入口

```typescript
// mcp-server/src/index.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SolanaZigBridge } from "./zig-bridge.js";

const server = new Server(
  {
    name: "solana-agent-mcp",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  }
);

// 初始化 Zig 核心引擎
const zigCore = new SolanaZigBridge({
  rpcUrl: process.env.SOLANA_RPC_URL!,
  keypairPath: process.env.AGENT_KEYPAIR_PATH,
});

// 注册 Tools
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "solana_get_balance",
      description: "Get SOL balance of an address",
      inputSchema: {
        type: "object",
        properties: {
          address: { type: "string", description: "Solana address (base58)" }
        },
        required: ["address"]
      }
    },
    {
      name: "solana_swap",
      description: "Swap tokens using Jupiter aggregator",
      inputSchema: {
        type: "object",
        properties: {
          inputMint: { type: "string", description: "Input token mint address" },
          outputMint: { type: "string", description: "Output token mint address" },
          amount: { type: "number", description: "Amount in smallest units" },
          slippageBps: { type: "number", description: "Slippage in basis points (default: 50)", default: 50 }
        },
        required: ["inputMint", "outputMint", "amount"]
      }
    },
    {
      name: "solana_lend",
      description: "Lend tokens to Marginfi",
      inputSchema: {
        type: "object",
        properties: {
          token: { type: "string", description: "Token to lend (e.g., SOL, USDC)" },
          amount: { type: "number", description: "Amount to lend" }
        },
        required: ["token", "amount"]
      }
    }
  ]
}));

// 执行 Tool
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    let result;
    switch (name) {
      case "solana_get_balance":
        result = await zigCore.getBalance(args.address);
        break;
      case "solana_swap":
        result = await zigCore.executeSwap(args);
        break;
      case "solana_lend":
        result = await zigCore.executeLend(args);
        break;
      default:
        throw new Error(`Unknown tool: ${name}`);
    }

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(result, null, 2)
        }
      ]
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Error: ${error.message}`
        }
      ],
      isError: true
    };
  }
});

// 启动
const transport = new StdioServerTransport();
await server.connect(transport);
```

#### 1.2 Zig FFI Bridge

```typescript
// mcp-server/src/zig-bridge.ts
import ffi from 'ffi-napi';
import ref from 'ref-napi';
import path from 'path';

const StringPtr = ref.refType(ref.types.CString);

interface ZigLibrary {
  agent_init: (rpc_url: string, keypair_path: string) => number;
  agent_get_balance: (address: string) => number;
  agent_swap_tokens: (
    input_mint: string,
    output_mint: string,
    amount: number,
    slippage_bps: number
  ) => StringPtr;
  agent_free_string: (ptr: StringPtr) => void;
}

export class SolanaZigBridge {
  private lib: ZigLibrary;
  private agentHandle: number;

  constructor(config: { rpcUrl: string; keypairPath?: string }) {
    // 加载 Zig 编译的动态库
    const libPath = path.join(__dirname, '../../zig-core/zig-out/lib/libsolana_agent.so');
    
    this.lib = ffi.Library(libPath, {
      'agent_init': ['int', ['string', 'string']],
      'agent_get_balance': ['uint64', ['string']],
      'agent_swap_tokens': ['string', ['string', 'string', 'uint64', 'uint16']],
      'agent_free_string': ['void', ['string']]
    }) as ZigLibrary;

    // 初始化 Agent
    this.agentHandle = this.lib.agent_init(
      config.rpcUrl,
      config.keypairPath || ''
    );
  }

  async getBalance(address: string): Promise<{ lamports: number; sol: number }> {
    const lamports = this.lib.agent_get_balance(address);
    return {
      lamports,
      sol: lamports / 1e9
    };
  }

  async executeSwap(params: {
    inputMint: string;
    outputMint: string;
    amount: number;
    slippageBps?: number;
  }): Promise<{ signature: string; outputAmount: number }> {
    const resultPtr = this.lib.agent_swap_tokens(
      params.inputMint,
      params.outputMint,
      params.amount,
      params.slippageBps || 50
    );

    const resultJson = ref.readCString(resultPtr, 0);
    this.lib.agent_free_string(resultPtr);

    return JSON.parse(resultJson);
  }
}
```

---

### 2. Zig Core Engine 设计

#### 2.1 项目结构

```
zig-core/
├── build.zig
├── src/
│   ├── main.zig          # C FFI 导出函数
│   ├── agent.zig         # Agent 核心逻辑
│   ├── rpc/
│   │   ├── client.zig    # RPC 客户端
│   │   └── types.zig     # RPC 类型定义
│   ├── tx/
│   │   ├── builder.zig   # 交易构建器
│   │   ├── signer.zig    # 签名器
│   │   └── simulation.zig # 模拟执行
│   ├── protocols/
│   │   ├── jupiter.zig   # Jupiter DEX
│   │   ├── marginfi.zig  # Marginfi Lending
│   │   └── drift.zig     # Drift Protocol
│   └── utils/
│       ├── keypair.zig
│       ├── pubkey.zig
│       └── base58.zig
```

#### 2.2 核心代码实现

##### build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 构建为动态库
    const lib = b.addSharedLibrary(.{
        .name = "solana_agent",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 链接 C 库
    lib.linkLibC();
    
    // 安装到 zig-out/lib
    b.installArtifact(lib);

    // 测试
    const tests = b.addTest(.{
        .root_source_file = b.path("src/agent.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```

##### src/main.zig (FFI 导出)

```zig
const std = @import("std");
const Agent = @import("agent.zig").Agent;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var agent_instance: ?*Agent = null;

/// 初始化 Agent
export fn agent_init(rpc_url: [*:0]const u8, keypair_path: [*:0]const u8) c_int {
    const rpc_url_slice = std.mem.span(rpc_url);
    const keypair_path_slice = std.mem.span(keypair_path);

    const agent = allocator.create(Agent) catch return -1;
    agent.* = Agent.init(allocator, rpc_url_slice, keypair_path_slice) catch {
        allocator.destroy(agent);
        return -1;
    };

    agent_instance = agent;
    return 0;
}

/// 查询余额
export fn agent_get_balance(address: [*:0]const u8) u64 {
    const agent = agent_instance orelse return 0;
    const address_slice = std.mem.span(address);

    const balance = agent.getBalance(address_slice) catch return 0;
    return balance;
}

/// 执行 Swap
export fn agent_swap_tokens(
    input_mint: [*:0]const u8,
    output_mint: [*:0]const u8,
    amount: u64,
    slippage_bps: u16,
) ?[*:0]const u8 {
    const agent = agent_instance orelse return null;

    const result = agent.swapTokens(.{
        .input_mint = std.mem.span(input_mint),
        .output_mint = std.mem.span(output_mint),
        .amount = amount,
        .slippage_bps = slippage_bps,
    }) catch return null;

    // 序列化为 JSON 字符串
    const json = std.json.stringifyAlloc(allocator, result, .{}) catch return null;
    return @ptrCast(json.ptr);
}

/// 释放字符串
export fn agent_free_string(ptr: [*:0]const u8) void {
    const slice = std.mem.span(ptr);
    allocator.free(slice);
}
```

##### src/agent.zig

```zig
const std = @import("std");
const RpcClient = @import("rpc/client.zig").RpcClient;
const TxBuilder = @import("tx/builder.zig").TxBuilder;
const Jupiter = @import("protocols/jupiter.zig");
const Keypair = @import("utils/keypair.zig").Keypair;

pub const Agent = struct {
    allocator: std.mem.Allocator,
    rpc: RpcClient,
    keypair: Keypair,
    tx_builder: TxBuilder,

    pub fn init(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        keypair_path: []const u8,
    ) !Agent {
        const rpc = try RpcClient.init(allocator, rpc_url);
        const keypair = try Keypair.fromFile(allocator, keypair_path);
        const tx_builder = TxBuilder.init(allocator);

        return .{
            .allocator = allocator,
            .rpc = rpc,
            .keypair = keypair,
            .tx_builder = tx_builder,
        };
    }

    pub fn deinit(self: *Agent) void {
        self.rpc.deinit();
        self.tx_builder.deinit();
    }

    /// 获取账户余额
    pub fn getBalance(self: *Agent, address: []const u8) !u64 {
        const response = try self.rpc.getBalance(address);
        return response.value;
    }

    /// 执行代币交换
    pub fn swapTokens(self: *Agent, params: SwapParams) !SwapResult {
        // 1. 获取 Jupiter 报价
        const quote = try Jupiter.getQuote(
            self.allocator,
            params.input_mint,
            params.output_mint,
            params.amount,
            params.slippage_bps,
        );
        defer quote.deinit();

        // 2. 构建交易
        const tx = try Jupiter.buildSwapTransaction(
            self.allocator,
            quote,
            self.keypair.publicKey(),
        );
        defer tx.deinit();

        // 3. 模拟执行（安全检查）
        const simulation = try self.rpc.simulateTransaction(tx);
        if (simulation.err) |err| {
            std.log.err("Simulation failed: {s}", .{err});
            return error.SimulationFailed;
        }

        // 4. 签名
        try tx.sign(&[_]Keypair{self.keypair});

        // 5. 发送交易
        const signature = try self.rpc.sendTransaction(tx);

        // 6. 等待确认
        try self.rpc.confirmTransaction(signature, .finalized);

        return .{
            .signature = signature,
            .input_amount = params.amount,
            .output_amount = quote.outAmount,
            .price_impact = quote.priceImpactPct,
        };
    }
};

pub const SwapParams = struct {
    input_mint: []const u8,
    output_mint: []const u8,
    amount: u64,
    slippage_bps: u16,
};

pub const SwapResult = struct {
    signature: []const u8,
    input_amount: u64,
    output_amount: u64,
    price_impact: f64,
};
```

##### src/protocols/jupiter.zig

```zig
const std = @import("std");
const http = std.http;

pub const Quote = struct {
    inputMint: []const u8,
    outputMint: []const u8,
    inAmount: u64,
    outAmount: u64,
    priceImpactPct: f64,
    routePlan: []RoutePlanStep,

    allocator: std.mem.Allocator,

    pub fn deinit(self: Quote) void {
        self.allocator.free(self.inputMint);
        self.allocator.free(self.outputMint);
        for (self.routePlan) |step| {
            self.allocator.free(step.swapInfo.label);
        }
        self.allocator.free(self.routePlan);
    }
};

const RoutePlanStep = struct {
    swapInfo: struct {
        label: []const u8,
        inputMint: []const u8,
        outputMint: []const u8,
    },
};

/// 获取 Jupiter 报价
pub fn getQuote(
    allocator: std.mem.Allocator,
    input_mint: []const u8,
    output_mint: []const u8,
    amount: u64,
    slippage_bps: u16,
) !Quote {
    // 构建 URL
    const url = try std.fmt.allocPrint(
        allocator,
        "https://quote-api.jup.ag/v6/quote?inputMint={s}&outputMint={s}&amount={d}&slippageBps={d}",
        .{ input_mint, output_mint, amount, slippage_bps },
    );
    defer allocator.free(url);

    // HTTP 请求
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    const response = try client.fetch(allocator, .{
        .location = .{ .uri = uri },
        .method = .GET,
    });
    defer allocator.free(response.body);

    // 解析 JSON
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response.body,
        .{},
    );
    defer parsed.deinit();

    const json = parsed.value.object;

    return .{
        .allocator = allocator,
        .inputMint = try allocator.dupe(u8, json.get("inputMint").?.string),
        .outputMint = try allocator.dupe(u8, json.get("outputMint").?.string),
        .inAmount = @intCast(json.get("inAmount").?.integer),
        .outAmount = @intCast(json.get("outAmount").?.integer),
        .priceImpactPct = json.get("priceImpactPct").?.float,
        .routePlan = &[_]RoutePlanStep{}, // 简化处理
    };
}

/// 构建 Swap 交易
pub fn buildSwapTransaction(
    allocator: std.mem.Allocator,
    quote: Quote,
    user_pubkey: []const u8,
) !Transaction {
    // 调用 Jupiter Swap API
    const url = "https://quote-api.jup.ag/v6/swap";
    
    const request_body = try std.json.stringifyAlloc(allocator, .{
        .quoteResponse = quote,
        .userPublicKey = user_pubkey,
        .wrapAndUnwrapSol = true,
    }, .{});
    defer allocator.free(request_body);

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    const response = try client.fetch(allocator, .{
        .location = .{ .uri = uri },
        .method = .POST,
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
        .payload = request_body,
    });
    defer allocator.free(response.body);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response.body,
        .{},
    );
    defer parsed.deinit();

    // 从 swapTransaction 字段反序列化交易
    const swap_tx_b64 = parsed.value.object.get("swapTransaction").?.string;
    return try Transaction.fromBase64(allocator, swap_tx_b64);
}

// 简化的 Transaction 类型（实际需要完整实现）
pub const Transaction = struct {
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn fromBase64(allocator: std.mem.Allocator, b64: []const u8) !Transaction {
        const decoder = std.base64.standard.Decoder;
        const data = try allocator.alloc(u8, try decoder.calcSizeForSlice(b64));
        _ = try decoder.decode(data, b64);
        return .{ .data = data, .allocator = allocator };
    }

    pub fn deinit(self: Transaction) void {
        self.allocator.free(self.data);
    }

    pub fn sign(self: *Transaction, signers: []const Keypair) !void {
        // TODO: 实现签名逻辑
        _ = self;
        _ = signers;
    }
};
```

---

### 3. 安全机制实现

#### 3.1 Transaction Simulation

```zig
// src/tx/simulation.zig
const std = @import("std");

pub const SimulationResult = struct {
    err: ?[]const u8,
    logs: [][]const u8,
    unitsConsumed: u64,
    returnData: ?[]const u8,
};

pub fn simulateTransaction(
    rpc: *RpcClient,
    tx: Transaction,
) !SimulationResult {
    const request = .{
        .jsonrpc = "2.0",
        .id = 1,
        .method = "simulateTransaction",
        .params = .{
            tx.toBase64(),
            .{
                .encoding = "base64",
                .sigVerify = true,
                .replaceRecentBlockhash = false,
            },
        },
    };

    const response = try rpc.call(request);
    
    return .{
        .err = response.value.err,
        .logs = response.value.logs,
        .unitsConsumed = response.value.unitsConsumed,
        .returnData = response.value.returnData,
    };
}
```

#### 3.2 白名单验证

```zig
// src/utils/whitelist.zig
const std = @import("std");

const TRUSTED_PROGRAMS = [_][]const u8{
    "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4", // Jupiter V6
    "MFv2hWf31Z9kbCa1snEPYctwafyhdvnV7FZnsebVacA",  // Marginfi
    "dRiftyHA39MWEi3m9aunc5MzRF1JYuBsbn6VPcn33UH",  // Drift
};

pub fn isProgramTrusted(program_id: []const u8) bool {
    for (TRUSTED_PROGRAMS) |trusted| {
        if (std.mem.eql(u8, program_id, trusted)) {
            return true;
        }
    }
    return false;
}
```

---

### 4. 性能优化

#### 4.1 连接池

```zig
// src/rpc/pool.zig
pub const RpcPool = struct {
    clients: []*RpcClient,
    current_index: std.atomic.Value(usize),

    pub fn init(allocator: Allocator, endpoints: []const []const u8) !RpcPool {
        var clients = try allocator.alloc(*RpcClient, endpoints.len);
        for (endpoints, 0..) |endpoint, i| {
            clients[i] = try allocator.create(RpcClient);
            clients[i].* = try RpcClient.init(allocator, endpoint);
        }

        return .{
            .clients = clients,
            .current_index = std.atomic.Value(usize).init(0),
        };
    }

    pub fn getClient(self: *RpcPool) *RpcClient {
        const index = self.current_index.fetchAdd(1, .monotonic) % self.clients.len;
        return self.clients[index];
    }
};
```

#### 4.2 批量查询

```zig
pub fn getMultipleAccounts(
    rpc: *RpcClient,
    addresses: []const []const u8,
) ![]Account {
    const request = .{
        .method = "getMultipleAccounts",
        .params = .{ addresses, .{ .encoding = "base64" } },
    };
    
    const response = try rpc.call(request);
    return try parseAccounts(response.value);
}
```

---

## 🔄 数据流示例

### 完整的 Swap 流程

```
┌─────────────┐
│ User Input  │ "Swap 1 SOL to USDC"
└──────┬──────┘
       │ MCP Protocol
┌──────▼──────┐
│ MCP Server  │ 解析 Intent -> solana_swap tool
└──────┬──────┘
       │ FFI Call
┌──────▼──────┐
│  Zig Core   │ 1. Jupiter getQuote()
│             │ 2. buildSwapTransaction()
│             │ 3. simulateTransaction()
│             │    ├─ Check: units < 200k
│             │    ├─ Check: no errors
│             │    └─ Check: trusted programs
│             │ 4. signTransaction()
│             │ 5. sendTransaction()
└──────┬──────┘
       │ RPC Call
┌──────▼──────┐
│   Solana    │ Execute on-chain
└──────┬──────┘
       │ Confirmation
┌──────▼──────┐
│   Result    │ { signature, outputAmount, ... }
└─────────────┘
```

---

## 📦 部署配置

### Claude Desktop 配置

```json
{
  "mcpServers": {
    "solana-agent": {
      "command": "node",
      "args": ["/path/to/mcp-server/dist/index.js"],
      "env": {
        "SOLANA_RPC_URL": "https://api.mainnet-beta.solana.com",
        "AGENT_KEYPAIR_PATH": "/home/user/.config/solana/agent-keypair.json",
        "TRUSTED_PROGRAMS": "JUP6...,MFv2...,dRif...",
        "MAX_TX_AMOUNT_SOL": "10"
      }
    }
  }
}
```

### 环境变量

```bash
# .env
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
SOLANA_RPC_BACKUP_1=https://solana-api.projectserum.com
SOLANA_RPC_BACKUP_2=https://rpc.ankr.com/solana

# 安全配置
AGENT_KEYPAIR_PATH=/secure/path/to/keypair.json
MAX_SINGLE_TX_SOL=5
MAX_DAILY_VOLUME_SOL=100
REQUIRE_SIMULATION=true

# 性能配置
RPC_TIMEOUT_MS=30000
MAX_RETRIES=3
```

---

## 🎯 下一步实施

1. **搭建基础框架** (Week 1)
   - [ ] 初始化项目结构
   - [ ] 实现 Zig RPC 客户端
   - [ ] 测试 FFI 绑定

2. **核心功能实现** (Week 2-3)
   - [ ] Jupiter Swap 集成
   - [ ] Transaction Simulation
   - [ ] MCP Server 完整实现

3. **测试验证** (Week 4)
   - [ ] Devnet 集成测试
   - [ ] 性能基准测试
   - [ ] 安全审计

---

*Last Updated: 2026-01-23*
