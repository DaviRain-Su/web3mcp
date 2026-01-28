# Zig 0.16 Skill - 使用指南

## 关于这个 Skill

这个 skill 记录了从 Zig 0.15 迁移到 0.16-dev 过程中的 API 变更、常见错误和解决方案。由于 Zig 0.16 还在开发中，API 可能继续变化，因此这个 skill 需要持续更新。

## 文件说明

```
zig-0.16/
├── SKILL.md              # 主要的 skill 内容（AI 读取）
├── README.md            # 本文件，使用说明
├── CONTRIBUTING.md      # 完善 skill 的详细指南
├── errors.md            # 快速记录错误的临时文件
└── record-error.sh      # 快速记录错误的脚本
```

## 日常使用工作流程

### 1. 当你遇到编译错误时

```bash
# 快速创建一个错误记录
cd .claude/skills/zig-0.16
./record-error.sh "你的错误简述"
```

这会在 `errors.md` 中添加一个模板，然后：

1. 打开 `errors.md`
2. 填写错误信息、旧代码、修复代码
3. 添加说明和参考链接

### 2. 手动记录（不用脚本）

直接编辑 `errors.md`，按照以下格式：

```markdown
## 2026-01-28 - std.Io.randomSecure 使用问题

**错误信息：**
```
error: expected type '*std.Io', found '*const std.Io'
```

**旧代码：**
```zig
var buf: [32]u8 = undefined;
std.Io.randomSecure(io, &buf);
```

**修复代码：**
```zig
var buf: [32]u8 = undefined;
const io_ptr: *std.Io = @constCast(io);
io_ptr.randomSecure(&buf);
```

**说明：**
- std.Io.randomSecure 需要可变指针
- 需要使用 @constCast 转换
```

### 3. 定期整理到 SKILL.md

每周或累积一定数量后：

1. 打开 `errors.md` 和 `SKILL.md`
2. 将 `errors.md` 中的内容归类整理到 `SKILL.md` 对应章节
3. 相似的错误可以合并
4. 清空 `errors.md`（保留标题）

### 4. Claude Code 会自动使用

当你编写 Zig 代码时，Claude Code 会自动参考 `SKILL.md`，避免生成已知的错误代码。

## 快速查询

### 查看已记录的错误

```bash
cat .claude/skills/zig-0.16/errors.md
```

### 搜索特定 API 的问题

```bash
grep -n "std.fmt" .claude/skills/zig-0.16/SKILL.md
```

### 查看所有待整理的错误

```bash
grep "^## 2" .claude/skills/zig-0.16/errors.md
```

## 示例工作流程

假设你在写代码时遇到这个错误：

```
error: no member named 'tcpConnectToHost' in namespace 'std.Io.net'
```

**步骤 1：快速记录**

```bash
./record-error.sh "std.Io.net.tcpConnectToHost 不存在"
```

**步骤 2：填写 errors.md**

打开 `errors.md`，填写：

```markdown
## 2026-01-28 - std.Io.net.tcpConnectToHost 不存在

**错误信息：**
```
error: no member named 'tcpConnectToHost' in namespace 'std.Io.net'
```

**旧代码：**
```zig
const stream = try std.Io.net.tcpConnectToHost(allocator, "example.com", 80);
```

**修复代码：**
```zig
// 使用新的 Io vtable API
const io = std.Io.Threaded.global_single_threaded.ioBasic();
const addr = try std.Io.net.IpAddress.parseIp("93.184.216.34", 80);
var stream: std.Io.Stream = undefined;
try io.vtable.netConnectIp(&stream, addr);
```

**说明：**
- Zig 0.16 移除了 tcpConnectToHost 高级函数
- 需要使用 Io vtable 的 netConnectIp
- 需要先解析 IP 地址（或手动 DNS 查询）

**参考：**
- std.Io.net 源码
- 相关的迁移 commit
```

**步骤 3：继续开发**

修复后继续开发，下次再遇到类似错误时重复此流程。

**步骤 4：定期整理**

周末或完成功能后，将 `errors.md` 的内容整理到 `SKILL.md` 的 "Std.Io replaces std.net" 章节。

## 高级技巧

### 1. 与团队共享

如果多人开发，可以：
- 将 `.claude/skills/` 加入 git
- 定期 pull 获取团队成员的更新
- 提交你的改进

### 2. 贡献回上游

有价值的内容可以贡献回 https://github.com/zigcc/skills：

```bash
cd /tmp
git clone https://github.com/zigcc/skills.git
cd skills
# 创建新分支
git checkout -b update-zig-0.16

# 复制你完善的内容
cp ~/.../your-project/.claude/skills/zig-0.16/SKILL.md zig-0.16/

# 提交 PR
git add zig-0.16/SKILL.md
git commit -m "feat(zig-0.16): add xxx API changes"
git push origin update-zig-0.16
```

### 3. 版本控制策略

```bash
# 跟踪 skill 变更
git add .claude/skills/zig-0.16/
git commit -m "docs(skill): update zig-0.16 with xxx errors"

# 不跟踪临时文件（可选）
echo ".claude/skills/*/errors.md" >> .gitignore
```

## 需要帮助？

- 查看 `CONTRIBUTING.md` 了解详细的完善指南
- 参考已有的 `SKILL.md` 内容格式
- 在项目中直接问 Claude Code："这个错误应该怎么记录到 skill？"

## 维护频率建议

- **实时记录**：遇到错误立即记录到 `errors.md`
- **每周整理**：将 `errors.md` 整理到 `SKILL.md`
- **每月审查**：检查 SKILL.md 的准确性，删除过时内容
- **版本升级后**：Zig 0.16 正式发布后，创建归档版本
