# Solana AI Agent 中间层 - 快速开始指南

## 🚀 2 小时 MVP 实现路线

这个指南将帮助你在 **2 小时内**搭建一个可运行的原型，验证核心概念。

---

## 📋 前置要求

### 系统环境
- ✅ Zig 0.15.0+
- ✅ Node.js 20+
- ✅ Solana CLI 1.18+
- ✅ 一个 Solana Devnet 账户（带测试 SOL）

### 安装依赖

```bash
# 1. 安装 Zig（如果没有）
curl https://ziglang.org/download/0.15.0/zig-linux-x86_64-0.15.0.tar.xz | tar -xJ
export PATH=$PATH:$(pwd)/zig-linux-x86_64-0.15.0

# 2. 安装 Solana CLI
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"

# 3. 创建测试钱包
solana-keygen new --outfile ~/.config/solana/agent-devnet.json
solana config set --url devnet
solana airdrop 2  # 获取测试 SOL
```

---

## 🛠️ Step 1: 创建项目结构 (10 分钟)

```bash
mkdir -p solana-agent-mcp/{mcp-server,zig-core/src}
cd solana-agent-mcp

# 初始化 TypeScript 项目
cd mcp-server
npm init -y
npm install @modelcontextprotocol/sdk@latest ffi-napi ref-napi @types/node typescript
npx tsc --init

cd ../zig-core
```

---

## 🔧 Step 2: 实现 Zig 核心（最小化版本）(40 分钟)

### 2.1 创建 `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "solana_agent",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    b.installArtifact(lib);
}
```

### 2.2 创建 `src/main.zig` (最小实现)

```zig
const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// 全局配置
var rpc_url: []const u8 = undefined;

/// 初始化（仅保存配置）
export fn agent_init(url: [*:0]const u8) c_int {
    rpc_url = allocator.dupe(u8, std.mem.span(url)) catch return -1;
    std.log.info("Agent initialized with RPC: {s}", .{rpc_url});
    return 0;
}

/// 获取余额（调用 Solana RPC）
export fn agent_get_balance(address: [*:0]const u8) u64 {
    const addr = std.mem.span(address);
    
    // 构建 JSON-RPC 请求
    const request = std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["{s}"]}}
    , .{addr}) catch return 0;
    defer allocator.free(request);

    // 调用 RPC（简化版：使用 curl）
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", request,
            rpc_url,
        },
    }) catch return 0;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // 解析 JSON 响应
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        result.stdout,
        .{},
    ) catch return 0;
    defer parsed.deinit();

    const balance = parsed.value.object.get("result").?.object.get("value").?.integer;
    return @intCast(balance);
}

/// 释放资源
export fn agent_deinit() void {
    allocator.free(rpc_url);
    _ = gpa.deinit();
}
```

### 2.3 编译

```bash
cd zig-core
zig build -Doptimize=ReleaseFast

# 验证生成的动态库
ls -lh zig-out/lib/
# 应该看到 libsolana_agent.so (Linux) 或 .dylib (macOS)
```

---

## 🌐 Step 3: 实现 MCP Server (30 分钟)

### 3.1 创建 `src/index.ts`

```typescript
#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import ffi from "ffi-napi";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// 加载 Zig 库
const libPath = path.join(__dirname, "../../zig-core/zig-out/lib/libsolana_agent.so");
const zigLib = ffi.Library(libPath, {
  agent_init: ["int", ["string"]],
  agent_get_balance: ["uint64", ["string"]],
  agent_deinit: ["void", []],
});

// 初始化
const rpcUrl = process.env.SOLANA_RPC_URL || "https://api.devnet.solana.com";
if (zigLib.agent_init(rpcUrl) !== 0) {
  console.error("Failed to initialize agent");
  process.exit(1);
}

// 创建 MCP Server
const server = new Server(
  {
    name: "solana-agent",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// 注册工具
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "solana_get_balance",
      description: "Get SOL balance of a Solana address",
      inputSchema: {
        type: "object",
        properties: {
          address: {
            type: "string",
            description: "Solana public key (base58)",
          },
        },
        required: ["address"],
      },
    },
  ],
}));

// 执行工具
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "solana_get_balance") {
    try {
      const lamports = zigLib.agent_get_balance(args.address);
      const sol = lamports / 1e9;

      return {
        content: [
          {
            type: "text",
            text: `Address: ${args.address}\nBalance: ${sol.toFixed(9)} SOL (${lamports} lamports)`,
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Error: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  }

  return {
    content: [{ type: "text", text: `Unknown tool: ${name}` }],
    isError: true,
  };
});

// 启动服务器
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Solana Agent MCP Server running");
}

// 清理
process.on("SIGINT", () => {
  zigLib.agent_deinit();
  process.exit(0);
});

main();
```

### 3.2 配置 `package.json`

```json
{
  "name": "solana-agent-mcp",
  "version": "0.1.0",
  "type": "module",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "bin": {
    "solana-agent-mcp": "./dist/index.js"
  }
}
```

### 3.3 编译并测试

```bash
cd mcp-server
npm run build

# 手动测试（模拟 MCP 协议）
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/index.js
```

---

## 🧪 Step 4: 集成到 Claude Desktop (20 分钟)

### 4.1 配置 Claude Desktop

编辑 `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)  
或 `%APPDATA%\Claude\claude_desktop_config.json` (Windows)  
或 `~/.config/Claude/claude_desktop_config.json` (Linux)

