const sdl = @import("sdl");
const Vertex = @import("../display/structs.zig").Vertex;
const Window = @import("../display/window.zig");
const shader_loader = @import("../shader.zig").loader;
const Pipeline = @import("../display/Pipeline.zig");
const Error = @import("../display/errors.zig").Error;
const Self = @This();

/// 纯色矩形背景（Button / TitleBar）的共享渲染管线。
///
/// 与 `BannerPipeline` 对称：所有矩形复用同一份着色器与图形管线。矩形是「全屏
/// quad + uniform 矩形区间」，不采样纹理，因此这里没有采样器；顶点、uniform 等
/// 状态由各矩形自身持有（见 `RectDrawer`）。
gpu: *const sdl.Gpu,
pipeline: Pipeline,

pub fn init(window: *const Window, gpu: *const sdl.Gpu) Error!Self {
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

    const vert_shader = try shader_loader.load(gpu, @embedFile("base.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    const frag_shader = try shader_loader.load(gpu, @embedFile("rect.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 1 });
    const pipeline = try Pipeline.init(gpu, window.sdl_window, .{ .vert = vert_shader, .frag = frag_shader }, vertex_input_state);

    return Self{
        .gpu = gpu,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.pipeline.deinit();
    self.* = undefined;
}

/// 在当前 render pass 内绑定共享图形管线。
pub fn bind(self: *Self, pass: *sdl.c.SDL_GPURenderPass) void {
    self.pipeline.bind(pass);
}

/// 绘制当前绑定管线的 6 个顶点（一次全屏 quad）。
pub fn draw(self: *Self) void {
    self.pipeline.draw();
}
