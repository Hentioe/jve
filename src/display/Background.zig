const c = @import("sdl").c;
const h = @import("sdl").h;
const Gpu = @import("sdl").Gpu;
const shader_loader = @import("../shader/loader.zig");
const Device = @import("../Device.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

gpu: *const Gpu,
pipeline: *c.SDL_GPUGraphicsPipeline,
vert_shader: *c.SDL_GPUShader,
frag_shader: *c.SDL_GPUShader,
frag_from_user: bool,
render_pass: ?*c.SDL_GPURenderPass = null,

pub fn init(gpu: *const Gpu, format: c.SDL_GPUTextureFormat) Error!Self {
    var frag_from_user = false;
    // 构造背景管线
    const vert_shader = try shader_loader.load(gpu, @embedFile("background.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    const frag_shader = if (Device.getBackgroundShader()) |shader| blk: {
        frag_from_user = true;
        break :blk shader;
    } else try shader_loader.load(gpu, @embedFile("checker_bg.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 0 });
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{
        .format = format,
        // 垫底混合：把背景画到已有内容下面（内容为预乘 Alpha）
        .blend_state = .{
            .enable_blend = true,
            .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
            .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
            .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
            .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
            .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
            .enable_color_write_mask = false,
        },
    };
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
        .frag_from_user = frag_from_user,
    };
}

pub fn deinit(self: *Self) void {
    self.gpu.releaseGPUGraphicsPipeline(self.pipeline);
    self.gpu.releaseGPUShader(self.vert_shader);
    if (!self.frag_from_user) self.gpu.releaseGPUShader(self.frag_shader);
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

/// 链上的一趟：在已有内容上垫入背景（混合状态见 init）
pub fn composite(self: *Self, cmd_buf: *c.SDL_GPUCommandBuffer, target: *c.SDL_GPUTexture) Error!void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = target,
        .load_op = c.SDL_GPU_LOADOP_LOAD,
        .store_op = c.SDL_GPU_STOREOP_STORE,
    };
    self.render_pass = try h.check(c.SDL_BeginGPURenderPass(cmd_buf, &color_target, 1, null));
    c.SDL_BindGPUGraphicsPipeline(self.render_pass, self.pipeline);
    c.SDL_DrawGPUPrimitives(self.render_pass, 3, 1, 0, 0);
    c.SDL_EndGPURenderPass(self.render_pass);
}
