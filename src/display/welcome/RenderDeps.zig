const std = @import("std");
const sdl = @import("sdl");
const consts = @import("../consts.zig");
const Vertex = @import("../structs.zig").Vertex;
const Window = @import("../window.zig");
const Uploader = @import("../Uploader.zig");
const shader_loader = @import("../shader_loader.zig");
const Pipeline = @import("../Pipeline.zig");
const Error = @import("../errors.zig").Error;
const Self = @This();

window: *Window,
gpu: *sdl.Gpu,
pipeline: Pipeline,
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,

pub fn init(allocator: std.mem.Allocator, window: *Window, gpu: *sdl.Gpu) Error!Self {
    const vert_shader = try shader_loader.load(gpu, @embedFile("base.vert.spv"), "main", .vertex, 0, 0);
    const frag_shader = try shader_loader.load(gpu, @embedFile("welcome.frag.spv"), "main", .fragment, 0, 0);
    // todo: 把整个基础顶点数据提取成公共部分
    const vert_buffer_desc: sdl.c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = sdl.c.SDL_GPU_VERTEXINPUTRATE_VERTEX };
    const vert_attrs: [2]sdl.c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    const pipeline = try Pipeline.init(
        gpu,
        window.sdl_window,
        .{ .vert = vert_shader, .frag = frag_shader },
        .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vert_buffer_desc,
            .num_vertex_attributes = 2,
            .vertex_attributes = &vert_attrs,
        },
    );

    // 创建上传器
    var uploader = Uploader.init(allocator, gpu);
    defer uploader.deinit();

    // 上传顶点
    const verts = consts.base_verts;
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = try uploader.uploadBuffer(&verts_buffer_info, @ptrCast(&verts), verts_size);
    try uploader.submit();

    return Self{
        .window = window,
        .gpu = gpu,
        .pipeline = pipeline,
        .verts_buffer = verts_buffer,
        .verts_binding = sdl.c.SDL_GPUBufferBinding{ .buffer = verts_buffer, .offset = 0 },
    };
}

pub fn deinit(self: *Self) void {
    self.pipeline.deinit();
    self.gpu.releaseGPUBuffer(self.verts_buffer);
    self.* = undefined;
}
