const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("myConverter", .{
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

    const exe = b.addExecutable(.{
        .name = "myConverter",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("png_parser", mod);
    exe.root_module.addImport("jpeg_buffer", jpeg);
    exe.root_module.addImport("ppm", ppm);

    exe.linkLibC();
    exe.linkSystemLibrary("z");
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_source_file = mod.root_source_file.?,
        .target = target,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_source_file = exe.root_module.root_source_file.?,
        .target = target,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
