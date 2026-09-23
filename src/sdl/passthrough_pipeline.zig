const c = @import("c.zig").c;
const post_util = @import("post_util.zig");
const shader_util = @import("shader_util.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Self = @This();

pipeline: *c.SDL_GPUGraphicsPipeline,
render_pass: ?*c.SDL_GPURenderPass = undefined,

pub fn init(
    device: *c.SDL_GPUDevice,
    vert_sharder: ?*c.SDL_GPUShader,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,
) Error!Self {
    const frag_sharder = try shader_util.loadAndCompileHLSL(
        device,
        "passthrough_frag.hlsl",
        "main",
        c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        1,
        0,
    );
    const pipeline = try post_util.createPipeline(
        device,
        .{ .vert = vert_sharder, .frag = frag_sharder },
        vert_buffer_desc,
        vert_attrs,
        color_target_desc,
    );

    return Self{
        .pipeline = pipeline,
    };
}

pub fn begin(self: *Self, swapchain_texture: ?*c.SDL_GPUTexture, render_cmd_buf: ?*c.SDL_GPUCommandBuffer) void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };
    self.render_pass = c.SDL_BeginGPURenderPass(render_cmd_buf, &color_target, 1, null);
}

pub fn draw(self: *Self, tex_src: ?*c.SDL_GPUTexture, sampler: ?*c.SDL_GPUSampler) void {
    c.SDL_BindGPUGraphicsPipeline(self.render_pass, self.pipeline);
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
