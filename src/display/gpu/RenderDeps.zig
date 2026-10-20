const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const consts = @import("../consts.zig");
const structs = @import("../structs.zig");
const LImage = @import("vips").LImage;
const Vertex = shared.Vertex;
const Window = @import("../window.zig");
const Device = @import("../../Device.zig");
const pipelines = @import("../../pipelines.zig");
const shader = @import("../../shader.zig");
const ui = @import("../../ui.zig");
const Error = @import("../errors.zig").Error;
const Self = @This();

allocator: std.mem.Allocator,
window: *Window,
device: *const sdl.Gpu,
image: LImage,
texture: *sdl.c.SDL_GPUTexture,
offscreen_info: sdl.c.SDL_GPUTextureCreateInfo,
// 基础着色器
vert_shader: *sdl.GPUShader,
frag_shader: *sdl.GPUShader,
// 后处理片段着色器（供释放）
sharpen_shader: *sdl.GPUShader,
blur_shader: *sdl.GPUShader,
fog_shader: *sdl.GPUShader,
overflow_shader: *sdl.GPUShader,
mask_shader: *sdl.GPUShader,
// 顶点
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
sampler: *sdl.c.SDL_GPUSampler,
// 管线
base_pipeline: *sdl.c.SDL_GPUGraphicsPipeline,
background: pipelines.Background,
screen: pipelines.Screen,
sharpen: pipelines.Post,
blur_x: pipelines.Post,
blur_y: pipelines.Post,
fog: pipelines.Post,
overflow: pipelines.Post,
mask: pipelines.Post,
marker: pipelines.Base,
// 离屏纹理（乒乓）
tex_a: *sdl.c.SDL_GPUTexture,
tex_b: *sdl.c.SDL_GPUTexture,
// 自定义管线（堆分配，便于释放）
custom: std.ArrayList(*pipelines.Post),
// 组件列表
widgets: []ui.Widget,