```json
{
  "mcpServers": {
    "solana-agent": {
      "command": "node",
      "args": ["/absolute/path/to/solana-agent-mcp/mcp-server/dist/index.js"],
      "env": {
        "SOLANA_RPC_URL": "https://api.devnet.solana.com"
      }
    }
  }
}
```

### 4.2 重启 Claude Desktop

关闭并重新打开 Claude Desktop。

### 4.3 测试

在 Claude 对话框中输入：

```
请帮我查询这个 Solana 地址的余额：
9B5XszUGdMaxCZ7uSQhPzdks5ZQSmWxrmzCSvtJ6Ns6g
```

如果一切正常，你应该看到 Claude 调用 `solana_get_balance` 工具并返回余额。

---

## 🎯 Step 5: 扩展功能（可选，30 分钟）

### 添加 Token 余额查询

#### 修改 `zig-core/src/main.zig`

```zig
/// 获取 SPL Token 余额
export fn agent_get_token_balance(
    address: [*:0]const u8,
    mint: [*:0]const u8,
) u64 {
    const addr = std.mem.span(address);
    const mint_addr = std.mem.span(mint);

    const request = std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"2.0","id":1,"method":"getTokenAccountsByOwner","params":["{s}",{{"mint":"{s}"}},{{"encoding":"jsonParsed"}}]}}
    , .{ addr, mint_addr }) catch return 0;
    defer allocator.free(request);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", request,
            rpc_url,
        },
    }) catch return 0;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        result.stdout,
        .{},
    ) catch return 0;
    defer parsed.deinit();

    const accounts = parsed.value.object.get("result").?.object.get("value").?.array;
    if (accounts.items.len == 0) return 0;

    const token_amount = accounts.items[0].object
        .get("account").?.object
        .get("data").?.object
        .get("parsed").?.object
        .get("info").?.object
        .get("tokenAmount").?.object
        .get("amount").?.string;

    return std.fmt.parseInt(u64, token_amount, 10) catch 0;
}
```

#### 更新 MCP Server

在 `src/index.ts` 中添加新工具：

```typescript
{
  name: "solana_get_token_balance",
  description: "Get SPL token balance",
  inputSchema: {
    type: "object",
    properties: {
      address: { type: "string", description: "Owner address" },
      mint: { type: "string", description: "Token mint address" }
    },
    required: ["address", "mint"]
  }
}
```

---

## 📊 验证清单

完成以下检查，确保系统正常运行：

- [ ] Zig 库成功编译（`zig-out/lib/libsolana_agent.so` 存在）
- [ ] MCP Server 启动无错误
- [ ] Claude Desktop 配置正确
- [ ] 可以查询 Devnet 地址余额
- [ ] 错误处理正常（查询无效地址会返回友好错误）

---

## 🐛 常见问题

### Q1: FFI 加载失败
```
Error: Dynamic loading not supported
```

**解决方案**:
```bash
# 检查库文件权限
chmod +x zig-core/zig-out/lib/*.so

# 验证库可以被加载
ldd zig-core/zig-out/lib/libsolana_agent.so
```

### Q2: RPC 超时
```
Error: ETIMEDOUT
```

**解决方案**:
```typescript
// 在 zig-core/src/main.zig 中增加超时参数
"-m", "30",  // curl 最大执行时间 30 秒
```

### Q3: Claude Desktop 未识别 MCP Server
```
No tools available
```

**解决方案**:
1. 检查配置文件路径是否正确
2. 查看 Claude 日志：`~/Library/Logs/Claude/mcp*.log`
3. 确保 Node.js 在系统 PATH 中

---

## 🚀 下一步改进

现在你有了一个可运行的原型！接下来可以：

1. **添加 Jupiter Swap 集成** (参考 `ARCHITECTURE.md`)
2. **实现 Transaction Simulation**（安全机制）
3. **添加 Keypair 管理**（允许 Agent 签名交易）
4. **性能优化**（替换 `curl` 为原生 HTTP 客户端）
5. **错误处理增强**（重试机制、降级策略）

---

## 📚 相关资源

- [MCP 官方文档](https://spec.modelcontextprotocol.io/)
- [Solana JSON-RPC API](https://docs.solana.com/api/http)
- [Jupiter API 文档](https://station.jup.ag/docs/apis/swap-api)
- [Zig FFI 教程](https://ziglang.org/documentation/master/#C)

---

## 🎉 成功案例

如果你完成了上述步骤，你已经实现了：

✅ **世界上第一个 Zig 驱动的 Solana MCP Server**  
✅ **可以让 Claude 直接查询区块链状态**  
✅ **为构建完整的 AI DeFi Agent 打下基础**

下一步可以考虑：
- 在 GitHub 上开源（会收获大量关注）
- 申请 Solana Foundation Grant
- 参加相关 Hackathon（如 Colosseum）

**恭喜你进入 Web3 AI Agent 的前沿领域！** 🚀

---

*Last Updated: 2026-01-23*
*Estimated Completion Time: 2 hours*
