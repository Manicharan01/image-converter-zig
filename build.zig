const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const png = b.addModule("myConverter", .{
        .root_source_file = b.path("src/png_parser/root.zig"),
        .target = target,
    });

    const jpeg = b.addModule("myConverter", .{
        .root_source_file = b.path("src/jpeg_buffer/root.zig"),
        .target = target,
    });

    const ppm = b.addModule("myConverter", .{
        .root_source_file = b.path("src/ppm/root.zig"),
        .target = target,
    });

    const webp = b.addModule("myConverter", .{
        .root_source_file = b.path("src/webp/root.zig"),
        .target = target,
    });

    const viewer = b.addModule("myConverter", .{
        .root_source_file = b.path("src/viewer/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "myConverter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "png_parser", .module = png },
                .{ .name = "jpeg_buffer", .module = jpeg },
                .{ .name = "ppm", .module = ppm },
                .{ .name = "webp", .module = webp },
                .{ .name = "viewer", .module = viewer },
            },
        }),
    });

    exe.linkLibC();
    exe.linkSystemLibrary("z");
    exe.linkSystemLibrary("SDL2");
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = png,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
