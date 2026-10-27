const std = @import("std");
const sdl = @import("sdl");
const c = sdl.c;
const h = sdl.h;
const zeroInit = std.mem.zeroInit;
const shader_loader = @import("../shader/loader.zig");
const Device = @import("../Device.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

gpu: *const sdl.Gpu,
pipeline: *sdl.GPUGraphicsPipeline,
vert_shader: *sdl.GPUShader,
frag_shader: *sdl.GPUShader,
frag_from_user: bool,
pass: ?*sdl.GPURenderPass = null,

pub fn init(format: c.SDL_GPUTextureFormat) Error!Self {
    const gpu = try Device.getGpu();
    const existing_frag = Device.getBackgroundShader();
    var frag_from_user = false;
    var frag_shader: *sdl.GPUShader = undefined;
    const vert_shader = try shader_loader.load(gpu, @embedFile("background.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    if (existing_frag) |shader| {
        frag_from_user = true;
        frag_shader = shader;
    } else {
        frag_shader = try shader_loader.load(gpu, @embedFile("checker_bg.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 0 });
    }
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{
        .format = format,
        // 垫底混合：把背景画到已有内容下面（内容为预乘 Alpha）
        .blend_state = zeroInit(sdl.GPUColorTargetBlendState, .{
            // 源颜色：乘 (1 - 目标 Alpha)，让背景只填内容透明处
            .src_color_blendfactor = sdl.GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
            // 目标颜色：直接保留已有内容
            .dst_color_blendfactor = sdl.GPU_BLENDFACTOR_ONE,
            // 颜色混合运算：相加
            .color_blend_op = sdl.GPU_BLENDOP_ADD,
            // 源 Alpha：乘 (1 - 目标 Alpha)
            .src_alpha_blendfactor = sdl.GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
            // 目标 Alpha：直接保留
            .dst_alpha_blendfactor = sdl.GPU_BLENDFACTOR_ONE,
            // Alpha 混合运算：相加
            .alpha_blend_op = sdl.GPU_BLENDOP_ADD,
            // 启用混合
            .enable_blend = true,
        }),
    };
    // 其余字段留空：vertex_input_state 无顶点缓冲、primitive_type = TRIANGLELIST、
    // 光栅化/多重采样/深度模板状态均取默认零值、props = 0
    const pipeline_info = zeroInit(sdl.GPUGraphicsPipelineCreateInfo, .{
        // 编译好的顶点着色器
        .vertex_shader = vert_shader,
        // 编译好的片段着色器
        .fragment_shader = frag_shader,
        // 渲染目标信息（外层 zeroInit 递归清零缺省字段）
        .target_info = .{
            // 颜色目标数量：1
            .num_color_targets = 1,
            // 颜色目标描述（格式与混合状态）
            .color_target_descriptions = &color_target_desc,
        },
    });
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

pub fn bind(self: *Self, pass: *sdl.GPURenderPass) void {
    c.SDL_BindGPUGraphicsPipeline(pass, self.pipeline);
    self.pass = pass;
}

pub fn draw(self: *const Self) void {
    // 绘制 3 个顶点覆盖整个屏幕
    c.SDL_DrawGPUPrimitives(self.pass, 3, 1, 0, 0);
}

/// 链上的一趟：在已有内容上垫入背景（混合状态见 init）
pub fn composite(self: *Self, cmd: *c.SDL_GPUCommandBuffer, target: *sdl.GPUTexture) Error!void {
    const color_target = zeroInit(sdl.GPUColorTargetInfo, .{
        // 渲染目标纹理：叠加背景的目标纹理（链上已有内容）
        .texture = target,
        // 进入渲染通道时如何处理已有内容：保留原有像素，在其上混合背景
        .load_op = sdl.GPU_LOADOP_LOAD,
        // 离开渲染通道时如何存储结果：保留混合后的内容
        .store_op = sdl.GPU_STOREOP_STORE,
    });
    self.pass = try h.check(c.SDL_BeginGPURenderPass(cmd, &color_target, 1, null));
    c.SDL_BindGPUGraphicsPipeline(self.pass, self.pipeline);
    c.SDL_DrawGPUPrimitives(self.pass, 3, 1, 0, 0);
    c.SDL_EndGPURenderPass(self.pass);
}
