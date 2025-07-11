pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const mod = b.addModule("oopz", .{
        .root_source_file = b.path("src/oopz.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "oopz",
        .root_module = mod,
    });
    b.installArtifact(lib);

    // Docs
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    // Test
    const tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);

    // Steps
    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&docs.step);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

const std = @import("std");
