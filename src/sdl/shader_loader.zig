const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;

// todo: 两个 num 参数合并成一个结构体
pub fn loadHlslFile(
    allocator: std.mem.Allocator,
    device: *c.SDL_GPUDevice,
    file_name: [*:0]const u8,
    entrypoint: [*:0]const u8,
    stage: c.SDL_GPUShaderStage,
    num_samplers: u32,
    num_uniform_buffers: u32,
) Error!*c.SDL_GPUShader {
    // todo: 改为路径 join
    const file_path = try std.fmt.allocPrint(allocator, "src/shaders/{s}", .{file_name});
    defer allocator.free(file_path);
    // 检查文件是否可访问
    std.fs.cwd().access(file_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.log.err("Shader file not found: {s}", .{file_path});
        }

        return err;
    };
    // 正在加载着色器
    std.log.info("Loading shader: {s}", .{file_name});
    var file_size: usize = 0;
    const hlsl_source = c.SDL_LoadFile(@ptrCast(file_path), &file_size);
    if (hlsl_source == null) {
        h.printError();
        return Error.SdlLoadFileFailed;
    }
    defer c.SDL_free(hlsl_source);

    var hlsl_info = c.SDL_ShaderCross_HLSL_Info{
        .source = @ptrCast(hlsl_source),
        .entrypoint = entrypoint,
        .include_dir = null,
        .defines = null,
        .shader_stage = stage,
        .props = 0,
    };

    var spirv_size: usize = 0;
    const spirv_bytes = c.SDL_ShaderCross_CompileSPIRVFromHLSL(&hlsl_info, &spirv_size);
    if (spirv_bytes == null) {
        h.printError();
        return Error.SdlCompileShaderFailed;
    }
    defer c.SDL_free(spirv_bytes);

    var spirv_info = c.SDL_ShaderCross_SPIRV_Info{
        .bytecode = @ptrCast(spirv_bytes),
        .bytecode_size = spirv_size,
        .entrypoint = entrypoint,
        .shader_stage = stage,
        .props = 0,
    };

    const shader = c.SDL_ShaderCross_CompileGraphicsShaderFromSPIRV(
        device,
        &spirv_info,
        &.{ .num_samplers = num_samplers, .num_uniform_buffers = num_uniform_buffers },
        0,
    );
    if (shader == null) {
        h.printError();
        return Error.SdlCompileShaderFailed;
    }
    return shader.?;
}
