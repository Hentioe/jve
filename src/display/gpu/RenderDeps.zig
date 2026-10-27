const std = @import("std");
const sdl = @import("sdl");
const zeroInit = std.mem.zeroInit;
const shared = @import("shared");
const consts = @import("../consts.zig");
const ui = @import("../../ui.zig");
const pipelines = @import("../../pipelines.zig");
const LImage = @import("vips").LImage;
const Animation = @import("vips").Animation;
const Vertex = shared.Vertex;
const Window = @import("../window.zig");
const Device = @import("../../Device.zig");
const shader = @import("../../shader.zig");
const Manuals = std.AutoHashMap(*const shader.loaded.Item, *pipelines.Post);
const Error = @import("../errors.zig").Error;
const Self = @This();

allocator: std.mem.Allocator,
window: *Window,
device: *const sdl.Gpu,
image: LImage,
animation: ?Animation,
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
// 自定义管线列表
custom: std.ArrayList(*pipelines.Post),
// 手动激活的管线列表
manuals: Manuals,
// 组件列表
widgets: []ui.Widget,
// 错误消息横幅
banner: *ui.TextBanner,

pub fn init(
    allocator: std.mem.Allocator,
    window: *Window,
    device: *const sdl.Gpu,
    image: LImage,
    shaders: ?shader.loaded.All,
    widgets: []ui.Widget,
    error_banner: *ui.TextBanner,
) Error!Self {
    // -- 上传器 (Uploader) --
    const uploader = try Device.getUploader();

    // -- 纹理 (Texture) --
    const texture_size = image.shape.toSize2D(u32);
    // type / sample_count / props 留空：分别为 2D、单采样、0（zeroInit 清零）
    const texture_info = zeroInit(sdl.GPUTextureCreateInfo, .{
        // 像素格式：RGBA8888，对应上传的像素数据
        .format = sdl.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        // 用途：作为采样器纹理供管线读取
        .usage = sdl.GPU_TEXTUREUSAGE_SAMPLER,
        .width = texture_size.w,
        .height = texture_size.h,
        // 层数/深度：非数组、非 3D 纹理必须为 1
        .layer_count_or_depth = 1,
        // mip 层级：1 表示不生成 mipmap（0 会生成完整 mip 链）
        .num_levels = 1,
    });
    const texture = try uploader.uploadTextureBorrowed(&texture_info, image.pixels_ptr, texture_size);

    // -- 动图容器 (Animation) --
    // 仅对 GIF/WebP/JXL 尝试；其他格式或单帧图会返回 null。
    const animation = Animation.init(allocator, image.file_path, .{}) catch |err| blk: {
        std.log.warn("Failed to initialize animation for {s}: {}", .{ image.file_path, err });
        break :blk null;
    };

    // -- 顶点 (Vertex) --
    const verts: [6]Vertex = consts.base_verts;
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = zeroInit(sdl.GPUBufferCreateInfo, .{
        // 用途：顶点缓冲区，绘制时绑定给顶点阶段读取
        .usage = sdl.GPU_BUFFERUSAGE_VERTEX,
        // 缓冲区大小（字节）：6 个顶点
        .size = verts_size,
    });
    const verts_buffer = try uploader.uploadBufferBorrowed(&verts_buffer_info, @ptrCast(&verts), verts_size);
    const verts_binding: sdl.c.SDL_GPUBufferBinding = .{ .buffer = verts_buffer, .offset = 0 };

    // -- 纹理采样器 (Sampler) --
    // 其余字段留空：mip_lod_bias/min_lod/max_lod = 0、无各向异性、无深度比较、props = 0
    const sampler_desc = zeroInit(sdl.GPUSamplerCreateInfo, .{
        // 缩小/放大过滤：线性插值，缩放图片时更平滑
        .min_filter = sdl.GPU_FILTER_LINEAR,
        .mag_filter = sdl.GPU_FILTER_LINEAR,
        // mipmap 过滤模式：线性（纹理本身只有一级 mip）
        .mipmap_mode = sdl.GPU_SAMPLERMIPMAPMODE_LINEAR,
        // UVW 越界模式：钳制到边缘，避免图片边缘出现重复像素
        .address_mode_u = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    });
    const sampler = try device.createGPUSampler(&sampler_desc);

    // -- 图形管线 (Graphics Pipeline) --
    const vert_attrs: [2]sdl.c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x"), .buffer_slot = 0 }, // Position
        .{ .location = 1, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u"), .buffer_slot = 0 }, // UV
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
    const vert_buffer_desc: sdl.c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = sdl.c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0 };
    // 其余字段留空：primitive_type = TRIANGLELIST、光栅化/多重采样/深度模板状态取默认零值、props = 0
    const pipeline_info = zeroInit(sdl.GPUGraphicsPipelineCreateInfo, .{
        // 编译好的顶点着色器
        .vertex_shader = vert_shader,
        // 编译好的片段着色器
        .fragment_shader = frag_shader,
        // 顶点输入布局
        .vertex_input_state = zeroInit(sdl.GPUVertexInputState, .{
            // 顶点缓冲数量与描述（槽位、步长、输入率）
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vert_buffer_desc,
            // 顶点属性数量与属性表（位置 + UV）
            .num_vertex_attributes = 2,
            .vertex_attributes = &vert_attrs,
        }),
        // 渲染目标信息（外层 zeroInit 递归清零缺省字段）
        .target_info = .{
            // 颜色目标数量：1
            .num_color_targets = 1,
            // 颜色目标描述（格式与混合状态）
            .color_target_descriptions = &color_target_desc,
        },
    });
    // 基础着色器（负责图像渲染）
    const base_pl = try device.createGPUGraphicsPipeline(&pipeline_info);
    // 构造背景
    const background = try pipelines.Background.init(color_target_desc.format);

    // 创建离屏渲染纹理 A 和 B
    // type / sample_count / props 留空：分别为 2D、单采样、0（zeroInit 清零）
    const offscreen_info = zeroInit(sdl.GPUTextureCreateInfo, .{
        // 像素格式：与交换链颜色目标一致，便于屏幕直通采样
        .format = color_target_desc.format,
        // 用途：既作为后处理管线的渲染目标，也作为下一趟的采样输入
        .usage = sdl.GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.GPU_TEXTUREUSAGE_SAMPLER,
        .width = texture_size.w,
        .height = texture_size.h,
        // 层数/深度：非数组、非 3D 纹理必须为 1
        .layer_count_or_depth = 1,
        // mip 层级：1 表示不生成 mipmap（0 会生成完整 mip 链）
        .num_levels = 1,
    });
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
    var custom: std.ArrayList(*pipelines.Post) = .empty;
    if (shaders) |all| {
        var list = try all.defaults(allocator);
        defer list.deinit(allocator);
        for (list.items) |item| {
            const pl = try allocator.create(pipelines.Post); // 在堆上创建，避免被作用域回收
            pl.* = try pl_builder.build(
                .custom,
                .{ .vert = vert_shader, .frag = item.shader },
            );
            try custom.append(allocator, pl);
        }
    }
    // 添加手动激活管线
    var manuals: Manuals = .init(allocator);
    if (shaders) |all| {
        var list = try all.manuals(allocator);
        defer list.deinit(allocator);
        for (list.items) |item| {
            const pl = try allocator.create(pipelines.Post); // 在堆上创建，避免被作用域回收
            pl.* = try pl_builder.build(
                .custom,
                .{ .vert = vert_shader, .frag = item.shader },
            );
            try manuals.put(item, pl);
        }
    }
    // 统一提交本次初始化中所有组件的资源上传
    try uploader.submit();

    return Self{
        .allocator = allocator,
        .window = window,
        .device = device,
        .image = image,
        .animation = animation,
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
        .manuals = manuals,
        .widgets = widgets,
        .banner = error_banner,
    };
}

