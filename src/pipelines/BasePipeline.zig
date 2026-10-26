const std = @import("std");
const sdl = @import("sdl");
const zeroInit = std.mem.zeroInit;
const c = sdl.c;
const Gpu = sdl.Gpu;
const ShaderPair = @import("structs.zig").ShaderPair;
const Error = @import("errors.zig").Error;
const Self = @This();

gpu: *const Gpu,
sdl_pipeline: *c.SDL_GPUGraphicsPipeline,
vert_shader: *sdl.c.SDL_GPUShader,
frag_shader: ?*sdl.c.SDL_GPUShader,
owns_vert: bool,
owns_frag: bool,
render_pass: ?*c.SDL_GPURenderPass = null,

const Ownership = struct {
    vert: bool = true,
    frag: bool = true,
};

pub fn init(gpu: *const Gpu, window: *c.SDL_Window, shaders: ShaderPair, vertex_input_state: ?sdl.c.SDL_GPUVertexInputState) Error!Self {
    return initInternal(gpu, window, shaders, vertex_input_state, .{});
}

/// 与 `init` 相同，但不接管顶点着色器的生命周期（由外部共享持有）。
pub fn initBorrowedVert(gpu: *const Gpu, window: *c.SDL_Window, shaders: ShaderPair, vertex_input_state: ?sdl.c.SDL_GPUVertexInputState) Error!Self {
    return initInternal(gpu, window, shaders, vertex_input_state, .{ .vert = false });
}

fn initInternal(
    gpu: *const Gpu,
    window: *c.SDL_Window,
    shaders: ShaderPair,
    vertex_input_state: ?sdl.c.SDL_GPUVertexInputState,
    ownership: Ownership,
) Error!Self {
    // 构造管线
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{
        .format = gpu.getGPUSwapchainTextureFormat(window),
        // 启用 Alpha 混合：非预乘输入按 SRC_ALPHA 叠加，写入后即预乘 Alpha
        .blend_state = zeroInit(sdl.GPUColorTargetBlendState, .{
            // 源颜色：乘源 Alpha（输入为非预乘）
            .src_color_blendfactor = sdl.GPU_BLENDFACTOR_SRC_ALPHA,
            // 目标颜色：乘 (1 - 源 Alpha)
            .dst_color_blendfactor = sdl.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            // 颜色混合运算：相加
            .color_blend_op = sdl.GPU_BLENDOP_ADD,
            // 源 Alpha：直接保留
            .src_alpha_blendfactor = sdl.GPU_BLENDFACTOR_ONE,
            // 目标 Alpha：乘 (1 - 源 Alpha)
            .dst_alpha_blendfactor = sdl.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            // Alpha 混合运算：相加
            .alpha_blend_op = sdl.GPU_BLENDOP_ADD,
            // 启用混合
            .enable_blend = true,
        }),
    };

    // 其余字段留空：primitive_type = TRIANGLELIST、光栅化/多重采样/深度模板状态取默认零值、props = 0
    var pipeline_info = zeroInit(sdl.GPUGraphicsPipelineCreateInfo, .{
        // 编译好的顶点着色器
        .vertex_shader = shaders.vert,
        // 编译好的片段着色器
        .fragment_shader = shaders.frag,
        // 渲染目标信息（外层 zeroInit 递归清零缺省字段）
        .target_info = .{
            // 颜色目标数量：1
            .num_color_targets = 1,
            // 颜色目标描述（格式与混合状态）
            .color_target_descriptions = &color_target_desc,
        },
    });
    // 可选的顶点输入状态：为空时保持零值（无顶点缓冲/属性）
    if (vertex_input_state) |state| pipeline_info.vertex_input_state = state;

    errdefer {
        if (ownership.frag) gpu.releaseGPUShader(shaders.frag);
        if (ownership.vert) gpu.releaseGPUShader(shaders.vert);
    }
    const sdl_pipeline = try gpu.createGPUGraphicsPipeline(&pipeline_info);

    return Self{
        .gpu = gpu,
        .vert_shader = shaders.vert,
        .frag_shader = shaders.frag,
        .owns_vert = ownership.vert,
        .owns_frag = ownership.frag,
        .sdl_pipeline = sdl_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.gpu.releaseGPUGraphicsPipeline(self.sdl_pipeline);
    if (self.owns_frag) if (self.frag_shader) |s| self.gpu.releaseGPUShader(s);
    if (self.owns_vert) self.gpu.releaseGPUShader(self.vert_shader);
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
