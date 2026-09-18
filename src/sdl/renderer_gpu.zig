const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const initializer = @import("initializer.zig");
const shader_util = @import("shader_util.zig");
const post_util = @import("post_util.zig");
const writer = @import("../root.zig").writer;
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const LoadedImage = @import("../root.zig").loader.Image;
const Checkerboard = @import("checkerboard_gpu.zig");
const PostPipeline = @import("post_pipeline.zig");
const PassthroughPipeline = @import("passthrough_pipeline.zig");

// 定义顶点与 UV 坐标
const Vertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
};

// 基础片段着色器 Uniforms
const BaseUniforms = extern struct {
    invert: f32, // 0.0 ~ 1.0
    grayscale: f32, // 0.0 为全彩，1.0 为完全灰阶（0.5 为半去色）
    brightness: f32, // 0.0 为正常，正数为增亮，负数为变暗
    contrast: f32, // 1.0 为正常，>1.0 增加对比度
    gamma: f32, // 1.0 为正常
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // 补齐 16 字节对齐 (5 * 4 = 20 字节，加 12 字节凑齐 32 字节)
};

// 锐化效果的片段着色器 Uniforms
const SharpenUniforms = extern struct {
    strength: f32,
    textureSize: [2]f32,
    padding: f32 = 0.0,
};

// 模糊效果的片段着色器 Uniforms
const BlurParams = extern struct {
    blurIntensity: f32,
    texelSize: [2]f32,
    _pad0: f32 = 0.0,
    direction: [2]f32,
    _pad1: [2]f32 = .{ 0.0, 0.0 },
};

