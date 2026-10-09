const sdl = @import("sdl");
const c = sdl.c;
const Gpu = sdl.Gpu;
const Error = @import("errors.zig").Error;
const ShaderPair = @import("structs.zig").ShaderPair;
const Self = @This();

gpu: *Gpu,
sdl_pipeline: *c.SDL_GPUGraphicsPipeline,
vert_shader: *sdl.c.SDL_GPUShader,
frag_shader: ?*sdl.c.SDL_GPUShader,
render_pass: ?*c.SDL_GPURenderPass = null,

pub fn init(gpu: *Gpu, window: *c.SDL_Window, shaders: ShaderPair, vertex_input_state: ?sdl.c.SDL_GPUVertexInputState) Error!Self {
    // 构造管线
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{
        .format = gpu.getGPUSwapchainTextureFormat(window),
        .blend_state = .{ // 启用 Alpha 混合
            .enable_blend = true,
            .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
            .enable_color_write_mask = false, // 为 false 时自动写全 RGBA 通道
        },
    };

    const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = shaders.vert, // 编译好的顶点着色器
        .fragment_shader = shaders.frag, // 编译好的片段着色器
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &color_target_desc },
        .vertex_input_state = vertex_input_state orelse .{},
    };

    const sdl_pipeline = try gpu.createGPUGraphicsPipeline(&pipeline_info);

    return Self{
        .gpu = gpu,
        .vert_shader = shaders.vert,
        .frag_shader = shaders.frag,
        .sdl_pipeline = sdl_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.gpu.releaseGPUGraphicsPipeline(self.sdl_pipeline);
    if (self.frag_shader) |s| self.gpu.releaseGPUShader(s);
    self.gpu.releaseGPUShader(self.vert_shader);
}

pub fn bind(self: *Self, render_pass: *c.SDL_GPURenderPass) void {
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.sdl_pipeline);
    self.render_pass = render_pass;
}

pub fn pushVertexUniforms(_: *const Self, cmd_buf: *c.SDL_GPUCommandBuffer, slot_index: u32, data: *const anyopaque, length: u32) void {
    c.SDL_PushGPUVertexUniformData(cmd_buf, slot_index, data, length);
}

pub fn pushFragmentUniforms(_: *const Self, cmd_buf: *c.SDL_GPUCommandBuffer, slot_index: u32, data: *const anyopaque, length: u32) void {
    c.SDL_PushGPUFragmentUniformData(cmd_buf, slot_index, data, length);
}

pub fn draw(self: *Self) void {
    c.SDL_DrawGPUPrimitives(self.render_pass, 6, 1, 0, 0);
}

pub fn end(self: *Self) void {
    c.SDL_EndGPURenderPass(self.render_pass);
}
