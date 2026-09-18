const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const initializer = @import("initializer.zig");
const shader_util = @import("shader_util.zig");
const post_util = @import("post_util.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const LoadedImage = @import("../loader.zig").Loaded;
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
const FragUniforms = extern struct {
    invert: i32,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

// 锐化效果的片段着色器 Uniforms
const SharpenUniforms = extern struct {
    strength: f32,
    textureSize: [2]f32,
    padding: f32 = 0.0,
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
    var sharpen = try PostPipeline.init(
        .Sharpen,
        device,
        .{ .vert = vert_shader, .frag = sharpen_frag_shader },
        &vert_buffer_desc,
        &vert_attrs,
        &color_target_desc,
    );
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
    const pipelines = [_]*PostPipeline{&sharpen};

    // --- 渲染循环 (Render Pass 绘制) ---
    var running = true;
    var event: c.SDL_Event = undefined;
    var need_invert = false;
    var horizontal_adjusting = false; // 是否在横向调节
    var horizontal_value: f32 = 0; // 横向调节的值
    const horizontal_sensitivity = 100; // 横向调节灵敏度
    while (running) {
        if (c.SDL_WaitEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                running = false;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_R) { // R 键反转颜色
                need_invert = !need_invert;
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_MIDDLE) {
                horizontal_adjusting = true;
                std.log.debug("Mouse wheel event down: {}", .{event.button.button});
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == c.SDL_BUTTON_MIDDLE) {
                horizontal_adjusting = false;
                std.log.debug("Mouse wheel event up: {}", .{event.button.button});
            } else if (event.type == c.SDL_EVENT_MOUSE_MOTION and horizontal_adjusting) {
                horizontal_value += event.motion.xrel / horizontal_sensitivity;
                std.log.debug("Horizontal value updated: {}", .{horizontal_value});
            }
        }
        // 获取当前帧的 Command Buffer
        const render_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
        // 开启 Render Pass
        const base_color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = tex_src,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        };
        const render_pass = c.SDL_BeginGPURenderPass(render_cmd_buf, &base_color_target, 1, null);
        // 绑定图形管线
        c.SDL_BindGPUGraphicsPipeline(render_pass, base_pipeline);
        // 准备要传递的参数
        const invert: i32 = if (need_invert) 1 else 0;
        const uniforms: FragUniforms = .{ .invert = invert };
        // 将参数推送到片段着色器 (Fragment Shader) 的 slot 0 槽位
        c.SDL_PushGPUFragmentUniformData(render_cmd_buf, // 当前命令缓冲区
            0, // 着色器中的 slot 索引（对应 register b0）
            &uniforms, // 数据指针
            @sizeOf(FragUniforms) // 数据字节大小
        );
        // 绑定顶点缓冲区
        const vertex_binding: c.SDL_GPUBufferBinding = .{ .buffer = verts_buffer, .offset = 0 };
        c.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_binding, 1);
        // 绑定之前上传的像素纹理 (gpu_texture) 以及采样器 (sampler)
        const tex_binding: c.SDL_GPUTextureSamplerBinding = .{
            .texture = texture,
            .sampler = sampler,
        };
        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &tex_binding, 1);
        // 绘制矩形 (绘制 6 个顶点 = 2 个三角形)
        c.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
        // 结束 Pass
        c.SDL_EndGPURenderPass(render_pass);

        // 后处理管线
        for (pipelines) |pipeline| {
            // 绑定管道
            pipeline.bind(tex_dst, tex_src, sampler, render_cmd_buf, &vertex_binding);
            if (pipeline.effect_type == .Sharpen) {
                // 传递锐化参数
                const sharpen_uniforms: SharpenUniforms = .{
                    .strength = horizontal_value,
                    .textureSize = .{ @floatFromInt(loaded.width), @floatFromInt(loaded.height) },
                };
                c.SDL_PushGPUFragmentUniformData(render_cmd_buf, 0, &sharpen_uniforms, @sizeOf(SharpenUniforms));
            }
            // 绘制当前管道内容
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
                passthrough.beginRender(swapchain_texture, render_cmd_buf);
                // 绘制棋盘格
                checkerboard.render(passthrough.render_pass);
                // 渲染到屏幕
                passthrough.endRender(tex_src, sampler);
            }
        }
        // 提交绘制命令，渲染到屏幕
        _ = c.SDL_SubmitGPUCommandBuffer(render_cmd_buf);
    }
}
