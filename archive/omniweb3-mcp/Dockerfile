FROM debian:bookworm-slim

# 安装运行时依赖
RUN apt update && apt install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 直接复制预编译的二进制文件
COPY zig-out/bin/omniweb3-mcp /app/omniweb3-mcp

# 复制 IDL 注册表（动态工具需要）
COPY idl_registry /app/idl_registry

# 确保可执行
RUN chmod +x /app/omniweb3-mcp

ENV HOST=0.0.0.0
ENV PORT=8765
ENV MCP_WORKERS=4

EXPOSE 8765

CMD ["./omniweb3-mcp"]
