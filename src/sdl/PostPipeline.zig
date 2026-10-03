const std = @import("std");
const c = @import("c.zig").c;
const post_util = @import("post_util.zig");
const Error = @import("errors.zig").Error;
const ShaderPair = @import("structs.zig").ShaderPair;
const Self = @This();

// 功能类型枚举
const EffectType = enum {
    sharpen, // 锐化
    blur_x, // 横向模糊
    blur_y, // 纵向模糊
    busy_fog, // 忙碌雾气
    mask, // 遮罩
    marker, // 标记
    custom, // 自定义
};

pub const Builder = struct {
    device: *c.SDL_GPUDevice,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,

    pub fn init(
        device: *c.SDL_GPUDevice,
        vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
        vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
        color_target_desc: *const c.SDL_GPUColorTargetDescription,
    ) Builder {
        return Builder{
            .device = device,
            .vert_buffer_desc = vert_buffer_desc,
            .vert_attrs = vert_attrs,
            .color_target_desc = color_target_desc,
        };
    }

    pub fn build(self: *const Builder, effect: EffectType, shader_pair: ShaderPair) !Self {
        return try Self.init(
            effect,
            self.device,
            shader_pair,
            self.vert_buffer_desc,
            self.vert_attrs,
            self.color_target_desc,
        );
    }
};

effect: EffectType,
pipeline: *c.SDL_GPUGraphicsPipeline,
render_pass: ?*c.SDL_GPURenderPass = null,

pub fn init(
    effect: EffectType,
    device: *c.SDL_GPUDevice,
    shader_pair: ShaderPair,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,
) !Self {
    const pipeline = try post_util.createPipeline(
        device,
        shader_pair,
        vert_buffer_desc,
        vert_attrs,
        color_target_desc,
    );
    return Self{
        .effect = effect,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: *Self, device: *c.SDL_GPUDevice) void {
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline);
    self.* = undefined;
}

pub fn bind(
    self: *Self,
    cmd_buf: *c.SDL_GPUCommandBuffer,
    tex_dst: ?*c.SDL_GPUTexture,
    tex_src: ?*c.SDL_GPUTexture,
    sampler: ?*c.SDL_GPUSampler,
    vertex_binding: *const c.SDL_GPUBufferBinding,
) void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = tex_dst,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0 },
    };
    // 开始渲染通道
    self.render_pass = c.SDL_BeginGPURenderPass(cmd_buf, &color_target, 1, null);
    // 绑定顶点缓冲区
    c.SDL_BindGPUVertexBuffers(self.render_pass, 0, vertex_binding, 1);
    // 绑定管线
    c.SDL_BindGPUGraphicsPipeline(self.render_pass, self.pipeline);
    const sampler_bind: c.SDL_GPUTextureSamplerBinding = .{
        .texture = tex_src,
        .sampler = sampler,
    };
    // 绑定采样器
    c.SDL_BindGPUFragmentSamplers(self.render_pass, 0, &sampler_bind, 1);
}

pub fn bindWithMaskTex(
    self: *Self,
    cmd_buf: *c.SDL_GPUCommandBuffer,
    tex_dst: ?*c.SDL_GPUTexture,
    tex_src: ?*c.SDL_GPUTexture,
    tex_mask: ?*c.SDL_GPUTexture,
    sampler: ?*c.SDL_GPUSampler,
    vertex_binding: *const c.SDL_GPUBufferBinding,
) void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = tex_dst,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0 },
    };
    // 开始渲染通道
    self.render_pass = c.SDL_BeginGPURenderPass(cmd_buf, &color_target, 1, null);
    // 绑定顶点缓冲区
    c.SDL_BindGPUVertexBuffers(self.render_pass, 0, vertex_binding, 1);
    // 绑定管线
    c.SDL_BindGPUGraphicsPipeline(self.render_pass, self.pipeline);
    const sampler_binds: [2]c.SDL_GPUTextureSamplerBinding = .{
        .{ .texture = tex_src, .sampler = sampler },
        .{ .texture = tex_mask, .sampler = sampler },
    };
    // 绑定采样器
    c.SDL_BindGPUFragmentSamplers(self.render_pass, 0, &sampler_binds, 2);
}

pub fn draw(self: *const Self) void {
    c.SDL_DrawGPUPrimitives(self.render_pass, 6, 1, 0, 0);
}

pub fn end(self: *Self) void {
    c.SDL_EndGPURenderPass(self.render_pass);
}

// 从外部传入 render_pass
pub fn bindScreen(
    self: *Self,
    render_pass: ?*c.SDL_GPURenderPass,
    swapchain_texture: ?*c.SDL_GPUTexture,
    sampler: ?*c.SDL_GPUSampler,
    vertex_binding: *const c.SDL_GPUBufferBinding,
) void {
    self.render_pass = render_pass;
    // 绑定顶点缓冲区
    c.SDL_BindGPUVertexBuffers(render_pass, 0, vertex_binding, 1);
    // 绑定管线
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    const sampler_bind: c.SDL_GPUTextureSamplerBinding = .{
        .texture = swapchain_texture,
        .sampler = sampler,
    };
    // 绑定采样器
    c.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bind, 1);
}
