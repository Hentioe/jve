const std = @import("std");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const consts = @import("../consts.zig");
const Vertex = @import("../structs.zig").Vertex;
const Window = @import("../window.zig");
const Uploader = @import("../Uploader.zig");
const shader_loader = @import("../shader_loader.zig");
const Pipeline = @import("../Pipeline.zig");
const Drawable = @import("../../ui/Drawable.zig");
const Error = @import("../errors.zig").Error;
const Self = @This();

allocator: Allocator,
window: *const Window,
gpu: *const sdl.Gpu,
pipeline: Pipeline,
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
drawables: []Drawable,

pub fn init(allocator: Allocator, window: *const Window, gpu: *const sdl.Gpu, drawables: []Drawable) Error!Self {
    const vert_buffer_desc: sdl.c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = sdl.c.SDL_GPU_VERTEXINPUTRATE_VERTEX };
    const vert_attrs: [2]sdl.c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    const vertex_input_state: sdl.c.SDL_GPUVertexInputState = .{
        .num_vertex_buffers = 1,
        .vertex_buffer_descriptions = &vert_buffer_desc,
        .num_vertex_attributes = 2,
        .vertex_attributes = &vert_attrs,
    };

    // 全屏日食管线
    const vert_shader = try shader_loader.load(gpu, @embedFile("base.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    const frag_shader = try shader_loader.load(gpu, @embedFile("welcome.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 0 });
    const pipeline = try Pipeline.init(gpu, window.sdl_window, .{ .vert = vert_shader, .frag = frag_shader }, vertex_input_state);

    // 创建上传器
    var uploader = Uploader.init(allocator, gpu);
    defer uploader.deinit();

    // 上传全屏顶点
    const verts = consts.base_verts;
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = try uploader.uploadBuffer(&verts_buffer_info, @ptrCast(&verts), verts_size);

    try uploader.submit();

    return Self{
        .allocator = allocator,
        .window = window,
        .gpu = gpu,
        .pipeline = pipeline,
        .verts_buffer = verts_buffer,
        .verts_binding = sdl.c.SDL_GPUBufferBinding{ .buffer = verts_buffer, .offset = 0 },
        .drawables = drawables,
    };
}

pub fn deinit(self: *Self) void {
    self.pipeline.deinit();
    self.gpu.releaseGPUBuffer(self.verts_buffer);
    self.* = undefined;
}
