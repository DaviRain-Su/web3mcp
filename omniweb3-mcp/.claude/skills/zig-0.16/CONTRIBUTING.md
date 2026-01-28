# 完善 Zig 0.16 Skill 指南

## 工作流程

当你在开发过程中遇到 Zig 0.16 相关的错误时，可以按照以下步骤完善这个 skill：

### 1. 遇到错误时

当编译或运行代码遇到错误时：

1. **记录错误信息**：复制完整的编译器错误信息
2. **找到原因**：确认是 API 变更、废弃函数还是新的要求
3. **找到解决方案**：查看官方文档、源代码或社区讨论
4. **验证修复**：确保代码能正常工作

### 2. 添加到 SKILL.md

根据错误类型选择合适的章节：

#### 格式模板

```markdown
## [功能模块名称]

### [具体 API 或特性]

**错误示例（0.15 或旧版）：**
```zig
// 会报错的代码
const old_api = std.something.oldFunction();
```

**错误信息：**
```
error: no member named 'oldFunction' in struct 'something'
```

**正确示例（0.16-dev）：**
```zig
// 正确的代码
const new_api = std.something.newFunction();
```

**说明：**
- 简要说明为什么变更
- 如何迁移
- 注意事项
```

### 3. 常见错误分类

按照以下分类添加内容：

#### A. API 重命名/移动
```markdown
## [模块名] API 变更

- `std.old.path.function` → `std.new.path.function`
- 原因：[说明]
```

#### B. 参数变更
```markdown
## [函数名] 参数变更

**旧签名：**
```zig
fn oldFunc(a: Type1) ReturnType
```

**新签名：**
```zig
fn newFunc(a: Type1, b: Type2) ReturnType
```

**迁移：**
- 新增的参数 `b` 用于 [目的]
```

#### C. 完全移除
```markdown
## [被移除的 API]

**移除原因：** [说明]

**替代方案：**
```zig
// 使用新的方式
const replacement = ...;
```
```

### 4. 实际例子

假设你遇到这个错误：

```
error: no member named 'allocPrint' in struct 'std.fmt'
```

你应该这样添加：

```markdown
## std.fmt 变更

### allocPrint 移除

**错误代码：**
```zig
const str = try std.fmt.allocPrint(allocator, "Hello {s}", .{name});
```

**错误信息：**
```
error: no member named 'allocPrint' in struct 'std.fmt'
```

**正确代码：**
```zig
const str = try std.fmt.allocPrint(allocator, "Hello {s}", .{name}); // 实际可用的新 API
// 或者
var buf: [1024]u8 = undefined;
const str = try std.fmt.bufPrint(&buf, "Hello {s}", .{name});
```

**说明：**
- 0.16 中 `std.fmt.allocPrint` 签名可能有变化，需要检查当前版本
- 建议使用 `bufPrint` 或新的 writer API
```

## 快速记录模板

创建 `.claude/skills/zig-0.16/errors.md` 文件作为临时记录：

```markdown
# 待整理的错误记录

## [日期] - [错误简述]

**错误信息：**
```
[粘贴错误]
```

**旧代码：**
```zig
[出错的代码]
```

**修复代码：**
```zig
[修复后的代码]
```

**参考：**
- [相关文档链接]
- [commit hash 如果有]

---
```

## 整理和合并

定期（比如每周）将 `errors.md` 中的内容整理到 `SKILL.md`：

1. 归类相似的错误
2. 合并重复的内容
3. 完善说明和示例
4. 清理 `errors.md`

## 贡献回原仓库

如果你发现了有价值的内容，可以：

1. Fork https://github.com/zigcc/skills
2. 更新 `zig-0.16/SKILL.md`
3. 提交 Pull Request
4. 帮助其他开发者

## 最佳实践

1. **代码要可运行**：确保示例代码能编译通过
2. **错误信息要完整**：包含编译器输出的关键部分
3. **说明要简洁**：直击要点，不要冗长
4. **分类要合理**：相关的内容放在一起
5. **保持更新**：Zig 0.16 还在开发中，API 可能继续变化

## 工具辅助

你可以创建一个简单的脚本来快速记录错误：

```bash
#!/bin/bash
# .claude/skills/zig-0.16/record-error.sh

echo "## $(date +%Y-%m-%d) - $1" >> errors.md
echo "" >> errors.md
echo "**错误信息：**" >> errors.md
echo '```' >> errors.md
pbpaste >> errors.md  # macOS 剪贴板
echo '```' >> errors.md
echo "" >> errors.md
echo "**旧代码：**" >> errors.md
echo '```zig' >> errors.md
echo "```" >> errors.md
echo "" >> errors.md
echo "**修复代码：**" >> errors.md
echo '```zig' >> errors.md
echo "```" >> errors.md
echo "" >> errors.md
echo "---" >> errors.md
echo "记录已添加到 errors.md，请补充代码和说明"
```

使用：
```bash
chmod +x .claude/skills/zig-0.16/record-error.sh
./claude/skills/zig-0.16/record-error.sh "std.fmt.allocPrint 问题"
```
