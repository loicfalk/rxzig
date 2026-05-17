const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libxev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    const rx_zig_module = b.addModule("rx", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag != .freestanding,
    });

    const rx_zig_lib = b.addLibrary(.{
        .name = "rx",
        .root_module = rx_zig_module,
        .linkage = .static,
    });

    rx_zig_lib.root_module.addImport("xev", libxev_dep.module("xev"));
    b.installArtifact(rx_zig_lib);

    // ============================================================
    // TEST
    // ============================================================
    const test_step = b.step("test", "Run unit tests");

    const test_files = [_][]const u8{
        "test/observable_test.zig",
        "test/observable_test.zig",
    };

    // Run inline tests from the library module itself.
    const lib_tests = b.addTest(.{
        .root_module = rx_zig_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    for (test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "rx", .module = rx_zig_module },
                },
            }),
        });
        const run = b.addRunArtifact(t);
        test_step.dependOn(&run.step);
    }

    // ============================================================
    // EXAMPLES
    // ============================================================
    const examples = [_]struct { name: []const u8, file: []const u8 }{
        .{ .name = "basic", .file = "examples/basic/main.zig" },
    };

    const examples_step = b.step("examples", "Build examples");

    // Create example executables
    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.file),
                .target = target,
                .imports = &.{
                    .{ .name = "rx", .module = rx_zig_module },
                    .{
                        .name = "xev",
                        .module = libxev_dep.module("xev"),
                    },
                },
            }),
        });

        exe.root_module.addImport("xev", libxev_dep.module("xev"));
        exe.root_module.addImport("rx", rx_zig_module);

        const install_exe = b.addInstallArtifact(exe, .{});
        examples_step.dependOn(&install_exe.step);

        const run_example = b.addRunArtifact(exe);
        run_example.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_example.addArgs(args);
        }
        const run_example_step = b.step("example-basic", "🚀 Running the basic example");
        run_example_step.dependOn(&run_example.step);
    }
}
