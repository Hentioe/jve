const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;

const Stage = enum(c_uint) {
    vertex = c.SDL_GPU_SHADERSTAGE_VERTEX,
    fragment = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
};

// todo: 两个 num 参数合并成一个结构体
pub fn loadHlslFile(
    allocator: std.mem.Allocator,
    device: *c.SDL_GPUDevice,
    file_path: []const u8,
    entrypoint: [*:0]const u8,
    stage: Stage,
    num_samplers: u32,
    num_uniform_buffers: u32,
) Error!*c.SDL_GPUShader {
    // todo: 改为路径 join
    const input_path = try std.fmt.allocPrintSentinel(allocator, "{s}", .{file_path}, 0);
    defer allocator.free(input_path);
    // 检查文件是否可访问
    std.fs.cwd().access(input_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.log.err("Shader file not found: {s}", .{input_path});
        }

        return err;
    };
    // 正在加载着色器
    std.log.info("Loading shader: {s}", .{input_path});
    var file_size: usize = 0;
    const hlsl_source = try h.check(c.SDL_LoadFile(@ptrCast(input_path), &file_size));
    defer c.SDL_free(hlsl_source);

    var hlsl_info = c.SDL_ShaderCross_HLSL_Info{
        .source = @ptrCast(hlsl_source),
        .entrypoint = entrypoint,
        .include_dir = null,
        .defines = null,
        .shader_stage = @intFromEnum(stage),
        .props = 0,
    };

    var spirv_size: usize = 0;
    const spirv_bytes = try h.check(c.SDL_ShaderCross_CompileSPIRVFromHLSL(&hlsl_info, &spirv_size));
    defer c.SDL_free(spirv_bytes);

    var spirv_info = c.SDL_ShaderCross_SPIRV_Info{
        .bytecode = @ptrCast(spirv_bytes),
        .bytecode_size = spirv_size,
        .entrypoint = entrypoint,
        .shader_stage = @intFromEnum(stage),
        .props = 0,
    };

    const shader = try h.check(c.SDL_ShaderCross_CompileGraphicsShaderFromSPIRV(
        device,
        &spirv_info,
        &.{ .num_samplers = num_samplers, .num_uniform_buffers = num_uniform_buffers },
        0,
    ));
    return shader;
}

pub fn load(
    device: *c.SDL_GPUDevice,
    bytes: []const u8,
    entrypoint: [*:0]const u8,
    stage: Stage,
    num_samplers: u32,
    num_uniform_buffers: u32,
) Error!*c.SDL_GPUShader {
    const create_info = c.SDL_GPUShaderCreateInfo{
        .code = bytes.ptr,
        .code_size = bytes.len,
        .entrypoint = entrypoint,
        .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = @intFromEnum(stage),
        .num_samplers = num_samplers,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = num_uniform_buffers,
    };

    return try h.check(c.SDL_CreateGPUShader(device, &create_info));
}
