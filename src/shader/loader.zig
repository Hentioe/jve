const std = @import("std");
const sdl = @import("sdl");
const slang = @import("slang");
const Error = @import("errors.zig").Error;

const Stage = enum(c_uint) {
    vertex = sdl.c.SDL_GPU_SHADERSTAGE_VERTEX,
    fragment = sdl.c.SDL_GPU_SHADERSTAGE_FRAGMENT,
};

const ShaderOptions = struct { samplers: u32, buffers: u32 };

pub fn loadSlangFile(
    allocator: std.mem.Allocator,
    gpu: *const sdl.Gpu,
    file_path: []const u8,
    entrypoint: []const u8,
    stage: Stage,
    options: ShaderOptions,
) Error!*sdl.c.SDL_GPUShader {
    // 正在加载着色器
    std.log.info("Loading shader: {s}", .{file_path});
    // 检查文件是否可访问
    try std.Io.Dir.cwd().access(file_path, .{});
    const file = try std.Io.Dir.cwd().openFile(file_path, .{});
    defer file.close();
    const stat = try file.stat();
    const source = std.Io.Dir.cwd().readFileAllocOptions(
        allocator,
        file_path,
        stat.size,
        null,
        .of(u8),
        0,
    ) catch return Error.ShaderReadFailed;
    defer allocator.free(source);

    var compiled = try slang.compileToSpirv(allocator, file_path, source, .{ .entry = entrypoint });
    defer compiled.deinit();

    const entrypoint_z = try allocator.dupeSentinel(u8, entrypoint, 0);
    defer allocator.free(entrypoint_z);

    return load(gpu, compiled.bytes(), entrypoint_z, stage, options);
}

pub fn load(
    gpu: *const sdl.Gpu,
    bytes: []const u8,
    entrypoint: [*:0]const u8,
    stage: Stage,
    options: ShaderOptions,
) Error!*sdl.c.SDL_GPUShader {
    const create_info = sdl.c.SDL_GPUShaderCreateInfo{
        .code = bytes.ptr,
        .code_size = bytes.len,
        .entrypoint = entrypoint,
        .format = sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = @backingInt(stage),
        .num_samplers = options.samplers,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = options.buffers,
        .props = 0,
    };

    return try gpu.createGPUShader(&create_info);
}
