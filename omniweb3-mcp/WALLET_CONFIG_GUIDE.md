# 🔐 钱包配置指南

## 概述

MCP Server 支持三种方式管理 EVM 私钥：

1. ✅ **环境变量** - 最方便的方式
2. ✅ **配置文件** - 更安全的本地存储
3. ✅ **工具参数** - 临时测试使用

## 方式 1: 环境变量（推荐用于开发测试）

### 设置环境变量

在启动服务器前设置：

```bash
export EVM_PRIVATE_KEY="0x1234567890abcdef..."
```

或者在 `.env.bsc-testnet` 文件中添加：

```bash
# BSC Testnet Configuration
HOST=127.0.0.1
PORT=8765
MCP_WORKERS=4
ENABLE_DYNAMIC_TOOLS=false

# EVM Wallet Configuration
EVM_PRIVATE_KEY="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
```

### 使用环境变量启动

```bash
# 加载 .env 文件
source .env.bsc-testnet

# 启动服务器
./scripts/start-bsc-testnet.sh
```

### 测试转账（使用环境变量中的私钥）

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "transfer",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "to_address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
      "amount": "10000000000000000",
      "wallet_type": "local"
    }
  }'
```

**注意**: 私钥会自动从环境变量 `EVM_PRIVATE_KEY` 中读取。

---

## 方式 2: 配置文件（推荐用于生产）

### 创建密钥文件

默认路径：`~/.config/evm/keyfile.json`

#### 格式 1: 简单字符串

```bash
mkdir -p ~/.config/evm
cat > ~/.config/evm/keyfile.json << 'EOF'
"0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
EOF
```

#### 格式 2: JSON 对象（推荐）

```bash
mkdir -p ~/.config/evm
cat > ~/.config/evm/keyfile.json << 'EOF'
{
  "private_key": "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  "address": "0xYourAddress",
  "description": "BSC Testnet Wallet"
}
EOF
```

### 设置文件权限（重要！）

```bash
chmod 600 ~/.config/evm/keyfile.json
```

### 使用配置文件

```bash
# 不需要设置 EVM_PRIVATE_KEY 环境变量
# 服务器会自动读取 ~/.config/evm/keyfile.json

./scripts/start-bsc-testnet.sh
```

### 测试转账（使用配置文件）

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "transfer",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "to_address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
      "amount": "10000000000000000",
      "wallet_type": "local"
    }
  }'
```

### 使用自定义路径

如果你想使用其他路径：

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "transfer",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "to_address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
      "amount": "10000000000000000",
      "wallet_type": "local",
      "keypair_path": "/path/to/your/custom/keyfile.json"
    }
  }'
```

---

## 方式 3: 工具参数（用于临时测试）

直接在调用工具时传递私钥：

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "transfer",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "to_address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
      "amount": "10000000000000000",
      "wallet_type": "local",
      "private_key": "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    }
  }'
```

**⚠️ 警告**: 此方式仅用于临时测试，不要在生产环境使用！

---

## 优先级顺序

当多个配置方式同时存在时，优先级如下：

```
1. 工具参数 private_key（最高优先级）
2. 环境变量 EVM_PRIVATE_KEY
3. 配置文件 ~/.config/evm/keyfile.json（最低优先级）
```

---

## 完整示例：BSC Testnet 转账

### 步骤 1: 配置私钥

选择一种方式配置私钥（推荐方式 2：配置文件）

```bash
# 创建配置文件
mkdir -p ~/.config/evm
cat > ~/.config/evm/keyfile.json << 'EOF'
{
  "private_key": "YOUR_PRIVATE_KEY_HERE",
  "address": "YOUR_ADDRESS_HERE",
  "description": "BSC Testnet Testing Wallet"
}
EOF

# 设置权限
chmod 600 ~/.config/evm/keyfile.json
```

### 步骤 2: 获取测试 BNB

访问水龙头：https://testnet.bnbchain.org/faucet-smart

### 步骤 3: 启动服务器

```bash
./scripts/start-bsc-testnet.sh
```

### 步骤 4: 查询余额

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "evm_get_balance",
    "arguments": {
      "chain": "bsc",
      "network": "testnet",
      "address": "YOUR_ADDRESS_HERE"
    }
  }' | jq '.content[0].text'
```

### 步骤 5: 发送转账

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "transfer",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "to_address": "0x0000000000000000000000000000000000000001",
      "amount": "10000000000000000",
      "wallet_type": "local",
      "tx_type": "eip1559",
      "confirmations": 1
    }
  }' | jq '.'
```

