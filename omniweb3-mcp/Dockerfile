# syntax=docker/dockerfile:1.4
FROM debian:bookworm-slim AS build

# 安装依赖
RUN apt update && apt install -y curl xz-utils ca-certificates

# 下载 Zig 0.16.0-dev
WORKDIR /opt
RUN curl -L https://ziglang.org/builds/zig-x86_64-linux-0.16.0-dev.2261+d6b3dd25a.tar.xz | tar -xJ
ENV PATH="/opt/zig-x86_64-linux-0.16.0-dev.2261+d6b3dd25a:$PATH"

# 构建项目 - 使用 tmpfs 挂载解决 OverlayFS 兼容问题
WORKDIR /app
COPY . .
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/root/.cache \
    zig build -Doptimize=ReleaseFast \
    --cache-dir /tmp/zig-cache \
    --global-cache-dir /tmp/zig-cache

# 运行时镜像
FROM debian:bookworm-slim
RUN apt update && apt install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/zig-out/bin/omniweb3-mcp /app/omniweb3-mcp
ENV HOST=0.0.0.0
ENV PORT=8765
ENV MCP_WORKERS=4
EXPOSE 8765
CMD ["./omniweb3-mcp"]
