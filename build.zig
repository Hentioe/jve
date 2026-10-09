const std = @import("std");
const Import = std.Build.Module.Import;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 共享使用的基础模块
    const shared_mod = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
    });
    const shared_import: Import = .{ .name = "shared", .module = shared_mod };

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

    // SDL 包装模块
    const sdl_wrapper_mod = b.addModule("sdl", .{
        .root_source_file = b.path("src/sdl.zig"),
        .target = target,
    });
    sdl_wrapper_mod.linkLibrary(sdl_lib); // 让 sdl_wrapper 链接到 sdl
    sdl_wrapper_mod.linkLibrary(sdl_test_lib); // 让 sdl_wrapper 链接到 sdl_test
    const sdl_wrapper_import: Import = .{ .name = "sdl", .module = sdl_wrapper_mod };

    // TOML 依赖
    const toml_dep = b.dependency("toml", .{});
    const toml_import: Import = .{ .name = "toml", .module = toml_dep.module("toml") };

    // 配置模块
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .imports = &.{toml_import},
    });
    const config_import: Import = .{ .name = "config", .module = config_mod };

    // VIPS 模块
    const vips_mod = b.addModule("vips", .{
        .root_source_file = b.path("src/vips.zig"),
        .target = target,
        .imports = &.{shared_import},
    });
    // 链接系统 vips
    vips_mod.linkSystemLibrary("vips", .{});
    const vips_import: Import = .{ .name = "vips", .module = vips_mod };

    const ort_mod = b.addModule("ort", .{
        .root_source_file = b.path("src/ort.zig"),
        .target = target,
    });
    // 链接系统 onnxruntime
    ort_mod.linkSystemLibrary("onnxruntime", .{});
    const ort_import: Import = .{ .name = "ort", .module = ort_mod };

    // AI 模块
    const ai_mod = b.addModule("ai", .{
        .root_source_file = b.path("src/ai.zig"),
        .target = target,
        .imports = &.{ shared_import, config_import, ort_import, vips_import },
    });
    const ai_import: Import = .{ .name = "ai", .module = ai_mod };

    const clap_dep = b.dependency("clap", .{});
    const clap_import: Import = .{ .name = "clap", .module = clap_dep.module("clap") };

    const sdl_shadercross_dep = b.dependency("SDL_shadercross", .{
        .target = target,
        .optimize = optimize,
        .link_system_sdl = false, // 已由外部提供 SDL，禁用系统回退
    });
    const sdl_shadercross_mod = sdl_shadercross_dep.module("SDL_shadercross");
    const sdl_shadercross_import: Import = .{ .name = "SDL_shadercross", .module = sdl_shadercross_mod };
    sdl_shadercross_mod.linkLibrary(sdl_lib); // 让 sdl_shadercross 链接到 sdl

    const root_mod = b.addModule("jve", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            shared_import,
            toml_import,
            config_import,
            vips_import,
            ort_import,
            ai_import,
            sdl_wrapper_import,
            sdl_shadercross_import,
        },
    });
    const root_import: Import = .{ .name = "jve", .module = root_mod };

    // 链接系统 glib（vips 依赖）
    root_mod.linkSystemLibrary("glib-2.0", .{});

    const exe = b.addExecutable(.{
        .name = "jve",
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
        .{ .file = "fog.frag.hlsl", .stage = .fragment },
        .{ .file = "checker.frag.hlsl", .stage = .fragment },
        .{ .file = "checker.vert.hlsl", .stage = .vertex },
        .{ .file = "checker.frag.hlsl", .stage = .fragment },
        .{ .file = "marker.frag.hlsl", .stage = .fragment },
        .{ .file = "marker.vert.hlsl", .stage = .vertex },
        .{ .file = "mask.frag.hlsl", .stage = .fragment },
        .{ .file = "onscreen.frag.hlsl", .stage = .fragment },
        .{ .file = "overflow.frag.hlsl", .stage = .fragment },
        .{ .file = "sharpen.frag.hlsl", .stage = .fragment },
        .{ .file = "welcome.frag.hlsl", .stage = .fragment },
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