### 步骤 6: 在浏览器查看交易

复制返回的交易 hash，在 BSC Testnet 浏览器查看：
https://testnet.bscscan.com/tx/YOUR_TX_HASH

---

## 🔒 安全最佳实践

### ✅ 推荐做法

1. **使用配置文件** - 比环境变量更安全
2. **设置正确权限** - `chmod 600 ~/.config/evm/keyfile.json`
3. **分离测试和生产私钥** - 永远不要在测试网使用主网私钥
4. **使用 .gitignore** - 确保私钥文件不被提交到 git
5. **定期轮换密钥** - 定期更换测试私钥

### ❌ 避免做法

1. **不要在代码中硬编码私钥**
2. **不要将私钥提交到 git**
3. **不要在日志中打印私钥**
4. **不要在主网使用测试私钥**
5. **不要共享私钥文件**

### 🛡️ .gitignore 配置

确保你的 `.gitignore` 包含：

```gitignore
# Wallet configuration
.env*
!.env.example
*.json.bak
keyfile.json
wallet.json

# Sensitive files
**/id.json
**/.config/evm/
**/.config/solana/
```

---

## 🧪 测试配置

### 验证私钥配置

创建测试脚本：

```bash
cat > scripts/test-wallet-config.sh << 'EOF'
#!/bin/bash

echo "🔐 Testing Wallet Configuration"
echo ""

# Test 1: Check if keyfile exists
if [ -f ~/.config/evm/keyfile.json ]; then
    echo "✅ Keyfile found: ~/.config/evm/keyfile.json"

    # Check permissions
    PERMS=$(stat -f "%OLp" ~/.config/evm/keyfile.json 2>/dev/null || stat -c "%a" ~/.config/evm/keyfile.json 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
        echo "✅ Permissions correct: 600"
    else
        echo "⚠️  Permissions: $PERMS (should be 600)"
        echo "   Run: chmod 600 ~/.config/evm/keyfile.json"
    fi
else
    echo "❌ Keyfile not found: ~/.config/evm/keyfile.json"
fi

echo ""

# Test 2: Check environment variable
if [ -n "$EVM_PRIVATE_KEY" ]; then
    echo "✅ EVM_PRIVATE_KEY environment variable is set"
else
    echo "⚠️  EVM_PRIVATE_KEY not set (will use keyfile)"
fi

echo ""
echo "Configuration priority:"
echo "  1. Tool parameter 'private_key'"
echo "  2. Environment variable 'EVM_PRIVATE_KEY'"
echo "  3. Keyfile '~/.config/evm/keyfile.json'"
EOF

chmod +x scripts/test-wallet-config.sh
./scripts/test-wallet-config.sh
```

---

## 📚 相关工具

### 支持钱包配置的工具

- `transfer` - 原生代币转账
- `sign_and_send` - 签名并发送交易
- `wallet_status` - 查询钱包状态

### 查看钱包地址

```bash
curl -X POST http://127.0.0.1:8765/mcp/v1/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "wallet_status",
    "arguments": {
      "chain": "bnb",
      "network": "testnet",
      "wallet_type": "local"
    }
  }' | jq '.'
```

---

## 🆘 故障排除

### 问题 1: "KeypairFileNotFound"

**原因**: 配置文件不存在或路径错误

**解决**:
```bash
# 检查文件是否存在
ls -la ~/.config/evm/keyfile.json

# 创建配置文件
mkdir -p ~/.config/evm
echo '{"private_key": "0x..."}' > ~/.config/evm/keyfile.json
chmod 600 ~/.config/evm/keyfile.json
```

### 问题 2: "KeypairInvalidFormat"

**原因**: JSON 格式错误

**解决**:
```bash
# 验证 JSON 格式
jq '.' ~/.config/evm/keyfile.json

# 正确的格式示例
{
  "private_key": "0x..."
}
```

### 问题 3: "Invalid private key"

**原因**: 私钥格式不正确

**解决**:
- 确保私钥以 `0x` 开头
- 确保是 64 个十六进制字符（不含 0x 前缀）
- 完整格式：`0x` + 64位十六进制 = 66 个字符

---

## 下一步

1. ✅ 配置私钥（选择一种方式）
2. ✅ 测试基本查询（余额、nonce）
3. ✅ 测试转账功能
4. ✅ 查看 BSC_TESTNET_GUIDE.md 了解更多
