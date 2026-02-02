const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies from build.zig.zon
    const mcp_dep = b.dependency("mcp", .{ .target = target, .optimize = optimize });
    const solana_client_dep = b.dependency("solana_client", .{ .target = target, .optimize = optimize });
    const solana_sdk_dep = b.dependency("solana_sdk", .{ .target = target, .optimize = optimize });
    const zabi_dep = b.dependency("zabi", .{ .target = target, .optimize = optimize });
    const httpz_dep = b.dependency("httpz", .{ .target = target, .optimize = optimize });

    // Main executable: Smart MCP with discovery tools + unified interfaces
    const exe = b.addExecutable(.{
        .name = "omniweb3-mcp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addImport("mcp", mcp_dep.module("mcp"));
    exe.root_module.addImport("solana_client", solana_client_dep.module("solana_client"));
    exe.root_module.addImport("solana_sdk", solana_sdk_dep.module("solana_sdk"));
    exe.root_module.addImport("zabi", zabi_dep.module("zabi"));
    exe.root_module.addImport("httpz", httpz_dep.module("httpz"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run omniweb3-mcp");
    run_step.dependOn(&run_cmd.step);

    // Test step (using main.zig tests)
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    tests.root_module.addImport("mcp", mcp_dep.module("mcp"));
    tests.root_module.addImport("solana_client", solana_client_dep.module("solana_client"));
    tests.root_module.addImport("solana_sdk", solana_sdk_dep.module("solana_sdk"));
    tests.root_module.addImport("zabi", zabi_dep.module("zabi"));
    tests.root_module.addImport("httpz", httpz_dep.module("httpz"));

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
