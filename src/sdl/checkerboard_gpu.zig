const std = @import("std");
const c = @import("c.zig").c;
const shader_loader = @import("shader_loader.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Self = @This();

pipeline: *c.SDL_GPUGraphicsPipeline,

pub fn init(device: *c.SDL_GPUDevice, window: *Window) Error!Self {
    // 构造棋盘格管线
    const vert_shader = try shader_loader.load(device, @embedFile("checker.vert.spv"), "main", .vertex, 0, 0);
    const frag_shader = try shader_loader.load(device, @embedFile("checker.frag.spv"), "main", .fragment, 0, 0);
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{ .format = c.SDL_GetGPUSwapchainTextureFormat(device, window.sdl_window) };
    const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert_shader, // 编译好的顶点着色器
        .fragment_shader = frag_shader, // 编译好的片段着色器
        .vertex_input_state = .{},
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &color_target_desc },
    };
    return Self{
        .pipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse unreachable,
    };
}

pub fn bind(self: *const Self, render_pass: ?*c.SDL_GPURenderPass) void {
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
}

pub fn draw(_: *const Self, render_pass: ?*c.SDL_GPURenderPass) void {
    // 绘制 3 个顶点覆盖整个屏幕
    c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
}
