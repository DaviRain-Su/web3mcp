#!/bin/bash
# 快速记录 Zig 0.16 错误的脚本

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
ERRORS_FILE="$SKILL_DIR/errors.md"

if [ -z "$1" ]; then
    echo "用法: ./record-error.sh '错误简述'"
    echo "例如: ./record-error.sh 'std.fmt.allocPrint 不存在'"
    exit 1
fi

# 添加记录模板
cat >> "$ERRORS_FILE" << EOF

## $(date +%Y-%m-%d) - $1

**错误信息：**
\`\`\`
[粘贴编译器错误信息]
\`\`\`

**旧代码：**
\`\`\`zig
// 出错的代码
\`\`\`

**修复代码：**
\`\`\`zig
// 修复后的代码
\`\`\`

**说明：**
- [为什么会出错]
- [如何修复]
- [注意事项]

**参考：**
- [相关文档或 commit]

---
EOF

echo "✓ 错误记录模板已添加到 $ERRORS_FILE"
echo "请打开文件填写详细内容"
