const std = @import("std");
const Translator = @import("translate_c").Translator;
const Import = std.Build.Module.Import;

const SlangMode = enum {
    /// 使用内置 Slang 依赖，生成 libslang.so，主程序保留纯 Zig 调用层。
    builtin_dynamic,
    /// 使用内置 Slang 依赖，把 Slang、shim 和 libc++ 全部静态链进主程序。
    builtin_static,
    /// 使用系统 slang，把 shim 和 libc++ 链进主程序。
    system,
};
const VipsMode = enum {
    // 使用内置 libvips 依赖，生成 libvips.so。
    builtin_dynamic,
    // 使用系统 libvips。
    system,
};

pub fn build(b: *std.Build) void {
    const slang_mode: SlangMode = b.option(
        SlangMode,
        "slang-mode",
        "Slang integration mode: builtin_dynamic, builtin_static, or system",
    ) orelse .system;
    const vips_mode: VipsMode = b.option(
        VipsMode,
        "vips-mode",
        "libvips integration mode: builtin_dynamic or system",
    ) orelse .system;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // 针对 C 库的编译优化
    const c_dep_optimize = switch (optimize) {
        .Debug => .fast, // 在 debug 模式，c 库始终 fast 编译
        else => optimize,
    };

    // C 翻译器（0.17 要求）
    const translate_c = b.dependency("translate_c", .{});

    // 全局可用的共享模块
    const shared_mod = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
    });
    const shared_import: Import = .{ .name = "shared", .module = shared_mod };

    // clap 依赖
    const clap_dep = b.dependency("clap", .{});
    const clap_mod = clap_dep.module("clap");

    // TOML 依赖
    const toml_dep = b.dependency("toml", .{});
    const toml_mod = toml_dep.module("toml");

    // XDG 标准目录解析
    const xdg_mod = b.addModule("xdg", .{
        .root_source_file = b.path("src/xdg.zig"),
        .target = target,
    });

    // SDL 相关模块
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
    const sdl_c_translator: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/sdl/c.h"),
        .target = target,
        .optimize = optimize,
    });
    sdl_c_translator.linkLibrary(sdl_lib);
    sdl_c_translator.linkLibrary(sdl_test_lib);
    const sdl_mod = b.addModule("sdl", .{
        .root_source_file = b.path("src/sdl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sdl_c", .module = sdl_c_translator.mod },
        },
    });

    // libass 相关模块
    const ass_c_translator: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/ass/c.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{.{ .name = "libass" }},
    });
    const ass_c_mod = ass_c_translator.mod;
    const ass_mod = b.addModule("ass", .{
        .root_source_file = b.path("src/ass.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "ass_c", .module = ass_c_mod },
        },
    });

    // libvips 相关模块
    const vips_mod = b.addModule("vips", .{
        .root_source_file = b.path("src/vips.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            shared_import,
        },
    });
    if (vips_mode == .builtin_dynamic) {
        const vips_dep = b.dependency("libvips", .{
            .target = target,
            .optimize = c_dep_optimize,
            .shared = true,
            // 可选：关闭不需要的依赖，例如：
            // .heif = false,
            // .jxl = false,
            // .magick = false,
        });
        const vips_c_mod = vips_dep.module("vips");
        vips_mod.addImport("vips_c", vips_c_mod);
        const libvips = vips_dep.artifact("vips");
        vips_mod.linkLibrary(libvips);
        b.installArtifact(libvips);
    } else {
        const vips_c_translator: Translator = .init(translate_c, .{
            .c_source_file = b.path("src/vips/c.h"),
            .target = target,
            .optimize = optimize,
            .link_system_libs = &.{.{ .name = "vips" }},
        });
        const vips_c_mod = vips_c_translator.mod;
        vips_mod.addImport("vips_c", vips_c_mod);
    }
    // ORT 相关模块
    const ort_c_translator: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/ort/c.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{.{ .name = "onnxruntime" }},
    });
    const ort_mod = b.addModule("ort", .{
        .root_source_file = b.path("src/ort.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "ort_c", .module = ort_c_translator.mod },
        },
    });

    // slang 相关模块
    const slang_c_translator: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/slang/shim.h"),
        .target = target,
        .optimize = optimize,
    });
    const slang_c_mod = slang_c_translator.mod;
    // 应用侧只保留 Zig 包装层。动态模式下它通过 C ABI 调用 libslang.so；
    // 静态/系统模式下，shim.cpp 也会编进这个模块。
    const slang_mod = b.addModule("slang", .{
        .root_source_file = b.path("src/slang.zig"),
        .target = target,
        .link_libc = true,
        .link_libcpp = slang_mode != .builtin_dynamic,
        .imports = &.{
            shared_import,
            .{ .name = "slang_c", .module = slang_c_mod },
        },
    });
    const shim_cpp_source: std.Build.Module.CSourceFile = .{
        .file = b.path("src/slang/shim.cpp"),
        .flags = &.{"-std=c++20"},
    };

    switch (slang_mode) {
        .builtin_dynamic => {
            const slang_dep = b.dependency("slang", .{
                .target = target,
                .optimize = optimize,
                .pic = true,
            });

            // 动态库只包含 C++ shim 与 Slang 静态库。保持纯 C++ 根模块可以让
            // Zig 使用 LLD，并避免把 Zig 的 ABI/分配器暴露到 .so 边界。
            const slang_cpp_mod = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .pic = true,
                .link_libc = true,
                .link_libcpp = true,
            });
            slang_cpp_mod.addIncludePath(b.path("src/slang"));
            slang_cpp_mod.addIncludePath(slang_dep.path("include"));
            // shim.cpp 需要这个宏才会把 glslang 以进程内方式安装到 global session。
            slang_cpp_mod.addCMacro("EMBEDDED_GLSLANG", "1");
            slang_cpp_mod.addCSourceFile(shim_cpp_source);
            slang_cpp_mod.linkLibrary(slang_dep.artifact("slang-compiler"));
            slang_cpp_mod.linkLibrary(slang_dep.artifact("slang-glslang"));

            const slang_lib = b.addLibrary(.{
                .name = "slang",
                .linkage = .dynamic,
                .root_module = slang_cpp_mod,
            });
            slang_mod.linkLibrary(slang_lib);
            b.installArtifact(slang_lib);
        },
        .builtin_static => {
            const slang_dep = b.dependency("slang", .{
                .target = target,
                .optimize = optimize,
                .pic = false,
            });

            // 原始集成方式：Slang、glslang、shim.cpp 和 libc++ 共用同一份
            // 进程内 C++ 运行时，全部静态链进可执行文件。
            slang_mod.addIncludePath(b.path("src/slang"));
            slang_mod.addIncludePath(slang_dep.path("include"));
            slang_mod.addCMacro("EMBEDDED_GLSLANG", "1");
            slang_mod.addCSourceFile(shim_cpp_source);
            slang_mod.linkLibrary(slang_dep.artifact("slang-compiler"));
            slang_mod.linkLibrary(slang_dep.artifact("slang-glslang"));
        },
        .system => {
            // 系统 slang 只提供标准 Slang API；自定义 slang_shim_* 实现
            // 仍由本项目编译，并链接系统 slang 和 Zig 的静态 libc++。
            slang_mod.addIncludePath(b.path("src/slang"));
            slang_mod.addCSourceFile(shim_cpp_source);
            slang_mod.linkSystemLibrary("slang", .{});
        },
    }

    const root_mod = b.addModule("jve", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            shared_import,
            .{ .name = "xdg", .module = xdg_mod },
            .{ .name = "toml", .module = toml_mod },
            .{ .name = "ass", .module = ass_mod },
            .{ .name = "vips", .module = vips_mod },
            .{ .name = "sdl", .module = sdl_mod },
            .{ .name = "ort", .module = ort_mod },
            .{ .name = "slang", .module = slang_mod },
        },
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "jve", .module = root_mod },
        },
        .link_libc = true,
    });
    // 安装后的目录布局是 bin/ + lib/，让可执行文件在没有 Zig 缓存路径时也能找到 libslang.so/libvips.so。
    if ((slang_mode == .builtin_dynamic or vips_mode == .builtin_dynamic) and target.result.os.tag == .linux) {
        exe_mod.addRPathSpecial("$ORIGIN/../lib");
    }
    const exe = b.addExecutable(.{
        .name = "jve",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

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
        "black_bg.frag.slang", // 纯黑背景
        "checker_bg.frag.slang", // 经典背景
        "rainbow_bg.frag.slang", // 彩虹背景
        "tiles_bg.frag.slang", // 砖块背景
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
