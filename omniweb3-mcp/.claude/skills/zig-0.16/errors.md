# Zig 0.16 错误记录（待整理）

> 这个文件用于快速记录开发中遇到的 Zig 0.16 错误和解决方案
> 定期整理后合并到 SKILL.md，然后清空此文件

---

<!-- 在下方添加新的错误记录 -->

## 2026-01-28 - httpz posix_compat.zig 和 mcp.zig 不支持 macOS

**错误信息：**
```
posix_compat.zig:102:35: error: posix_compat.socket only implemented for Linux
posix_compat.zig:118:35: error: posix_compat.bind only implemented for Linux
posix_compat.zig:137:35: error: posix_compat.listen only implemented for Linux
posix_compat.zig:214:35: error: posix_compat.write only implemented for Linux
posix_compat.zig:299:5: error: kqueue not supported on this platform
posix_compat.zig:303:5: error: kevent not supported on this platform
deps/mcp.zig/src/transport/transport.zig:24:9: error: Unsupported OS
```

**旧代码（httpz posix_compat.zig）：**
```zig
pub fn socket(domain: u32, socket_type: u32, protocol: u32) SocketError!socket_t {
    if (builtin.os.tag != .linux) @compileError("posix_compat.socket only implemented for Linux");
    // Linux only implementation...
}

pub fn kqueue() UnexpectedError!fd_t {
    @compileError("kqueue not supported on this platform");
}
```

**旧代码（mcp.zig transport.zig）：**
```zig
fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) !void {
    if (builtin.os.tag == .linux) {
        // Linux implementation
    } else {
        @compileError("Unsupported OS");
    }
}
```

**修复代码：**
```zig
// httpz posix_compat.zig - 添加 errno helper
inline fn getErrno(rc: anytype) std.posix.E {
    if (builtin.os.tag == .macos) {
        _ = rc;
        return @enumFromInt(std.c._errno().*);
    }
    return .SUCCESS;
}

// 支持 macOS 的 socket 函数
pub fn socket(domain: u32, socket_type: u32, protocol: u32) SocketError!socket_t {
    if (builtin.os.tag == .linux) {
        // Linux implementation with linux.*
    } else if (builtin.os.tag == .macos) {
        const rc = std.c.socket(@intCast(domain), @intCast(socket_type), @intCast(protocol));
        if (rc < 0) {
            const err = getErrno(rc);
            return switch (err) {
                .ACCES => error.AccessDenied,
                // ... other error mappings
                else => std.posix.unexpectedErrno(err),
            };
        }
        return @intCast(rc);
    } else {
        @compileError("posix_compat.socket only implemented for Linux and macOS");
    }
}

// 支持 macOS 的 kqueue（macOS 使用 kqueue 而不是 epoll）
pub fn kqueue() UnexpectedError!fd_t {
    if (builtin.os.tag == .macos) {
        const rc = std.c.kqueue();
        if (rc < 0) {
            const err = getErrno(rc);
            return std.posix.unexpectedErrno(err);
        }
        return @intCast(rc);
    } else {
        @compileError("kqueue only supported on macOS");
    }
}

// mcp.zig transport.zig - 支持 macOS
fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) !void {
    if (builtin.os.tag == .linux) {
        // Linux implementation
    } else if (builtin.os.tag == .macos) {
        var index: usize = 0;
        while (index < bytes.len) {
            const written_raw = std.c.write(fd, bytes[index..].ptr, bytes[index..].len);
            if (written_raw < 0) return error.WriteError;
            const written: usize = @intCast(written_raw);
            if (written == 0) return error.WriteError;
            index += written;
        }
    }
}

fn readFromFd(fd: std.posix.fd_t, buffer: []u8) !usize {
    if (builtin.os.tag == .linux) {
        // Linux implementation
    } else if (builtin.os.tag == .macos) {
        const result = std.c.read(fd, buffer.ptr, buffer.len);
        if (result < 0) return error.ReadError;
        return @intCast(result);
    }
}
```

**说明：**
- Zig 0.16 的 `std.posix` 模块移除了很多高层次的 wrapper 函数
- 需要直接使用 `std.c.*` 系统调用来支持 macOS
- macOS 上获取 errno 使用 `std.c._errno().*` 而不是 `std.c.getErrno`
- macOS 使用 kqueue/kevent 而不是 epoll（Linux 专用）
- 所有网络函数（socket, bind, listen, accept, connect, write, writev 等）都需要为 macOS 添加 `std.c.*` 实现
- 需要为每个系统调用检查返回值 (< 0 表示错误) 并映射错误码

**注意事项：**
- macOS 的 accept() 不支持 flags 参数，需要单独处理
- 不要在 macOS 分支中使用 `_ = flags` 来 discard 参数，这会导致"pointless discard"错误
- 确保所有错误码映射正确（ACCES vs ACCESS 等）
- timespec 类型使用 `std.posix.timespec`

**参考：**
- Zig 0.16 std.c documentation
- deps/http.zig/src/posix_compat.zig
- deps/mcp.zig/src/transport/transport.zig

---
