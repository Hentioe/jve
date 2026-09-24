const std = @import("std");
const Import = std.Build.Module.Import;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ort_mod = b.addModule("ort", .{
        .root_source_file = b.path("src/ort.zig"),
        .target = target,
    });
    const ort_import: Import = .{ .name = "ort", .module = ort_mod };

    const root_mod = b.addModule("imageviewer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{ort_import},
    });
    const root_import: Import = .{ .name = "imageviewer", .module = root_mod };

    const clap_dep = b.dependency("clap", .{});
    const clap_import: Import = .{ .name = "clap", .module = clap_dep.module("clap") };

    const exe = b.addExecutable(.{
        .name = "imageviewer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ root_import, clap_import, ort_import },
            .link_libc = true,
        }),
    });

    // 链接 vips
    exe.root_module.linkSystemLibrary("vips", .{});
    // 链接 glib（vips 依赖）
    exe.root_module.linkSystemLibrary("glib-2.0", .{});
    // 链接 SDL3_shadercross
    exe.root_module.linkSystemLibrary("SDL3_shadercross", .{});
    // 链接 onnxruntime
    exe.root_module.linkSystemLibrary("onnxruntime", .{});

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        //.preferred_linkage = .static,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
        //.system_include_path = null,
        //.system_framework_path = null,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    const sdl_test_lib = sdl_dep.artifact("SDL3_test");

    exe.linkLibrary(sdl_lib);
    exe.linkLibrary(sdl_test_lib);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = root_mod,
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
