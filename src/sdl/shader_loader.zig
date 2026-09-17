const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;

pub fn loadAndCompileHLSL(
    device: *c.SDL_GPUDevice,
    file_name: [*:0]const u8,
    entrypoint: [*:0]const u8,
    stage: c.SDL_GPUShaderStage,
    num_samplers: u32,
    num_uniform_buffers: u32,
) Error!?*c.SDL_GPUShader {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const file_path = try std.fmt.allocPrint(allocator, "src/shaders/{s}", .{file_name});
    defer allocator.free(file_path);
    std.debug.print("Shader: {s}\n", .{file_name});
    var file_size: usize = 0;
    // todo: 处理加载错误
    const hlsl_source = c.SDL_LoadFile(@ptrCast(file_path), &file_size);
    const hlsl_source_ptr: [*c]const u8 = @ptrCast(hlsl_source);

    var hlsl_info = c.SDL_ShaderCross_HLSL_Info{
        .source = hlsl_source_ptr,
        .entrypoint = entrypoint,
        .include_dir = null,
        .defines = null,
        .shader_stage = stage,
        .props = 0,
    };

    var spirv_size: usize = 0;
    // todo: 处理编译错误
    const spirv_bytes = c.SDL_ShaderCross_CompileSPIRVFromHLSL(&hlsl_info, &spirv_size);

    const spirv_bytes_ptr: [*c]const u8 = @ptrCast(spirv_bytes);
    c.SDL_free(hlsl_source);

    var spirv_info = c.SDL_ShaderCross_SPIRV_Info{
        .bytecode = spirv_bytes_ptr,
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
        helper.printSdlError();
        return Error.SdlCompileShaderFailed;
    }
    c.SDL_free(spirv_bytes);
    return shader;
}
