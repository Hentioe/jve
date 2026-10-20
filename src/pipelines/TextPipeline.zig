const sdl = @import("sdl");
const Window = @import("../display/window.zig");
const shader_loader = @import("../shader.zig").loader;
const Pipeline = @import("BasePipeline.zig");
const structs = @import("structs.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

/// 文字/图标组件的共享渲染管线。
///
/// 所有组件复用同一份片段着色器、图形管线与采样器；顶点着色器由会话级
/// `pipeline_registry` 加载一次并共享。顶点数据、纹理与状态 uniform 由各组件
/// 自行持有（见 `ui.Drawer`），因此这个管线本身不携带任何组件状态。
gpu: *const sdl.Gpu,
pipeline: Pipeline,
sampler: *sdl.c.SDL_GPUSampler,

pub fn init(window: *const Window, gpu: *const sdl.Gpu, vert_shader: *sdl.c.SDL_GPUShader) Error!Self {
    // 文字管线
    const frag_shader = try shader_loader.load(gpu, @embedFile("text.frag.spv"), "main", .fragment, .{ .samplers = 1, .buffers = 1 });
    var pipeline = try Pipeline.initBorrowedVert(gpu, window.sdl_window, .{ .vert = vert_shader, .frag = frag_shader }, structs.vertex_input_state);
    errdefer pipeline.deinit();

    // 文字纹理采样器（所有组件共用）
    const sampler_desc = sdl.c.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl.c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = sdl.c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = sdl.c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    };
    const sampler = try gpu.createGPUSampler(&sampler_desc);

    return Self{
        .gpu = gpu,
        .pipeline = pipeline,
        .sampler = sampler,
    };
}

pub fn deinit(self: *Self) void {
    self.pipeline.deinit();
    self.gpu.releaseGPUSampler(self.sampler);
    self.* = undefined;
}

/// 在当前 render pass 内绑定共享图形管线。
pub fn bind(self: *Self, pass: *sdl.c.SDL_GPURenderPass) void {
    self.pipeline.bind(pass);
}

/// 绘制当前绑定管线的 6 个顶点（一次 quad）。
pub fn draw(self: *Self) void {
    self.pipeline.draw();
}
