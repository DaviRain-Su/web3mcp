# Zig 0.16 快速参考卡片

## 🚀 快速开始

```bash
# 检查版本
zig version  # 应该 >= 0.16.0-dev.2261

# 构建
cd omniweb3-mcp
zig build

# 测试
./test_build.sh

# 运行
./zig-out/bin/omniweb3-mcp
```

## 📋 常用命令

| 命令 | 说明 |
|------|------|
| `zig build` | 构建项目 (Debug) |
| `zig build -Doptimize=ReleaseFast` | Release 构建 |
| `zig build clean` | 清理构建产物 |
| `rm -rf .zig-cache zig-out` | 完全清理 |
| `./test_build.sh` | 运行测试 |

## 🔧 API 速查表

### stdout 写入

```zig
// Zig 0.16
const stdout_fd = std.posix.STDOUT_FILENO;
_ = std.os.linux.write(stdout_fd, message.ptr, message.len);

// 或使用 helper
writeToFd(stdout_fd, message) catch ...;
```

### stdin 读取

```zig
// Zig 0.16
const stdin_fd = std.posix.STDIN_FILENO;
const result = std.os.linux.read(stdin_fd, buffer.ptr, buffer.len);
const bytes_read: usize = @intCast(result);

// 或使用 helper
const bytes_read = readFromFd(stdin_fd, &buffer) catch ...;
```

### 环境变量

```zig
// Zig 0.16 (需要 libc)
const c = @cImport({
    @cInclude("stdlib.h");
});

if (c.getenv("HOME")) |value_c| {
    const value = std.mem.span(value_c);
    // 使用 value
}
```

### 打开文件

```zig
// Zig 0.16 (Linux)
const path_z = try allocator.dupeZ(u8, path);
defer allocator.free(path_z);

const flags: std.os.linux.O = .{ .ACCMODE = .RDONLY };
const fd = std.os.linux.open(path_z.ptr, flags, 0);
if (fd < 0) return error.OpenFailed;
defer _ = std.os.linux.close(@intCast(fd));

// 读取
var buffer: [1024]u8 = undefined;
const result = std.os.linux.read(@intCast(fd), buffer.ptr, buffer.len);
if (result < 0) return error.ReadFailed;
const bytes_read: usize = @intCast(result);
```

### Build System

```zig
// build.zig - Zig 0.16
const exe = b.addExecutable(.{
    .name = "app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,  // 如果需要 libc
    }),
});
```

## 🐛 常见错误

### 错误 1: `no member named 'writeAll'`

```
error: no field or member function named 'writeAll' in 'Io.File'
```

**解决**: 使用 `std.os.linux.write()` 或 helper 函数

### 错误 2: `no member named 'getenv'`

```
error: root source file struct 'posix' has no member named 'getenv'
```

**解决**: 使用 C 的 `getenv()` 通过 `@cImport`

### 错误 3: `no member named 'openFileAbsolute'`

```
error: root source file struct 'fs' has no member named 'openFileAbsolute'
```

**解决**: 使用 `std.os.linux.open()` 系统调用

### 错误 4: `no field or member function named 'linkLibC'`

```
error: no field or member function named 'linkLibC'
```

**解决**: 在 `createModule` 中设置 `link_libc = true`

## 📚 文档链接

- [详细迁移指南](./ZIG_0.16_MIGRATION.md)
- [用户手册](./README.zig-0.16.md)
- [升级完成报告](./UPGRADE_COMPLETE.md)

## 🔗 依赖仓库

- [solana-sdk-zig#zig-0.16](https://github.com/DaviRain-Su/solana-sdk-zig/tree/zig-0.16)
- [solana-client-zig#zig-0.16](https://github.com/DaviRain-Su/solana-client-zig/tree/zig-0.16)

## ⚠️ 限制

- ✅ Linux: 完全支持
- ❌ Windows: 未实现
- ❌ macOS: 未实现
- ⚠️ 需要 libc

## 💡 小技巧

1. **清理缓存**: 构建出错时先清理 `rm -rf ~/.cache/zig .zig-cache`
2. **查看依赖**: `ls ~/.cache/zig/p/` 查看已下载的依赖
3. **Release 构建**: 使用 `-Doptimize=ReleaseFast` 减小二进制大小
4. **调试**: 使用 `std.debug.print()` 输出调试信息

---

**版本**: Zig 0.16.0-dev.2261+d6b3dd25a  
**更新**: 2026-01-23
