const std = @import("std");
const c = @import("c.zig").c;
const post_util = @import("post_util.zig");
const Error = @import("errors.zig").Error;
const ShaderPair = @import("structs.zig").ShaderPair;
const Self = @This();

// 功能类型枚举
const PostEffectType = enum {
    Sharpen, // 锐化
    BlurX, // 横向模糊
    BlurY, // 纵向模糊
    BusyFog, // 忙碌雾气
    mask,
    custom,
};

effect: PostEffectType,
pipeline: *c.SDL_GPUGraphicsPipeline,
render_pass: ?*c.SDL_GPURenderPass = null,

pub fn init(
    effect: PostEffectType,
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
    tex_dst: ?*c.SDL_GPUTexture,
    tex_src: ?*c.SDL_GPUTexture,
    sampler: ?*c.SDL_GPUSampler,
    render_cmd_buf: ?*c.SDL_GPUCommandBuffer,
    vertex_binding: *const c.SDL_GPUBufferBinding,
) void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = tex_dst,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0 },
    };
    // 开始渲染通道
    self.render_pass = c.SDL_BeginGPURenderPass(render_cmd_buf, &color_target, 1, null);
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

pub fn bindMask(
    self: *Self,
    tex_dst: ?*c.SDL_GPUTexture,
    tex_src: ?*c.SDL_GPUTexture,
    tex_mask: ?*c.SDL_GPUTexture,
    sampler: ?*c.SDL_GPUSampler,
    render_cmd_buf: ?*c.SDL_GPUCommandBuffer,
    vertex_binding: *const c.SDL_GPUBufferBinding,
) void {
    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = tex_dst,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0 },
    };
    // 开始渲染通道
    self.render_pass = c.SDL_BeginGPURenderPass(render_cmd_buf, &color_target, 1, null);
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
    // 这里可以添加任何在渲染结束时需要执行的操作
    c.SDL_DrawGPUPrimitives(self.render_pass, 6, 1, 0, 0);
    c.SDL_EndGPURenderPass(self.render_pass);
}

pub fn bindWithPass(
    self: *Self,
    render_pass: ?*c.SDL_GPURenderPass,
    tex_src: ?*c.SDL_GPUTexture,
    sampler: ?*c.SDL_GPUSampler,
    vertex_binding: *const c.SDL_GPUBufferBinding,
) void {
    // 绑定顶点缓冲区
    c.SDL_BindGPUVertexBuffers(render_pass, 0, vertex_binding, 1);
    // 绑定管线
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    const sampler_bind: c.SDL_GPUTextureSamplerBinding = .{
        .texture = tex_src,
        .sampler = sampler,
    };
    // 绑定采样器
    c.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bind, 1);
}

pub fn drawWithPass(
    _: *const Self,
    render_pass: ?*c.SDL_GPURenderPass,
) void {
    c.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
}