// 基于 SDL_GPU 渲染图片
pub fn render(allocator: std.mem.Allocator, loaded: LoadedImage) Error!void {
    // 执行初始化
    try initializer.initialize(.SdlGpu);
    // 创建窗口
    var window = try Window.create(
        allocator,
        loaded.width,
        loaded.height,
        true,
        .SdlGpu,
    );
    defer window.destroy();
    // 更新窗口标题
    try window.setTitle(loaded.file_name);
    // 创建 GPU 设备
    const device = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL,
        false,
        null,
    ) orelse {
        helper.printSdlError();
        return Error.SdlCreateGPUDeviceFailed;
    };
    // 绑定窗口到 GPU 设备
    if (!c.SDL_ClaimWindowForGPUDevice(device, window.sdl_window)) {
        helper.printSdlError();
        return Error.SdlClaimWindowForGPUDeviceFailed;
    }
    // 关闭垂直同步（修改交换链的 Present Mode）
    // 默认的 SDL_GPU_PRESENTMODE_FIFO 有垂直同步效果，会阻塞渲染循环（导致事件积压，延迟响应）
    if (c.SDL_WindowSupportsGPUPresentMode(device, window.sdl_window, c.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
        if (!c.SDL_SetGPUSwapchainParameters(device, window.sdl_window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
            helper.printSdlError();
        }
    } else {
        std.log.warn("IMMEDIATE Present Mode not supported", .{});
    }
    // --- 纹理 (Texture)---
    // 1. 创建 GPU 纹理
    const texture_info = c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 对应常见的 RGBA8888 像素格式
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER, // 作为采样器供 Pipeline 渲染
        .width = @intCast(loaded.width),
        .height = @intCast(loaded.height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const texture = c.SDL_CreateGPUTexture(device, &texture_info);
    // 2. 将 CPU 像素数据上传至 GPU
    const image_size: u32 = @intCast(loaded.width * loaded.height * 4); // RGBA8888 字节大小
    const transfer_info = c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, // 指定为 UPLOAD 模式，即 CPU -> GPU
        .size = image_size,
    };
    const txu_transfer_buf = c.SDL_CreateGPUTransferBuffer(device, &transfer_info);
    // 映射内存并拷贝像素数据至传输缓冲区
    const map_ptr = c.SDL_MapGPUTransferBuffer(device, txu_transfer_buf, false);
    _ = c.SDL_memcpy(map_ptr, loaded.pixels_ptr, image_size); // 执行复制（像素数据指针作为拷贝源）
    c.SDL_UnmapGPUTransferBuffer(device, txu_transfer_buf); // 解除映射
    // 创建 Command Buffer 并开启复制 Pass，将传输缓冲区的数据写入纹理
    const txu_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const copy_pass = c.SDL_BeginGPUCopyPass(txu_cmd_buf);
    const source = c.SDL_GPUTextureTransferInfo{
        .transfer_buffer = txu_transfer_buf,
        .offset = 0,
    };
    const destination = c.SDL_GPUTextureRegion{
        .texture = texture,
        .w = @intCast(loaded.width),
        .h = @intCast(loaded.height),
        .d = 1,
    };
    // 提交上传命令
    c.SDL_UploadToGPUTexture(copy_pass, &source, &destination, false);
    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(txu_cmd_buf);
    // 释放 TransferBuffer（纹理内容已上传至显存）
    _ = c.SDL_ReleaseGPUTransferBuffer(device, txu_transfer_buf);
    // 释放像素数据
    loaded.free_pixels();
    std.log.debug("Image pixels have been released", .{});

    // --- 顶点 (Vertex) ---
    // 1. 创建顶点：铺满屏幕的 6 个顶点（两个三角形组成一个矩形）
    const verts: [6]Vertex = .{
        // 三角形 1
        .{ .x = -1.0, .y = 1.0, .z = 0.0, .u = 0.0, .v = 0.0 }, // 左上
        .{ .x = 1.0, .y = 1.0, .z = 0.0, .u = 1.0, .v = 0.0 }, // 右上
        .{ .x = -1.0, .y = -1.0, .z = 0.0, .u = 0.0, .v = 1.0 }, // 左下
        // 三角形 2
        .{ .x = 1.0, .y = 1.0, .z = 0.0, .u = 1.0, .v = 0.0 }, // 右上
        .{ .x = 1.0, .y = -1.0, .z = 0.0, .u = 1.0, .v = 1.0 }, // 右下
        .{ .x = -1.0, .y = -1.0, .z = 0.0, .u = 0.0, .v = 1.0 }, // 左下
    };
    const verts_size = @sizeOf(Vertex) * verts.len;
    // 2. 将顶点上传到 GPU Buffer
    // 创建 GPU Buffer
    const verts_buffer_info = c.SDL_GPUBufferCreateInfo{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = c.SDL_CreateGPUBuffer(device, &verts_buffer_info);
    const verts_binding: c.SDL_GPUBufferBinding = .{ .buffer = verts_buffer, .offset = 0 }; // 顶点绑定
    // 通过 TransferBuffer 将顶点复制到 GPU Buffer
    const verts_transfer_info = c.SDL_GPUTransferBufferCreateInfo{ .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = verts_size };
    const verts_transfer_buf = c.SDL_CreateGPUTransferBuffer(device, &verts_transfer_info);
    const verts_map_ptr = c.SDL_MapGPUTransferBuffer(device, verts_transfer_buf, false);
    _ = c.SDL_memcpy(verts_map_ptr, @ptrCast(&verts), verts_size);
    c.SDL_UnmapGPUTransferBuffer(device, verts_transfer_buf);
    // 3. 提交上传指令
    const verts_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const verts_copy_pass = c.SDL_BeginGPUCopyPass(verts_cmd_buf);
    const src = c.SDL_GPUTransferBufferLocation{ .transfer_buffer = verts_transfer_buf, .offset = 0 };
    const dst = c.SDL_GPUBufferRegion{ .buffer = verts_buffer, .offset = 0, .size = verts_size };
    c.SDL_UploadToGPUBuffer(verts_copy_pass, &src, &dst, false);
    c.SDL_EndGPUCopyPass(verts_copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(verts_cmd_buf);
    _ = c.SDL_ReleaseGPUTransferBuffer(device, verts_transfer_buf); // 释放传输缓存

    // --- 纹理采样器 (Sampler) ---
    // 创建采样器
    const sampler_desc = c.SDL_GPUSamplerCreateInfo{
        .min_filter = c.SDL_GPU_FILTER_LINEAR, // 线性过滤
        .mag_filter = c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    };
    const sampler = c.SDL_CreateGPUSampler(device, &sampler_desc);
    // 创建纹理采样器绑定
    const tex_binding: c.SDL_GPUTextureSamplerBinding = .{ .texture = texture, .sampler = sampler };

    // --- 图形管线 (Graphics Pipeline) ---
    // 1. 构造顶点布局
    const vert_attrs: [2]c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    // 2. 加载着色器
    const vert_shader = try shader_util.loadAndCompileHLSL(device, "base_vert.hlsl", "main", c.SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    const frag_shader = try shader_util.loadAndCompileHLSL(device, "base_frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 1);
    // 3. 构造管线
    const vert_buffer_desc: c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX };
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{
        .format = c.SDL_GetGPUSwapchainTextureFormat(device, window.sdl_window),
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
        .vertex_shader = vert_shader, // 编译好的顶点着色器
        .fragment_shader = frag_shader, // 编译好的片段着色器
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vert_buffer_desc,
            .num_vertex_attributes = 2,
            .vertex_attributes = &vert_attrs,
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &color_target_desc },
    };
    const base_pipeline: *c.SDL_GPUGraphicsPipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse unreachable;

    // 构造棋盘格
    const checkerboard = try Checkerboard.init(device, window);
    defer checkerboard.deinit();
    // 创建后处理管线
    const sharpen_frag_shader = try shader_util.loadAndCompileHLSL(device, "sharpen_frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 1);
    var sharpen = try PostPipeline.init(.Sharpen, device, .{ .vert = vert_shader, .frag = sharpen_frag_shader }, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    const blur_frag_shader = try shader_util.loadAndCompileHLSL(device, "blur_frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 1);
    var blur_x = try PostPipeline.init(.BlurX, device, .{ .vert = vert_shader, .frag = blur_frag_shader }, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    var blur_y = try PostPipeline.init(.BlurY, device, .{ .vert = vert_shader, .frag = blur_frag_shader }, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    // 创建离屏渲染纹理 A 和 B
    const offscreen_texture_info: c.SDL_GPUTextureCreateInfo = .{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 与 Swapchain 格式一致
        .usage = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = @intCast(loaded.width),
        .height = @intCast(loaded.height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const tex_a = c.SDL_CreateGPUTexture(device, &offscreen_texture_info);
    const tex_b = c.SDL_CreateGPUTexture(device, &offscreen_texture_info);
    // 创建 src/dst 纹理引用
    var tex_src = tex_a;
    var tex_dst = tex_b;
    // 创建最终渲染屏幕的直通管线
    var passthrough = try PassthroughPipeline.init(
        device,
        vert_shader,
        &vert_buffer_desc,
        &vert_attrs,
        &color_target_desc,
    );
    // 创建后处理管线列表
    const pipelines = [_]*PostPipeline{ &sharpen, &blur_x, &blur_y };

    // --- 渲染循环 (Render Pass 绘制) ---
    var running = true;
    var event: c.SDL_Event = undefined;
    // 一些常量
    const color_transparent: c.SDL_FColor = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    // 一些功能控制
    var save_screenshot = false; // 是否保存截图
    // 模糊着色器参数
    const texel_size_w = 1.0 / @as(f32, @floatFromInt(loaded.width));
    const texel_size_h = 1.0 / @as(f32, @floatFromInt(loaded.height));
    const hor_float2 = .{ 1.0, 0.0 }; // 横方向
    const ver_float2 = .{ 0.0, 1.0 }; // 纵方向
    // 基础着色器控制变量
    var is_inverted = false; // 是否反转颜色
    var is_grayscale = false; // 是否灰阶化
    var brightness: f32 = 0; // 亮度调整值（暂未实现）
    var contrast: f32 = 1; // 对比度调整值（暂未实现）
    var gamma: f32 = 1; // Gamma 校正值（暂未实现）
    // 横向调节控制变量
    var hor_adjusting = false; // 是否正在横向调节
    var hor_value: f32 = 0; // 横向调节的值
    const hor_sensitivity = 100; // 横向调节灵敏度
    while (running) {
        if (c.SDL_WaitEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                running = false;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_SLASH) { // / 键重置所有参数
                is_inverted = false;
                is_grayscale = false;
                brightness = 0;
                contrast = 1;
                gamma = 1;
                hor_value = 0;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_R) { // R 键反转颜色
                is_inverted = !is_inverted;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_G) { // G 键灰阶化
                is_grayscale = !is_grayscale;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_S) { // S 键保存截图
                save_screenshot = true;
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_MIDDLE) {
                hor_adjusting = true;
                std.log.debug("Mouse wheel event down: {}", .{event.button.button});
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == c.SDL_BUTTON_MIDDLE) {
                hor_adjusting = false;
                std.log.debug("Mouse wheel event up: {}", .{event.button.button});
            } else if (event.type == c.SDL_EVENT_MOUSE_MOTION and hor_adjusting) {
                hor_value += event.motion.xrel / hor_sensitivity;
                std.log.debug("Horizontal value updated: {}", .{hor_value});
            }
        }
        // 获取当前帧的 Command Buffer
        const render_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
        // 开启 Render Pass
        const base_color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = tex_src,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .clear_color = color_transparent,
        };
        const render_pass = c.SDL_BeginGPURenderPass(render_cmd_buf, &base_color_target, 1, null);
        // 绑定图形管线
        c.SDL_BindGPUGraphicsPipeline(render_pass, base_pipeline);
        // 绑定顶点缓冲区
        c.SDL_BindGPUVertexBuffers(render_pass, 0, &verts_binding, 1);
        // 绑定图像的像素纹理以及采样器
        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &tex_binding, 1);
        // 准备要传递的参数
        const uniforms: BaseUniforms = .{
            .invert = if (is_inverted) 1.0 else 0.0,
            .brightness = brightness,
            .contrast = contrast,
            .gamma = gamma,
            .grayscale = if (is_grayscale) 1.0 else 0.0,
        };
        // 将参数推送到片段着色器 (Fragment Shader) 的 slot 0 槽位
        c.SDL_PushGPUFragmentUniformData(render_cmd_buf, // 当前命令缓冲区
            0, // 着色器中的 slot 索引（对应 register b0）
            &uniforms, // 数据指针
            @sizeOf(BaseUniforms) // 数据字节大小
        );
        // 绘制矩形 (绘制 6 个顶点 = 2 个三角形)
        c.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
        // 结束 Pass
        c.SDL_EndGPURenderPass(render_pass);

        // 后处理管线
        for (pipelines) |pipeline| {
            // 是否进入管线
            if (pipeline.effect_type == .Sharpen and hor_value <= 0) continue;
            if ((pipeline.effect_type == .BlurX or pipeline.effect_type == .BlurY) and hor_value >= 0) continue;
            // 绑定管线
            pipeline.bind(tex_dst, tex_src, sampler, render_cmd_buf, &verts_binding);
            if (pipeline.effect_type == .Sharpen) {
                // 传递锐化参数
                const sharpen_uniforms: SharpenUniforms = .{
                    .strength = hor_value,
                    .textureSize = .{ @floatFromInt(loaded.width), @floatFromInt(loaded.height) },
                };
                c.SDL_PushGPUFragmentUniformData(render_cmd_buf, 0, &sharpen_uniforms, @sizeOf(SharpenUniforms));
            } else if (pipeline.effect_type == .BlurX or pipeline.effect_type == .BlurY) {
                // 传递模糊参数
                const blur_uniforms: BlurParams = .{
                    .blurIntensity = -hor_value, // 从负数转换而来
                    .texelSize = .{ texel_size_w, texel_size_h },
                    .direction = if (pipeline.effect_type == .BlurX) hor_float2 else ver_float2, // 横向或纵向模糊
                };
                c.SDL_PushGPUFragmentUniformData(render_cmd_buf, 0, &blur_uniforms, @sizeOf(BlurParams));
            }

            // 绘制管线内容
            pipeline.draw();
            // 乒乓交换：把这一轮的输出 dst，作为下一轮的输入 src
            const temp = tex_src;
            tex_src = tex_dst;
            tex_dst = temp;
        }

        // 获取当前帧的 Swapchain 纹理
        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        if (c.SDL_WaitAndAcquireGPUSwapchainTexture(render_cmd_buf, window.sdl_window, @constCast(&swapchain_texture), null, null)) {
            if (swapchain_texture != null) {
                // 用 SDL_GPUBlitInfo 直接将 tex_src 贴到屏幕，更加高效但无法渲染棋盘格
                {
                    // const blit_info: c.SDL_GPUBlitInfo = .{
                    //     .source = .{
                    //         .texture = tex_src,
                    //         .w = @intCast(loaded.width),
                    //         .h = @intCast(loaded.height),
                    //     },
                    //     .destination = .{
                    //         .texture = swapchain_texture,
                    //         .w = @intCast(loaded.width),
                    //         .h = @intCast(loaded.height),
                    //     },
                    //     .load_op = c.SDL_GPU_LOADOP_CLEAR,
                    //     .filter = c.SDL_GPU_FILTER_NEAREST,
                    // };
                    // c.SDL_BlitGPUTexture(render_cmd_buf, &blit_info);
                }
                // 开启渲染通道
                passthrough.beginRenderPass(swapchain_texture, render_cmd_buf);
                // 绘制棋盘格
                checkerboard.drawByPass(passthrough.render_pass);
                // 渲染到屏幕
                passthrough.endRenderPass(tex_src, sampler);
                // 处理截图
                if (save_screenshot) {
                    // 1. 创建用于接收像素的下载缓冲区
                    const buffer_size: u32 = @intCast(loaded.width * loaded.height * 4); // 以 32 位 RGBA 为例
                    const tb_create_info: c.SDL_GPUTransferBufferCreateInfo = .{
                        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
                        .size = buffer_size,
                    };
                    const download_buffer = c.SDL_CreateGPUTransferBuffer(device, &tb_create_info);
                    // 2. 提交回读命令
                    const cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
                    const download_pass = c.SDL_BeginGPUCopyPass(cmd_buf);
                    const src_region: c.SDL_GPUTextureRegion = .{
                        .texture = tex_src, // 管线渲染/处理后的输出纹理
                        .w = @intCast(loaded.width),
                        .h = @intCast(loaded.height),
                        .d = 1,
                    };
                    const dst_transfer: c.SDL_GPUTextureTransferInfo = .{
                        .transfer_buffer = download_buffer,
                        .offset = 0,
                        .pixels_per_row = @intCast(loaded.width),
                        .rows_per_layer = @intCast(loaded.height),
                    };
                    // 执行下载拷贝
                    c.SDL_DownloadFromGPUTexture(download_pass, &src_region, &dst_transfer);
                    c.SDL_EndGPUCopyPass(download_pass);
                    _ = c.SDL_SubmitGPUCommandBuffer(cmd_buf);
                    // 3. 等待 GPU 完成计算和数据传输
                    _ = c.SDL_WaitForGPUIdle(device);
                    const pixels_ptr = c.SDL_MapGPUTransferBuffer(device, download_buffer, false) orelse unreachable;
                    // 5. 解理映射与清理资源
                    c.SDL_UnmapGPUTransferBuffer(device, download_buffer);
                    c.SDL_ReleaseGPUTransferBuffer(device, download_buffer);
                    save_screenshot = false; // 重置控制参数
                    // 执行写入
                    if (writer.saveRawPixels(
                        pixels_ptr,
                        loaded.width,
                        loaded.height,
                        4,
                        "imageviewer-screenshot.png", // todo: 输出名基于原文件名
                    )) {
                        std.log.info("Screenshot saved, pixel data size: {d}", .{buffer_size});
                    } else |err| {
                        std.log.err("Failed to save screenshot: {}", .{err});
                    }
                }
            }
        }
        // 提交绘制命令，渲染到屏幕
        _ = c.SDL_SubmitGPUCommandBuffer(render_cmd_buf);
    }
}
