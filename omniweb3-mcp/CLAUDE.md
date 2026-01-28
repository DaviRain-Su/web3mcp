# Claude Code 项目配置

## 项目说明

这是一个使用 Zig 0.16-dev 开发的 Web3/Solana MCP (Model Context Protocol) 服务器项目。

## Zig 开发

当编写 Zig 代码时，请参考以下 skills 获取正确的 API 用法：

- **Zig 0.16**: `.claude/skills/zig-0.16/SKILL.md`
- **Zig 内存管理**: `.claude/skills/zig-memory/SKILL.md`

## Solana 开发

当处理 Solana 相关代码时，请参考：

- **Solana SDK for Zig**: `.claude/skills/solana-sdk-zig/SKILL.md`

## 文档驱动开发

当需要遵循文档驱动开发实践时，请参考：

- **文档驱动开发**: `.claude/skills/doc-driven-dev/SKILL.md`

## 自动加载规则

- 当处理 `.zig` 文件时，自动参考 Zig skills
- 当修改 `build.zig` 时，参考 Zig build system 部分
- 当处理 Solana 交易、账户、程序等相关代码时，参考 Solana SDK skill

## 代码标准

- 遵循 Zig 官方代码风格
- 注重内存安全和错误处理
- 使用最新的 API，避免使用已废弃的函数

## 完善 Skills

当遇到 Zig 0.16 相关的编译错误时，可以完善 skill 内容：

### 快速记录错误

```bash
cd .claude/skills/zig-0.16
./record-error.sh "错误简述"
# 然后在 errors.md 中填写详细信息
```

### 定期整理

将 `errors.md` 中的内容定期整理到 `SKILL.md`，帮助 Claude Code 生成更准确的代码。

详细说明请查看：`.claude/skills/zig-0.16/README.md`
