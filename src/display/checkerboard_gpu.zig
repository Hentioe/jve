const c = @import("sdl").c;
const shader_loader = @import("shader_loader.zig");
const Error = @import("errors.zig").Error;
const Gpu = @import("sdl").Gpu;
const Window = @import("window.zig");
const Self = @This();

gpu: *Gpu,
pipeline: *c.SDL_GPUGraphicsPipeline,
vert_shader: *c.SDL_GPUShader,
frag_shader: *c.SDL_GPUShader,
render_pass: ?*c.SDL_GPURenderPass = null,

pub fn init(gpu: *Gpu, window: *Window) Error!Self {
    // 构造棋盘格管线
    const vert_shader = try shader_loader.load(gpu, @embedFile("checker.vert.spv"), "main", .vertex, 0, 0);
    const frag_shader = try shader_loader.load(gpu, @embedFile("checker.frag.spv"), "main", .fragment, 0, 0);
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{ .format = gpu.getGPUSwapchainTextureFormat(window.sdl_window) };
    const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert_shader, // 编译好的顶点着色器
        .fragment_shader = frag_shader, // 编译好的片段着色器
        .vertex_input_state = .{},
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &color_target_desc },
    };
    return Self{
        .gpu = gpu,
        .pipeline = try gpu.createGPUGraphicsPipeline(&pipeline_info),
        .vert_shader = vert_shader,
        .frag_shader = frag_shader,
    };
}

pub fn deinit(self: *Self) void {
    self.gpu.releaseGPUGraphicsPipeline(self.pipeline);
    self.gpu.releaseGPUShader(self.vert_shader);
    self.gpu.releaseGPUShader(self.frag_shader);
    self.* = undefined;
}

pub fn bind(self: *Self, render_pass: *c.SDL_GPURenderPass) void {
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    self.render_pass = render_pass;
}

pub fn draw(self: *const Self) void {
    // 绘制 3 个顶点覆盖整个屏幕
    c.SDL_DrawGPUPrimitives(self.render_pass, 3, 1, 0, 0);
}