pub fn init(
    allocator: std.mem.Allocator,
    window: *Window,
    device: *const sdl.Gpu,
    image: LImage,
    shaders: ?[]const *sdl.GPUShader,
    widgets: []ui.Widget,
) Error!Self {
    // -- 上传器 (Uploader) --
    const uploader = try Device.getUploader();

    // -- 纹理 (Texture) --
    const texture_size = image.shape.toSize2D(u32);
    const texture_info = sdl.c.SDL_GPUTextureCreateInfo{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 对应常见的 RGBA8888 像素格式
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_SAMPLER, // 作为采样器供 Pipeline 渲染
        .width = texture_size.w,
        .height = texture_size.h,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const texture = try uploader.uploadTextureBorrowed(&texture_info, image.pixels_ptr, texture_size);

    // -- 顶点 (Vertex) --
    const verts: [6]Vertex = consts.base_verts;
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = try uploader.uploadBufferBorrowed(&verts_buffer_info, @ptrCast(&verts), verts_size);
    const verts_binding: sdl.c.SDL_GPUBufferBinding = .{ .buffer = verts_buffer, .offset = 0 };

    // -- 纹理采样器 (Sampler) --
    const sampler_desc = sdl.c.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl.c.SDL_GPU_FILTER_LINEAR, // 线性过滤
        .mag_filter = sdl.c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = sdl.c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    };
    const sampler = try device.createGPUSampler(&sampler_desc);

    // -- 图形管线 (Graphics Pipeline) --
    const vert_attrs: [2]sdl.c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    // 所有颜色目标统一为 R8G8B8A8_UNORM
    // 基础 pass 输入非预乘图像，用 SRC_ALPHA 混合写入透明目标，写入后即为预乘 Alpha
    const color_target_desc: sdl.c.SDL_GPUColorTargetDescription = .{
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .blend_state = blendState(),
    };
    // 链上的内容自基础 pass 起均为预乘 Alpha，后续 pass 与屏幕直通必须用预乘混合，
    // 否则会把预乘颜色再乘一次 Alpha，导致边缘变暗
    const premultiplied_color_target_desc: sdl.c.SDL_GPUColorTargetDescription = .{
        .format = color_target_desc.format,
        .blend_state = premultipliedBlendState(),
    };
    const vert_shader = try shader.loader.load(device, @embedFile("base.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    const frag_shader = try shader.loader.load(device, @embedFile("base.frag.spv"), "main", .fragment, .{ .samplers = 1, .buffers = 1 });
    const vert_buffer_desc: sdl.c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = sdl.c.SDL_GPU_VERTEXINPUTRATE_VERTEX };
    const pipeline_info: sdl.c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert_shader, // 编译好的顶点着色器
        .fragment_shader = frag_shader, // 编译好的片段着色器
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vert_buffer_desc,
            .num_vertex_attributes = 2,
            .vertex_attributes = &vert_attrs,
        },
        .primitive_type = sdl.c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &color_target_desc },
    };
    // 基础着色器（负责图像渲染）
    const base_pl = try device.createGPUGraphicsPipeline(&pipeline_info);
    // 构造背景
    const background = try pipelines.Background.init(device, color_target_desc.format);

    // 创建离屏渲染纹理 A 和 B
    const offscreen_info: sdl.c.SDL_GPUTextureCreateInfo = .{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = color_target_desc.format,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = texture_size.w,
        .height = texture_size.h,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const tex_a = try device.createGPUTexture(&offscreen_info);
    const tex_b = try device.createGPUTexture(&offscreen_info);

    // 创建屏幕渲染的直通管线
    const onscreen = try pipelines.Screen.init(device, vert_shader, &vert_buffer_desc, &vert_attrs, &premultiplied_color_target_desc);
    // 链上后处理：输入输出均为预乘 Alpha
    const pl_builder = pipelines.Post.Builder.init(device, &vert_buffer_desc, &vert_attrs, &premultiplied_color_target_desc);
    // 仅屏幕叠加的管线：输出非预乘颜色，仍用 SRC_ALPHA 混合
    const screen_builder = pipelines.Post.Builder.init(device, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    const sharpen_frag_shader = try shader.loader.load(device, @embedFile("sharpen.frag.spv"), "main", .fragment, .{ .samplers = 1, .buffers = 1 });
    const sharpen = try pl_builder.build(.sharpen, .{ .vert = vert_shader, .frag = sharpen_frag_shader });
    const blur_frag_shader = try shader.loader.load(device, @embedFile("blur.frag.spv"), "main", .fragment, .{ .samplers = 1, .buffers = 1 });
    const blur_x_pl = try pl_builder.build(.blur_x, .{ .vert = vert_shader, .frag = blur_frag_shader });
    const blur_y_pl = try pl_builder.build(.blur_y, .{ .vert = vert_shader, .frag = blur_frag_shader });
    const fog_frag_shader = try shader.loader.load(device, @embedFile("fog.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 1 });
    const fog_pl = try screen_builder.build(.fog, .{ .vert = vert_shader, .frag = fog_frag_shader });
    // 构造超出提示管线（图片过大被限制尺寸时，在屏幕边缘显示提示）
    const overflow_frag_shader = try shader.loader.load(device, @embedFile("overflow.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 1 });
    const overflow_pl = try screen_builder.build(.overflow, .{ .vert = vert_shader, .frag = overflow_frag_shader });
    const mask_frag_shader = try shader.loader.load(device, @embedFile("mask.frag.spv"), "main", .fragment, .{ .samplers = 2, .buffers = 0 });
    const mask_pl = try pl_builder.build(.mask, .{ .vert = vert_shader, .frag = mask_frag_shader });
    // 构造标记管线
    const marker_vert_shader = try shader.loader.load(device, @embedFile("marker.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 1 });
    const marker_frag_shader = try shader.loader.load(device, @embedFile("marker.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 1 });
    const marker_pl = try pipelines.Base.init(device, window.sdl_window, .{ .vert = marker_vert_shader, .frag = marker_frag_shader }, null);

    // 添加自定义管线
    var custom = std.ArrayList(*pipelines.Post).empty;
    if (shaders) |list| {
        for (list) |frag| {
            const pl = try allocator.create(pipelines.Post); // 在堆上创建，避免被作用域回收
            pl.* = try pl_builder.build(
                .custom,
                .{ .vert = vert_shader, .frag = frag },
            );
            try custom.append(allocator, pl);
        }
    }

    // 统一提交本次初始化中所有组件的资源上传
    try uploader.submit();

    return Self{
        .allocator = allocator,
        .window = window,
        .device = device,
        .image = image,
        .texture = texture,
        .offscreen_info = offscreen_info,
        .vert_shader = vert_shader,
        .frag_shader = frag_shader,
        .sharpen_shader = sharpen_frag_shader,
        .blur_shader = blur_frag_shader,
        .fog_shader = fog_frag_shader,
        .overflow_shader = overflow_frag_shader,
        .mask_shader = mask_frag_shader,
        .verts_buffer = verts_buffer,
        .verts_binding = verts_binding,
        .sampler = sampler,
        .base_pipeline = base_pl,
        .background = background,
        .screen = onscreen,
        .sharpen = sharpen,
        .blur_x = blur_x_pl,
        .blur_y = blur_y_pl,
        .fog = fog_pl,
        .overflow = overflow_pl,
        .mask = mask_pl,
        .marker = marker_pl,
        .tex_a = tex_a,
        .tex_b = tex_b,
        .custom = custom,
        .widgets = widgets,
    };
}

pub fn deinit(self: *Self) void {
    self.marker.deinit();
    self.screen.deinit();
    self.mask.deinit(self.device);
    self.overflow.deinit(self.device);
    self.fog.deinit(self.device);
    self.blur_y.deinit(self.device);
    self.blur_x.deinit(self.device);
    self.sharpen.deinit(self.device);
    for (self.custom.items) |pl| {
        pl.deinit(self.device);
        self.allocator.destroy(pl);
    }
    self.custom.deinit(self.allocator);
    self.background.deinit();
    self.device.releaseGPUGraphicsPipeline(self.base_pipeline);
    self.device.releaseGPUShader(self.mask_shader);
    self.device.releaseGPUShader(self.overflow_shader);
    self.device.releaseGPUShader(self.fog_shader);
    self.device.releaseGPUShader(self.blur_shader);
    self.device.releaseGPUShader(self.sharpen_shader);
    self.device.releaseGPUShader(self.frag_shader);
    self.device.releaseGPUShader(self.vert_shader);
    self.device.releaseGPUSampler(self.sampler);
    self.device.releaseGPUBuffer(self.verts_buffer);
    self.device.releaseGPUTexture(self.tex_b);
    self.device.releaseGPUTexture(self.tex_a);
    self.device.releaseGPUTexture(self.texture);
    self.* = undefined;
}

/// 内建后处理管线（顺序即渲染顺序）
pub fn builtin(self: *Self) [4]*pipelines.Post {
    return .{ &self.sharpen, &self.blur_x, &self.blur_y, &self.mask };
}

/// 非预乘输入叠加到透明目标时的混合状态（基础 pass 用，结果变为预乘 Alpha）
fn blendState() sdl.c.SDL_GPUColorTargetBlendState {
    return .{
        .enable_blend = true,
        .src_color_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl.c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl.c.SDL_GPU_BLENDOP_ADD,
        .enable_color_write_mask = false, // 为 false 时自动写全 RGBA 通道
    };
}

/// 预乘 Alpha 的混合状态：源颜色已经乘过 Alpha，直接叠加，不再重复相乘
fn premultipliedBlendState() sdl.c.SDL_GPUColorTargetBlendState {
    return .{
        .enable_blend = true,
        .src_color_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_color_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl.c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl.c.SDL_GPU_BLENDOP_ADD,
        .enable_color_write_mask = false, // 为 false 时自动写全 RGBA 通道
    };
}
