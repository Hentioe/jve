const std = @import("std");
const sdl = @import("sdl");
const consts = @import("../consts.zig");
const structs = @import("../structs.zig");
const LImage = @import("vips").LImage;
const Window = @import("../window.zig");
const Uploader = @import("../Uploader.zig");
const shader_loader = @import("../shader_loader.zig");
const Checkerboard = @import("../checkerboard_gpu.zig");
const OnscreenPipeline = @import("../onscreen_pipeline.zig");
const PostPipeline = @import("../PostPipeline.zig");
const Pipeline = @import("../Pipeline.zig");
const Error = @import("../errors.zig").Error;
const Vertex = structs.Vertex;
const Self = @This();

allocator: std.mem.Allocator,
window: *Window,
device: *const sdl.Gpu,
image: LImage,
uploader: Uploader,
texture: *sdl.c.SDL_GPUTexture,
offscreen_info: sdl.c.SDL_GPUTextureCreateInfo,
// 基础着色器
vert_shader: *sdl.c.SDL_GPUShader,
frag_shader: *sdl.c.SDL_GPUShader,
// 后处理片段着色器（供释放）
sharpen_shader: *sdl.c.SDL_GPUShader,
blur_shader: *sdl.c.SDL_GPUShader,
fog_shader: *sdl.c.SDL_GPUShader,
overflow_shader: *sdl.c.SDL_GPUShader,
mask_shader: *sdl.c.SDL_GPUShader,
// 顶点
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
sampler: *sdl.c.SDL_GPUSampler,
// 管线
base_pipeline: *sdl.c.SDL_GPUGraphicsPipeline,
checkerboard: Checkerboard,
onscreen: OnscreenPipeline,
sharpen: PostPipeline,
blur_x: PostPipeline,
blur_y: PostPipeline,
fog: PostPipeline,
overflow: PostPipeline,
mask: PostPipeline,
marker: Pipeline,
// 离屏纹理（乒乓）
tex_a: *sdl.c.SDL_GPUTexture,
tex_b: *sdl.c.SDL_GPUTexture,
// 自定义管线（堆分配，便于释放）
custom: std.ArrayList(*PostPipeline),

pub fn init(
    allocator: std.mem.Allocator,
    window: *Window,
    device: *const sdl.Gpu,
    shaders: ?[]const *sdl.c.SDL_GPUShader,
    image: LImage,
) Error!Self {
    // -- 上传器 (Uploader) --
    var uploader = Uploader.init(allocator, device);

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
    const texture = try uploader.uploadTexture(&texture_info, image.pixels_ptr, texture_size);

    // -- 顶点 (Vertex) --
    const verts: [6]Vertex = consts.base_verts;
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = try uploader.uploadBuffer(&verts_buffer_info, @ptrCast(&verts), verts_size);
    const verts_binding: sdl.c.SDL_GPUBufferBinding = .{ .buffer = verts_buffer, .offset = 0 };

    // 一次性提交纹理与顶点上传
    try uploader.submit();

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
    const color_target_desc: sdl.c.SDL_GPUColorTargetDescription = .{
        .format = device.getGPUSwapchainTextureFormat(window.sdl_window),
        .blend_state = .{ // 启用 Alpha 混合
            .enable_blend = true,
            .src_color_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .dst_color_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = sdl.c.SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = sdl.c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = sdl.c.SDL_GPU_BLENDOP_ADD,
            .enable_color_write_mask = false, // 为 false 时自动写全 RGBA 通道
        },
    };
    const vert_shader = try shader_loader.load(device, @embedFile("base.vert.spv"), "main", .vertex, 0, 0);
    const frag_shader = try shader_loader.load(device, @embedFile("base.frag.spv"), "main", .fragment, 1, 1);
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
    // 构造棋盘格（透明图片的背景）
    const checkerboard = try Checkerboard.init(device, window);

    // 创建离屏渲染纹理 A 和 B
    const offscreen_info: sdl.c.SDL_GPUTextureCreateInfo = .{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 与 Swapchain 格式一致
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = texture_size.w,
        .height = texture_size.h,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const tex_a = try device.createGPUTexture(&offscreen_info);
    const tex_b = try device.createGPUTexture(&offscreen_info);

    // 创建屏幕渲染的直通管线
    const onscreen = try OnscreenPipeline.init(device, vert_shader, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    // 创建内建的后处理管线
    const pl_builder = PostPipeline.Builder.init(device, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    const sharpen_frag_shader = try shader_loader.load(device, @embedFile("sharpen.frag.spv"), "main", .fragment, 1, 1);
    const sharpen = try pl_builder.build(.sharpen, .{ .vert = vert_shader, .frag = sharpen_frag_shader });
    const blur_frag_shader = try shader_loader.load(device, @embedFile("blur.frag.spv"), "main", .fragment, 1, 1);
    const blur_x_pl = try pl_builder.build(.blur_x, .{ .vert = vert_shader, .frag = blur_frag_shader });
    const blur_y_pl = try pl_builder.build(.blur_y, .{ .vert = vert_shader, .frag = blur_frag_shader });
    const fog_frag_shader = try shader_loader.load(device, @embedFile("fog.frag.spv"), "main", .fragment, 0, 1);
    const fog_pl = try pl_builder.build(.fog, .{ .vert = vert_shader, .frag = fog_frag_shader });
    // 构造超出提示管线（图片过大被限制尺寸时，在屏幕边缘显示提示）
    const overflow_frag_shader = try shader_loader.load(device, @embedFile("overflow.frag.spv"), "main", .fragment, 0, 1);
    const overflow_pl = try pl_builder.build(.overflow, .{ .vert = vert_shader, .frag = overflow_frag_shader });
    const mask_frag_shader = try shader_loader.load(device, @embedFile("mask.frag.spv"), "main", .fragment, 2, 0);
    const mask_pl = try pl_builder.build(.mask, .{ .vert = vert_shader, .frag = mask_frag_shader });
    // 构造标记管线
    const marker_vert_shader = try shader_loader.load(device, @embedFile("marker.vert.spv"), "main", .vertex, 0, 1);
    const marker_frag_shader = try shader_loader.load(device, @embedFile("marker.frag.spv"), "main", .fragment, 0, 1);
    const marker_pl = try Pipeline.init(device, window.sdl_window, .{ .vert = marker_vert_shader, .frag = marker_frag_shader }, null);

    // 添加自定义管线
    var custom = std.ArrayList(*PostPipeline).empty;
    if (shaders) |list| {
        for (list) |shader| {
            const pl = try allocator.create(PostPipeline); // 在堆上创建，避免被作用域回收
            pl.* = try pl_builder.build(
                .custom,
                .{ .vert = vert_shader, .frag = shader },
            );
            try custom.append(allocator, pl);
        }
    }

    return Self{
        .allocator = allocator,
        .window = window,
        .device = device,
        .image = image,
        .uploader = uploader,
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
        .checkerboard = checkerboard,
        .onscreen = onscreen,
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
    };
}

pub fn deinit(self: *Self) void {
    self.marker.deinit();
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
    self.checkerboard.deinit();
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
    self.uploader.deinit();
    self.* = undefined;
}

/// 内建后处理管线（顺序即渲染顺序）
pub fn builtin(self: *Self) [4]*PostPipeline {
    return .{ &self.sharpen, &self.blur_x, &self.blur_y, &self.mask };
}
