const std = @import("std");
const Import = std.Build.Module.Import;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_dep_optimize = switch (optimize) {
        .Debug => .ReleaseFast, // 在 debug 模式，c 库始终 fast 编译
        else => optimize,
    };

    // 共享使用的基础模块
    const shared_mod = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
    });
    const shared_import: Import = .{ .name = "shared", .module = shared_mod };

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = c_dep_optimize,
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

    // libass
    const libass_mod = b.addModule("libass", .{
        .root_source_file = b.path("src/ass.zig"),
        .target = target,
    });
    libass_mod.linkSystemLibrary("libass", .{});
    const libass_import: Import = .{ .name = "ass", .module = libass_mod };

    // slang
    const slang_dep = b.dependency("slang", .{
        .target = target,
        .optimize = c_dep_optimize,
    });

    // slang_shim
    const slang_shim = b.addModule("slang_shim", .{
        .root_source_file = b.path("src/slang.zig"),
        .target = target,
        .imports = &.{shared_import},
        .link_libcpp = true,
        .link_libc = true,
    });
    slang_shim.addIncludePath(slang_dep.path("include"));
    slang_shim.addIncludePath(b.path("src/slang")); // 包含 shim.h
    slang_shim.addCSourceFile(.{ .file = b.path("src/slang/shim.cpp"), .flags = &.{"-std=c++20"} }); // 用 shim.cpp 简化接口
    slang_shim.linkLibrary(slang_dep.artifact("slang-compiler")); // 链接 slang-compiler
    slang_shim.linkLibrary(slang_dep.artifact("slang-glslang")); // 链接 slang-glslang
    const slang_import: Import = .{ .name = "slang", .module = slang_shim };

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
            slang_import,
            sdl_wrapper_import,
            libass_import,
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

    // -- Shader 编译 --
    // stage 由源文件中的 [shader("...")] 属性推断，目标格式由输出文件的 .spv 扩展名推断，故无需额外编译参数。
    const shaders = [_][]const u8{
        "base.frag.slang",
        "base.vert.slang",
        "background.vert.slang",
        "banner.frag.slang",
        "blur.frag.slang",
        "fog.frag.slang",
        "marker.frag.slang",
        "marker.vert.slang",
        "mask.frag.slang",
        "onscreen.frag.slang",
        "overflow.frag.slang",
        "rect.frag.slang",
        "sharpen.frag.slang",
        "text.frag.slang",
        "welcome.frag.slang",
        "diag.frag.slang",
        "checker_bg.frag.slang", // 经典背景
        "rainbow_bg.frag.slang", // 彩虹背景
    };

    const shaders_step = b.step("shaders", "Compile Slang shaders to SPIR-V");
    const update_shaders = b.addUpdateSourceFiles();

    for (shaders) |shader| {
        const src_path = b.pathJoin(&.{ "shaders", shader });
        const compile = b.addSystemCommand(&.{"slangc"});

        // 输入文件
        compile.addFileArg(b.path(src_path));
        compile.addArg("-o");

        // 输出文件名,例如 base.frag.slang -> base.frag.spv
        const spv_name = b.fmt("{s}.spv", .{shader[0 .. shader.len - ".slang".len]});

        // 添加 SPV 为输出文件，这一步让 Run Step 参与 Zig 的缓存系统
        // 源文件内容 + 命令行参数不变时，slangc 不会被再次调用
        const spv_cached = compile.addOutputFileArg(spv_name);

        // 添加到 root 的匿名导入
        root_mod.addAnonymousImport(spv_name, .{ .root_source_file = spv_cached });
    }

    shaders_step.dependOn(&update_shaders.step);

    // 让 `zig build` 默认就顺带编译 shader
    b.getInstallStep().dependOn(shaders_step);
}
