const std = @import("std");
const Import = std.Build.Module.Import;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const toml_dep = b.dependency("toml", .{});
    const toml_import: Import = .{ .name = "toml", .module = toml_dep.module("toml") };

    const ort_mod = b.addModule("ort", .{
        .root_source_file = b.path("src/ort.zig"),
        .target = target,
    });
    const ort_import: Import = .{ .name = "ort", .module = ort_mod };

    const clap_dep = b.dependency("clap", .{});
    const clap_import: Import = .{ .name = "clap", .module = clap_dep.module("clap") };

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

    const root_mod = b.addModule("imageviewer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{ toml_import, ort_import },
    });
    const root_import: Import = .{ .name = "imageviewer", .module = root_mod };
    // 链接 sdl
    root_mod.linkLibrary(sdl_lib);
    root_mod.linkLibrary(sdl_test_lib);
    // 链接 vips
    root_mod.linkSystemLibrary("vips", .{});
    // 链接 glib（vips 依赖）
    root_mod.linkSystemLibrary("glib-2.0", .{});
    // 链接 SDL3_shadercross
    root_mod.linkSystemLibrary("SDL3_shadercross", .{});
    // 链接 onnxruntime
    root_mod.linkSystemLibrary("onnxruntime", .{});

    const exe = b.addExecutable(.{
        .name = "imageviewer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ root_import, clap_import },
            .link_libc = true,
        }),
    });

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

    // --- Shader 编译 ---
    const ShaderStage = enum { vertex, fragment };
    const ShaderEntry = struct { file: []const u8, stage: ShaderStage };

    const shaders = [_]ShaderEntry{
        .{ .file = "base.frag.hlsl", .stage = .fragment },
        .{ .file = "base.vert.hlsl", .stage = .vertex },
        .{ .file = "blur.frag.hlsl", .stage = .fragment },
        .{ .file = "busy_fog.frag.hlsl", .stage = .fragment },
        .{ .file = "checker.frag.hlsl", .stage = .fragment },
        .{ .file = "checker.vert.hlsl", .stage = .vertex },
        .{ .file = "checker.frag.hlsl", .stage = .fragment },
        .{ .file = "marker.frag.hlsl", .stage = .fragment },
        .{ .file = "marker.vert.hlsl", .stage = .vertex },
        .{ .file = "mask.frag.hlsl", .stage = .fragment },
        .{ .file = "onscreen.frag.hlsl", .stage = .fragment },
        .{ .file = "sharpen.frag.hlsl", .stage = .fragment },
    };

    const shaders_step = b.step("shaders", "Compile HLSL shaders to SPIR-V");
    const update_shaders = b.addUpdateSourceFiles();

    for (shaders) |shader| {
        const src_path = b.pathJoin(&.{ "src", "shaders", shader.file });
        const compile = b.addSystemCommand(&.{"shadercross"}); // 确保存行在 shadercross 命令

        // 输入文件
        compile.addFileArg(b.path(src_path));
        // 其它参数
        compile.addArgs(&.{ "-s", "HLSL", "-d", "SPIRV", "-t", @tagName(shader.stage), "-e", "main" });
        compile.addArg("-o");

        // 输出文件名,例如 base.frag.hlsl -> base.frag.spv
        const spv_name = b.fmt("{s}.spv", .{shader.file[0 .. shader.file.len - ".hlsl".len]});

        // 添加 SPV 为输出文件，这一步让 Run Step 参与 Zig 的缓存系统
        // 源文件内容 + 命令行参数不变时，shadercross 不会被再次调用
        const spv_cached = compile.addOutputFileArg(spv_name);

        // 添加到 root 的匿名导入
        root_mod.addAnonymousImport(spv_name, .{ .root_source_file = spv_cached });
    }

    shaders_step.dependOn(&update_shaders.step);

    // 让 `zig build` 默认就顺带编译 shader
    b.getInstallStep().dependOn(shaders_step);
}
