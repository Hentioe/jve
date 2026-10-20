const sdl = @import("sdl");
const Window = @import("../display/window.zig");
const shader_loader = @import("../shader.zig").loader;
const Pipeline = @import("BasePipeline.zig");
const structs = @import("structs.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

/// 横幅背景的共享渲染管线。
///
/// 与 `TextPipeline` 对称：所有横幅复用同一份片段着色器与图形管线。背景是
/// 「全屏 quad + uniform 带」，不采样纹理，因此这里没有采样器；顶点着色器由
/// 会话级 `pipeline_registry` 加载一次并共享，其余状态由各横幅自身持有。
gpu: *const sdl.Gpu,
pipeline: Pipeline,

pub fn init(window: *const Window, gpu: *const sdl.Gpu, vert_shader: *sdl.c.SDL_GPUShader) Error!Self {
    const frag_shader = try shader_loader.load(gpu, @embedFile("banner.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 1 });
    const pipeline = try Pipeline.initBorrowedVert(gpu, window.sdl_window, .{ .vert = vert_shader, .frag = frag_shader }, structs.vertex_input_state);

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
