FROM debian:bookworm-slim AS build
RUN apt update && apt install -y curl xz-utils
WORKDIR /opt
RUN curl -L https://ziglang.org/builds/zig-linux-x86_64-0.16.0-dev.2261+d6b3dd25a.tar.xz \
  | tar -xJ
ENV PATH="/opt/zig-linux-x86_64-0.16.0-dev.2261+d6b3dd25a:$PATH"
WORKDIR /app
COPY . .
RUN zig build -Doptimize=ReleaseFast

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/zig-out/bin/omniweb3-mcp /app/omniweb3-mcp
ENV HOST=0.0.0.0
ENV PORT=8765
ENV MCP_WORKERS=4
EXPOSE 8765
CMD ["./omniweb3-mcp"]
