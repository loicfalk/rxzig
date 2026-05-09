const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libxev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    const rx_zig_module = b.addModule("rx_zig", .{
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
