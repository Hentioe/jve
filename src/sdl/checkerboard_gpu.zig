const c = @import("c.zig").c;
const shader_loader = @import("shader_loader.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Self = @This();

pipeline: *c.SDL_GPUGraphicsPipeline,

pub fn init(device: *c.SDL_GPUDevice, window: *Window) Error!Self {
    // 构造棋盘格管线
    const checker_vert_shader = try shader_loader.loadAndCompileHLSL(device, "checker_vert.hlsl", "main", c.SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    const checker_frag_shader = try shader_loader.loadAndCompileHLSL(device, "checker_frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    const checker_color_target_desc: c.SDL_GPUColorTargetDescription = .{ .format = c.SDL_GetGPUSwapchainTextureFormat(device, window.sdl_window) };
    const checker_pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = checker_vert_shader, // 编译好的顶点着色器
        .fragment_shader = checker_frag_shader, // 编译好的片段着色器
        .vertex_input_state = .{},
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &checker_color_target_desc },
    };
    return Self{
        .pipeline = c.SDL_CreateGPUGraphicsPipeline(device, &checker_pipeline_info) orelse unreachable,
    };
}

pub fn draw(self: *const Self, render_pass: ?*c.SDL_GPURenderPass) void {
    // 切换到棋盘格管线
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    // 绘制 3 个顶点覆盖整个屏幕
    c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
}

pub fn deinit(_: *const Self) void {
    // 暂时为空
}
