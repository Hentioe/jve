const std = @import("std");
const sdl = @import("sdl");
const c = sdl.c;
const h = sdl.h;
const zeroInit = std.mem.zeroInit;
const util = @import("util.zig");
const shader_loader = @import("../shader.zig").loader;
const Error = @import("errors.zig").Error;
const Gpu = sdl.Gpu;
const Self = @This();

gpu: *const Gpu,
pipeline: *c.SDL_GPUGraphicsPipeline,
frag_shader: *c.SDL_GPUShader,
render_pass: *c.SDL_GPURenderPass = undefined,

pub fn init(
    gpu: *const Gpu,
    vert_shader: *c.SDL_GPUShader,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,
) Error!Self {
    const frag_shader = try shader_loader.load(gpu, @embedFile("onscreen.frag.spv"), "main", .fragment, .{ .samplers = 1, .buffers = 0 });
    const pipeline = try util.createPipeline(
        gpu,
        .{ .vert = vert_shader, .frag = frag_shader },
        vert_buffer_desc,
        vert_attrs,
        color_target_desc,
    );

    return Self{
        .gpu = gpu,
        .pipeline = pipeline,
        .frag_shader = frag_shader,
    };
}

pub fn deinit(self: *Self) void {
    // 释放本管线持有的图形管线与内部片段着色器；
    // 顶点着色器由 RenderDeps 共享持有，不在此释放。
    self.gpu.releaseGPUGraphicsPipeline(self.pipeline);
    self.gpu.releaseGPUShader(self.frag_shader);
    self.* = undefined;
}

pub fn begin(self: *Self, cmd_buf: *c.SDL_GPUCommandBuffer, swapchain_texture: ?*c.SDL_GPUTexture) Error!void {
    const color_target = zeroInit(sdl.GPUColorTargetInfo, .{
        // 渲染目标纹理：本次获取到的交换链纹理（屏幕）
        .texture = swapchain_texture,
        // 进入渲染通道时如何处理已有内容：清除为 clear_color（zeroInit 默认全 0）
        .load_op = sdl.GPU_LOADOP_CLEAR,
        // 离开渲染通道时如何存储结果：保留内容并提交到屏幕
        .store_op = sdl.GPU_STOREOP_STORE,
    });
    self.render_pass = try h.check(c.SDL_BeginGPURenderPass(cmd_buf, &color_target, 1, null));
}

pub fn bind(self: *Self) void {
    c.SDL_BindGPUGraphicsPipeline(self.render_pass, self.pipeline);
}

pub fn draw(self: *Self, tex_src: ?*c.SDL_GPUTexture, sampler: ?*c.SDL_GPUSampler) void {
    const sampler_binding: c.SDL_GPUTextureSamplerBinding = .{
        .texture = tex_src,
        .sampler = sampler,
    };
    c.SDL_BindGPUFragmentSamplers(self.render_pass, 0, &sampler_binding, 1);
    c.SDL_DrawGPUPrimitives(self.render_pass, 6, 1, 0, 0);
}

pub fn end(self: *Self) void {
    c.SDL_EndGPURenderPass(self.render_pass);
}
