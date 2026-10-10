const c = @import("sdl").c;
const h = @import("sdl").h;
const post_util = @import("post_util.zig");
const shader_loader = @import("shader_loader.zig");
const Error = @import("errors.zig").Error;
const Gpu = @import("sdl").Gpu;
const Self = @This();

pipeline: *c.SDL_GPUGraphicsPipeline,
render_pass: *c.SDL_GPURenderPass = undefined,

pub fn init(
    gpu: *const Gpu,
    vert_shader: *c.SDL_GPUShader,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,
) Error!Self {
    const frag_sharder = try shader_loader.load(gpu, @embedFile("onscreen.frag.spv"), "main", .fragment, 1, 0);
    const pipeline = try post_util.createPipeline(
        gpu,
        .{ .vert = vert_shader, .frag = frag_sharder },
        vert_buffer_desc,
        vert_attrs,
        color_target_desc,
    );

    return Self{
        .pipeline = pipeline,
    };
}

pub fn begin(self: *Self, cmd_buf: *c.SDL_GPUCommandBuffer, swapchain_texture: ?*c.SDL_GPUTexture) Error!void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
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
