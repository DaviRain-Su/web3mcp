# Zig 0.16 Migration Summary

## 概述

成功将 `omniweb3-mcp` 项目迁移到 Zig 0.16，包括所有依赖项和代码适配。

## 依赖更新

### build.zig.zon

更新了以下依赖到 zig-0.16 分支：

```zig
.dependencies = .{
    .mcp = .{ .path = "deps/mcp.zig" },
    .solana_client = .{
        .url = "git+https://github.com/DaviRain-Su/solana-client-zig.git#zig-0.16",
        .hash = "1220657db2fce280d699403a3f0dba427d8767ed21dd05487bc2409d3ad480438eab",
    },
    .solana_sdk = .{
        .url = "git+https://github.com/DaviRain-Su/solana-sdk-zig.git#zig-0.16",
        .hash = "solana_sdk-0.1.0-J3orT3VWCACNq3Kziv3YTb7KE85t8-xDjawoxj6DHmPt",
    },
    .zabi = .{
        .url = "git+https://github.com/DaviRain-Su/zabi.git#4bf0d593937105e60160f7c91fc81be85cc5bd3a",
        .hash = "1220fb5fdd6d3327dcfbedf629f30331d5aaa215f3ecae27b61dd74166c0988a9991",
    },
},
```

**注意**: `solana_sdk` 使用与 `solana-client-zig` 中相同的哈希值，避免了重复依赖冲突。

## Zig 0.16 API 变更适配

### 1. File I/O API 变更

#### 问题
Zig 0.16 中：
- `std.fs.File` → `std.Io.File`
- `File.stdout()` / `File.stdin()` / `File.stderr()` 仍存在，但没有 `writeAll()` 和 `read()` 方法
- 新的 I/O 系统需要 `Io` 对象和 buffer

#### 解决方案
直接使用 Linux 系统调用（`deps/mcp.zig/src/transport/transport.zig`）：

```zig
// Helper functions for Zig 0.16 File I/O
fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) !void {
    if (builtin.os.tag == .linux) {
        var index: usize = 0;
        while (index < bytes.len) {
            const written = std.os.linux.write(fd, bytes[index..].ptr, bytes[index..].len);
            if (written == 0) return error.WriteError;
            index += written;
        }
    } else {
        @compileError("Unsupported OS");
    }
}

fn readFromFd(fd: std.posix.fd_t, buffer: []u8) !usize {
    if (builtin.os.tag == .linux) {
        const result = std.os.linux.read(fd, buffer.ptr, buffer.len);
        if (result < 0) return error.ReadError;
        return @intCast(result);
    } else {
        @compileError("Unsupported OS");
    }
}
```

**使用示例**:
```zig
// stdout
const stdout_fd = std.posix.STDOUT_FILENO;
try writeToFd(stdout_fd, message);

// stdin
const stdin_fd = std.posix.STDIN_FILENO;
const bytes_read = try readFromFd(stdin_fd, &buf);
```

### 2. 环境变量 API 变更

#### 问题
- `std.posix.getenv()` 不存在
- `std.process.getEnvVarOwned()` 也不存在

#### 解决方案
使用 C 的 `getenv` 函数（`src/tools/transfer.zig`）：

```zig
// C interop for getenv
const c = @cImport({
    @cInclude("stdlib.h");
});

fn getDefaultKeypairPath(allocator: std.mem.Allocator) ![]const u8 {
    if (c.getenv("SOLANA_KEYPAIR")) |env_path_c| {
        const env_path = std.mem.span(env_path_c);
        return allocator.dupe(u8, env_path);
    }
    
    const home_c = c.getenv("HOME") orelse return error.HomeNotFound;
    const home = std.mem.span(home_c);
    return std.fmt.allocPrint(allocator, "{s}/.config/solana/id.json", .{home});
}
```

**注意**: 需要链接 libc

### 3. 文件系统 API 变更

#### 问题
- `std.fs.openFileAbsolute()` 不存在
- `std.fs.cwd()` 不存在
- 文件操作移到了新的 `std.Io` 系统

#### 解决方案
使用 Linux 系统调用打开文件（`src/tools/transfer.zig`）：

```zig
fn loadKeypairFromFile(allocator: std.mem.Allocator, path: []const u8) !Keypair {
    // Add null terminator for C path
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    
    // Open file using Linux syscall
    const flags: std.os.linux.O = .{ .ACCMODE = .RDONLY };
    const fd = std.os.linux.open(path_z.ptr, flags, 0);
    if (fd < 0) return error.KeypairFileNotFound;
    defer _ = std.os.linux.close(@intCast(fd));
    
    // Read file content
    var buffer: [1024]u8 = undefined;
    const bytes_read = std.os.linux.read(@intCast(fd), buffer[0..].ptr, buffer.len);
    if (bytes_read < 0) return error.KeypairReadFailed;
    
    const content = try allocator.dupe(u8, buffer[0..@intCast(bytes_read)]);
    defer allocator.free(content);
    // ... continue processing
}
```

### 4. Build System API 变更

#### 问题
- `exe.linkLibC()` 方法不存在

#### 解决方案
在 `createModule` 时设置 `link_libc` 选项（`build.zig`）：

```zig
const exe = b.addExecutable(.{
    .name = "omniweb3-mcp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,  // ← 这里
    }),
});
```

## 修改的文件清单

1. **omniweb3-mcp/build.zig.zon**
   - 更新 `solana_client` 到 zig-0.16 分支
   - 更新 `solana_sdk` 哈希值
   - 更新 `zabi` 到明确的 commit hash

2. **omniweb3-mcp/build.zig**
   - 添加 `link_libc = true` 到 module 选项

3. **omniweb3-mcp/deps/mcp.zig/src/transport/transport.zig**
   - 添加 `writeToFd()` 和 `readFromFd()` helper 函数
   - 更新 `send()` 使用 `writeToFd()`
   - 更新 `receive()` 使用 `readFromFd()`
   - 更新 `writeStderr()` 使用 `writeToFd()`

4. **omniweb3-mcp/src/tools/transfer.zig**
   - 添加 C interop for `getenv`
   - 更新 `getDefaultKeypairPath()` 使用 C 的 `getenv`
   - 更新 `loadKeypairFromFile()` 使用 Linux 系统调用

## 构建结果

```bash
$ cd omniweb3-mcp && zig build
# 构建成功，无错误

$ ls -lh zig-out/bin/
-rwxrwxr-x 1 davirain davirain 30M  1月 23 19:01 omniweb3-mcp

$ file zig-out/bin/omniweb3-mcp
zig-out/bin/omniweb3-mcp: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), 
dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, 
with debug_info, not stripped
```

## 注意事项

1. **平台限制**: 当前实现仅支持 Linux，因为使用了 `std.os.linux` 系统调用
2. **libc 依赖**: 项目现在需要链接 libc（用于 `getenv`）
3. **mcp.zig 修改**: 修改了依赖库的代码，应考虑将修改提交回上游或维护一个 fork

## 未来改进

1. 添加 Windows 和 macOS 支持
2. 考虑将 `mcp.zig` 的修改提交到上游 zig-0.16 分支
3. 等待 Zig 0.16 稳定后，使用更高级的 API（如果有的话）

## 验证

使用以下命令验证构建：

```bash
cd omniweb3-mcp
zig build
./zig-out/bin/omniweb3-mcp --help  # 验证程序可以运行
```

## Zig 版本

```bash
$ zig version
0.16.0-dev.2261+d6b3dd25a
```