pub fn deinit(self: *Self) void {
    if (self.animation) |*animation| animation.deinit();
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
    var iter = self.manuals.valueIterator();
    while (iter.next()) |pl| {
        pl.*.deinit(self.device);
        self.allocator.destroy(pl.*);
    }
    self.manuals.deinit();
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

/// 将动图的一帧上传到当前图像纹理，复用已有纹理，不重新创建 GPU 资源。
pub fn updateFrame(self: *Self, view: Animation.FrameView) Error!void {
    const uploader = try Device.getUploader();
    try uploader.updateTextureBorrowed(self.texture, @ptrCast(view.pixels), view.size);
    try uploader.submit();
}

/// 内建后处理管线（顺序即渲染顺序）
pub fn builtin(self: *Self) [4]*pipelines.Post {
    return .{ &self.sharpen, &self.blur_x, &self.blur_y, &self.mask };
}

/// 非预乘输入叠加到透明目标时的混合状态（基础 pass 用，结果变为预乘 Alpha）
fn blendState() sdl.GPUColorTargetBlendState {
    return zeroInit(sdl.GPUColorTargetBlendState, .{
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
    });
}

/// 预乘 Alpha 的混合状态：源颜色已经乘过 Alpha，直接叠加，不再重复相乘
fn premultipliedBlendState() sdl.GPUColorTargetBlendState {
    return zeroInit(sdl.GPUColorTargetBlendState, .{
        // 源颜色：已预乘，直接取用
        .src_color_blendfactor = sdl.GPU_BLENDFACTOR_ONE,
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
    });
}
