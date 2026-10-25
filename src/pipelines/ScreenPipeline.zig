const c = @import("sdl").c;
const h = @import("sdl").h;
const util = @import("util.zig");
const shader_loader = @import("../shader.zig").loader;
const Error = @import("errors.zig").Error;
const Gpu = @import("sdl").Gpu;
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
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 },
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .resolve_texture = null,
        .resolve_mip_level = 0,
        .resolve_layer = 0,
        .cycle = false,
        .cycle_resolve_texture = false,
        .padding1 = 0,
        .padding2 = 0,
    };
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
