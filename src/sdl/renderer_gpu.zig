const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const shader_loader = @import("shader_loader.zig");
const post_util = @import("post_util.zig");
const root = @import("../root.zig");
const gpu = @import("gpu.zig");
const structs = @import("structs.zig");
const clipboard = @import("clipboard.zig");
const album = root.album;
const writer = root.writer;
const ArrayList = std.ArrayList;
const State = @import("State.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Pipeline = @import("Pipeline.zig");
const LeaderKey = @import("LeaderKey.zig");
const Task = @import("Task.zig");
const Uploader = @import("Uploader.zig");
const Checkerboard = @import("checkerboard_gpu.zig");
const PostPipeline = @import("PostPipeline.zig");
const OnscreenPipeline = @import("onscreen_pipeline.zig");
const Screenshot = @import("Screenshot.zig");
const RenderNext = @import("enums.zig").RenderNext;
const Delta = @import("Delta.zig");
const Size = structs.Size;
const Point = structs.Point(f32);
const Vertex = structs.Vertex;
const BaseUniforms = structs.BaseUniforms;
const SharpenUniforms = structs.SharpenUniforms;
const FogUniforms = structs.FogUniforms;
const BlurUniforms = structs.BlurUniforms;
const MarkerVertUniforms = structs.MarkerVertUniforms;
const MarkerFragUniforms = structs.MarkerFragUniforms;

const EventType = @FieldType(c.union_SDL_Event, "type");
const EventAction = union(enum) {
    none,
    quit,
    toggle,
    leader: EventType,
    reset,
    invert,
    grayscale,
    save_screenshot,
    copy_screenshot,
    start_task,
    toggle_custom_shader,
    slide_start: struct { button: u8 },
    slide_stop: struct { button: u8 },
    sliding: struct { xrel: f32 },
    marker: struct { x: f32, y: f32 },
};

// 基于 SDL_GPU 渲染图片
pub fn render(allocator: std.mem.Allocator, state: *State) Error!RenderNext {
    // 从相册取出当前图片
    const image = try album.current();
    // 更新状态
    try state.startRendering(&image, .sdl_gpu);
    // 创建窗口
    const window = state.gpu_window.?; // 确保在 startRendering 中完成初始化
    // 更新窗口标题
    try window.setTitle(image.file_name);
    // 创建 GPU 设备
    const device = state.gpu_device.?;
    // 创建上传器
    var uploader = Uploader.init(allocator, device);
    defer uploader.deinit();

    // --- 纹理 (Texture) ---
    const texture_info = c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 对应常见的 RGBA8888 像素格式
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER, // 作为采样器供 Pipeline 渲染
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    // 上传纹理
    const texture = try uploader.uploadTexture(
        &texture_info,
        image.pixels_ptr,
        try Size(u32).fromI32(image.width, image.height),
    );

    // --- 顶点 (Vertex) ---
    // 铺满屏幕的 6 个顶点（两个三角形组成一个矩形）
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
    // 上传顶点
    const vertices_size = @sizeOf(Vertex) * verts.len;
    const vertices_buffer_info = c.SDL_GPUBufferCreateInfo{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = vertices_size };
    const vertices_buffer = try uploader.uploadBuffer(&vertices_buffer_info, @ptrCast(&verts), vertices_size);
    defer c.SDL_ReleaseGPUBuffer(device, vertices_buffer);
    const vertices_binding: c.SDL_GPUBufferBinding = .{ .buffer = vertices_buffer, .offset = 0 }; // 顶点绑定

    // 一次性提交纹理与顶点上传
    try uploader.submit();

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
    defer c.SDL_ReleaseGPUSampler(device, sampler); // 释放采样器
    // 创建纹理采样器绑定
    const tex_binding: c.SDL_GPUTextureSamplerBinding = .{ .texture = texture, .sampler = sampler };

    // --- 图形管线 (Graphics Pipeline) ---
    // 1. 构造顶点布局
    const vert_attrs: [2]c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    // 2. 加载着色器
    const vert_shader = try shader_loader.load(device, @embedFile("base.vert.spv"), "main", .vertex, 0, 0);
    const frag_shader = try shader_loader.load(device, @embedFile("base.frag.spv"), "main", .fragment, 1, 1);
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
    // 基础着色器（负责图像渲染）
    const base_pl: *c.SDL_GPUGraphicsPipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse return Error.SdlCreateGPUGraphicsPipelineFailed;
    defer c.SDL_ReleaseGPUGraphicsPipeline(device, base_pl);
    // 构造棋盘格（透明图片的背景）
    var checkerboard = try Checkerboard.init(device, window);
    defer checkerboard.deinit();

    // 创建离屏渲染纹理 A 和 B
    const offscreen_info: c.SDL_GPUTextureCreateInfo = .{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 与 Swapchain 格式一致
        .usage = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const tex_a = c.SDL_CreateGPUTexture(device, &offscreen_info);
    defer c.SDL_ReleaseGPUTexture(device, tex_a);
    const tex_b = c.SDL_CreateGPUTexture(device, &offscreen_info);
    defer c.SDL_ReleaseGPUTexture(device, tex_b);
    // 创建 src/dst 纹理引用
    var tex_src = tex_a;
    var tex_dst = tex_b;
    // 创建屏幕渲染的直通管线
    var onscreen = try OnscreenPipeline.init(device, vert_shader, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    // 创建内建的后处理管线
    const pl_builder = PostPipeline.Builder.init(device, &vert_buffer_desc, &vert_attrs, &color_target_desc);
    const sharpen_frag_shader = try shader_loader.load(device, @embedFile("sharpen.frag.spv"), "main", .fragment, 1, 1);
    defer c.SDL_ReleaseGPUShader(device, sharpen_frag_shader);
    var sharpen = try pl_builder.build(.sharpen, .{ .vert = vert_shader, .frag = sharpen_frag_shader });
    const blur_frag_shader = try shader_loader.load(device, @embedFile("blur.frag.spv"), "main", .fragment, 1, 1);
    defer c.SDL_ReleaseGPUShader(device, blur_frag_shader);
    var blur_x_pl = try pl_builder.build(.blur_x, .{ .vert = vert_shader, .frag = blur_frag_shader });
    var blur_y_pl = try pl_builder.build(.blur_y, .{ .vert = vert_shader, .frag = blur_frag_shader });
    const busy_fog_frag_shader = try shader_loader.load(device, @embedFile("busy_fog.frag.spv"), "main", .fragment, 0, 1);
    defer c.SDL_ReleaseGPUShader(device, busy_fog_frag_shader);
    var busy_fog_pl = try pl_builder.build(.busy_fog, .{ .vert = vert_shader, .frag = busy_fog_frag_shader });
    const mask_frag_shader = try shader_loader.load(device, @embedFile("mask.frag.spv"), "main", .fragment, 2, 0);
    defer c.SDL_ReleaseGPUShader(device, mask_frag_shader);
    var mask_pl = try pl_builder.build(.mask, .{ .vert = vert_shader, .frag = mask_frag_shader });
    // 构造标记管线
    const marker_vert_shader = try shader_loader.load(device, @embedFile("marker.vert.spv"), "main", .vertex, 0, 1);
    defer c.SDL_ReleaseGPUShader(device, marker_vert_shader);
    const marker_frag_shader = try shader_loader.load(device, @embedFile("marker.frag.spv"), "main", .fragment, 0, 1);
    defer c.SDL_ReleaseGPUShader(device, marker_frag_shader);
    var marker_pl = try Pipeline.init(device, window.sdl_window, .{ .vert = marker_vert_shader, .frag = marker_frag_shader });
    defer marker_pl.deinit();

    // 构造后处理管线列表
    var builtin = [_]*PostPipeline{ &sharpen, &blur_x_pl, &blur_y_pl, &mask_pl };
    const builtin_count = builtin.len;
    var pipelines: ArrayList(*PostPipeline) = .empty;
    try pipelines.appendSlice(allocator, &builtin); // 添加内置管线
    defer {
        for (pipelines.items, 0..) |pl, i| {
            pl.deinit(device);
            if (i >= builtin_count) allocator.destroy(pl);
        }
        pipelines.deinit(allocator);
    }
    // 添加自定义管线
    if (state.shaders) |shaders| {
        for (shaders.items) |shader| {
            const pl = try allocator.create(PostPipeline); // 在堆上创建，避免被作用域回收
            errdefer allocator.destroy(pl);
            pl.* = try pl_builder.build(
                .custom,
                .{ .vert = vert_shader, .frag = shader },
            );
            try pipelines.append(allocator, pl);
        }
    }

    // --- 渲染循环 (Render Pass 绘制) ---
    var running = true;
    var event: c.SDL_Event = undefined;
    var action: EventAction = .none;
    var toggle = false;
    var dirty = false;
    var delta = Delta.init();
    // 一些常量
    const color_transparent: c.SDL_FColor = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    // 一些功能控制
    var save_screenshot = false; // 是否保存截图
    var copy_screenshot = false; // 是否复制截图到剪贴板
    var is_busy = false; // 是否正在繁忙处理
    // 模糊着色器参数
    const texel_size_w = 1.0 / @as(f32, @floatFromInt(image.width));
    const texel_size_h = 1.0 / @as(f32, @floatFromInt(image.height));
    const hor_float2 = .{ 1.0, 0.0 }; // 横方向
    const ver_float2 = .{ 0.0, 1.0 }; // 纵方向
    // 基础着色器控制变量
    var is_inverted = false; // 是否反转颜色
    var is_grayscale = false; // 是否灰阶化
    var brightness: f32 = 0; // 亮度调整值（暂未实现）
    var contrast: f32 = 1; // 对比度调整值（暂未实现）
    var gamma: f32 = 1; // Gamma 校正值（暂未实现）
    // 其它开关
    var leader = LeaderKey.init(c.SDLK_LALT); // Leader 键
    var custom_shader_enabled = false; // 是否启用自定义着色器
    // 标记
    const marker_radius: f32 = 18.0; // 标记半径（像素），同时作为二次点击移除的判定范围
    var marker_pos: ?Point = null; // 标记位置
    // 横向滑动控制变量
    var is_sliding = false; // 是否正在横向滑动
    var slide_value: f32 = 0; // 横向滑动的值
    const slide_sensitivity = 100; // 横向滑动灵敏度
    // 任务（后台调用模型）
    var task: ?*Task = null;
    defer if (task) |t| t.finish();
    var tex_mask: ?*c.SDL_GPUTexture = null;
    defer if (tex_mask) |tex| c.SDL_ReleaseGPUTexture(device, tex);

    while (running) {
        // 计算 delta
        delta.update();
        // std.log.info("delta: {}, fps: {}", .{ delta.value, delta.fps });
        defer action = .none; // 重置动作
        if (is_busy) dirty = true; // 繁忙的时候，渲染总是脏的状态（刷新迷雾动画）

        // 动作的依赖项
        const action_deps: ActionDeps = .{
            .leader = &leader,
            .is_sliding = is_sliding,
            .is_busy = is_busy,
        };
        if (!dirty) {
            var wait_event: c.SDL_Event = undefined;
            if (c.SDL_WaitEvent(&wait_event)) updateActionFromEvent(&action, wait_event, action_deps);
            delta.reset(); // 重置 delta（否则阻塞后唤醒会计算出巨大的 delta 值）
        }
        // 从事件中更新动作
        while (c.SDL_PollEvent(&event)) updateActionFromEvent(&action, event, action_deps);

        // 根据动作修改状态
        switch (action) {
            .none => {},
            .quit => running = false,
            .toggle => {
                toggle = true;
                running = false;
            },
            .leader => |event_type| {
                leader.inputType(event_type); // 根据类型，自动管理按下状态
                window.leader_pressed = leader.pressed; // 更新窗口的 leader_pressed 状态
            },
            .invert => is_inverted = !is_inverted,
            .grayscale => is_grayscale = !is_grayscale,
            .save_screenshot => save_screenshot = true,
            .copy_screenshot => copy_screenshot = true,
            .start_task => {
                if (task == null) {
                    is_busy = true;
                    if (Task.start(allocator, device, tex_src, state, .{ .width = image.width, .height = image.height, .bands = image.bands, .click = marker_pos })) |t| {
                        std.log.info("Task started successfully", .{});
                        task = t;
                    } else |err| {
                        std.log.err("Failed to start task: {}", .{err});
                        is_busy = false;
                    }
                }
            },
            .toggle_custom_shader => custom_shader_enabled = !custom_shader_enabled,
            .slide_start => |payload| {
                is_sliding = true;
                std.log.debug("Mouse wheel event down: {}", .{payload.button});
            },
            .slide_stop => |payload| {
                is_sliding = false;
                std.log.debug("Mouse wheel event up: {}", .{payload.button});
            },
            .sliding => |payload| {
                slide_value += payload.xrel / slide_sensitivity;
                std.log.debug("Horizontal value updated: {}", .{slide_value});
            },
            .marker => |payload| {
                var removed = false;
                if (marker_pos) |prev| {
                    const dx = payload.x - prev.x;
                    const dy = payload.y - prev.y;
                    // 二次点击落在标记范围内，则移除标记
                    if (dx * dx + dy * dy <= marker_radius * marker_radius) {
                        marker_pos = null;
                        removed = true;
                        std.log.debug("Marker removed", .{});
                    }
                }
                if (!removed) {
                    marker_pos = Point{ .x = payload.x, .y = payload.y };
                    std.log.debug("Marker position updated: ({}, {})", .{ payload.x, payload.y });
                }
            },
            .reset => {
                is_inverted = false;
                is_grayscale = false;
                brightness = 0;
                contrast = 1;
                gamma = 1;
                slide_value = 0;
                marker_pos = null;
            },
        }

        // 获取当前帧的 Command Buffer
        const cmd_buf = c.SDL_AcquireGPUCommandBuffer(device) orelse return Error.SdlAcquireGPUCommandBufferFailed;
        // 开启 Render Pass
        const base_color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = tex_src,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .clear_color = color_transparent,
        };
        const render_pass = c.SDL_BeginGPURenderPass(cmd_buf, &base_color_target, 1, null);
        // 绑定图形管线
        c.SDL_BindGPUGraphicsPipeline(render_pass, base_pl);
        // 绑定顶点缓冲区
        c.SDL_BindGPUVertexBuffers(render_pass, 0, &vertices_binding, 1);
        // 绑定图像的像素纹理以及采样器
        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &tex_binding, 1);
        // 准备片段着色器的的参数
        const base_uniforms: BaseUniforms = .{
            .invert = if (is_inverted) 1.0 else 0.0,
            .brightness = brightness,
            .contrast = contrast,
            .gamma = gamma,
            .grayscale = if (is_grayscale) 1.0 else 0.0,
        };
        // 将参数推送到片段着色器的 slot 0
        c.SDL_PushGPUFragmentUniformData(cmd_buf, // 当前命令缓冲区
            0, // 着色器中的 slot 索引（对应 register b0）
            &base_uniforms, // 数据指针
            @sizeOf(BaseUniforms) // 数据字节大小
        );
        // 绘制矩形 (绘制 6 个顶点 = 2 个三角形)
        c.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
        // 结束渲染通道
        c.SDL_EndGPURenderPass(render_pass);
        // 检查任务
        if (task) |t| {
            if (t.poll() == .done) {
                std.log.info("Task result is reading...", .{});
                if (tex_mask) |tex| c.SDL_ReleaseGPUTexture(device, tex);
                const data_ptr = t.result.?.data_ptr;
                const size: Size(u32) = .{ .w = t.result.?.width, .h = t.result.?.height };
                if (gpu.createAndUploadTexture(&uploader, &offscreen_info, data_ptr, size)) |created| {
                    tex_mask = created;
                    task = null;
                    is_busy = false;
                } else |err| {
                    std.log.err("Failed to create GPU texture: {}", .{err});
                }
                dirty = false;
                t.finish();
                std.log.info("Task result read complete", .{});
            }
        }

        // 后处理管线
        for (pipelines.items) |pl| {
            // 判断是否进入管线
            if (pl.effect == .custom and !custom_shader_enabled) continue; // 没有启用自定义着色器，跳过
            if (pl.effect == .sharpen and slide_value <= 0) continue; // 没有有效值，跳过
            if ((pl.effect == .blur_x or pl.effect == .blur_y) and slide_value >= 0) continue; // 没有有效值，跳过
            if (pl.effect == .mask and tex_mask == null) continue; // 没有有效的 mask，跳过
            // 绑定管线
            if (pl.effect == .mask) {
                pl.bindWithMaskTex(cmd_buf, tex_dst, tex_src, tex_mask, sampler, &vertices_binding);
            } else {
                pl.bind(cmd_buf, tex_dst, tex_src, sampler, &vertices_binding);
            }
            if (pl.effect == .sharpen) {
                // 传递锐化参数
                const uniforms: SharpenUniforms = .{
                    .strength = slide_value,
                    .textureSize = .{ @floatFromInt(image.width), @floatFromInt(image.height) },
                };
                c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &uniforms, @sizeOf(SharpenUniforms));
            } else if (pl.effect == .blur_x or pl.effect == .blur_y) {
                // 传递模糊参数
                const uniforms: BlurUniforms = .{
                    .blur_intensity = -slide_value, // 从负数转换而来
                    .texel_size = .{ texel_size_w, texel_size_h },
                    .direction = if (pl.effect == .blur_x) hor_float2 else ver_float2, // 横向或纵向模糊
                };
                c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &uniforms, @sizeOf(BlurUniforms));
            }

            // 绘制管线内容
            pl.draw();
            pl.end();
            // 乒乓交换：把这一轮的输出 dst，作为下一轮的输入 src
            const tmp = tex_src;
            tex_src = tex_dst;
            tex_dst = tmp;
        }

        // 获取当前帧的 Swapchain 纹理
        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        if (c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, window.sdl_window, @constCast(&swapchain_texture), null, null)) {
            if (swapchain_texture != null) {
                {
                    // 用 SDL_GPUBlitInfo 直接将 tex_src 贴到屏幕，更加高效但无法渲染棋盘格
                    // const blit_info: c.SDL_GPUBlitInfo = .{
                    //     .source = .{
                    //         .texture = tex_src,
                    //         .w = @intCast(image.width),
                    //         .h = @intCast(image.height),
                    //     },
                    //     .destination = .{
                    //         .texture = swapchain_texture,
                    //         .w = @intCast(image.width),
                    //         .h = @intCast(image.height),
                    //     },
                    //     .load_op = c.SDL_GPU_LOADOP_CLEAR,
                    //     .filter = c.SDL_GPU_FILTER_NEAREST,
                    // };
                    // c.SDL_BlitGPUTexture(render_cmd_buf, &blit_info);
                }
                // 开启屏幕渲染
                try onscreen.begin(cmd_buf, swapchain_texture);
                // 绘制棋盘格
                checkerboard.bind(onscreen.render_pass); // 绑定到屏幕通道
                checkerboard.draw();
                // 重新绑定屏幕管线，绘制内容（图片 + 后处理）
                onscreen.bind();
                onscreen.draw(tex_src, sampler);
                // 在屏幕之上继续添加新内容
                if (marker_pos) |pos| {
                    // 绘制标记
                    marker_pl.bind(onscreen.render_pass);
                    // 传递标记位置
                    const marker_loc_uniforms: MarkerVertUniforms = .fromScreen(pos.x, pos.y, image.width, image.height);
                    marker_pl.pushVertexUniforms(cmd_buf, 0, &marker_loc_uniforms, @sizeOf(MarkerVertUniforms));
                    // 传递标记大小
                    const marker_size_uniforms: MarkerFragUniforms = .{ .radius = marker_radius, .border_width = 2.0 };
                    marker_pl.pushFragmentUniforms(cmd_buf, 0, &marker_size_uniforms, @sizeOf(MarkerFragUniforms));
                    // 绘制标记
                    marker_pl.draw();
                }
                if (is_busy) {
                    // 添加忙雾（不采样纹理，仅使用 uniform）
                    busy_fog_pl.bindScreen(onscreen.render_pass, &vertices_binding);
                    const busy_fog_uniforms = FogUniforms{ .time = @as(f32, @floatFromInt(c.SDL_GetTicks())) / 1000.0 };
                    c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &busy_fog_uniforms, @sizeOf(FogUniforms));
                    busy_fog_pl.draw();
                }
                onscreen.end();
            }
        }
        // 提交绘制命令，渲染到屏幕
        if (!h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf))) return Error.SdlSubmitGPUCommandBufferFailed;

        // 处理截图保存和复制
        if (save_screenshot or copy_screenshot) {
            // 创建截图器
            var screenshot = Screenshot.init(
                allocator,
                device,
                tex_src,
                &image,
            ) catch |err| fallback: {
                std.log.err("Failed to create screenshot: {}", .{err});
                break :fallback null;
            };
            if (screenshot) |*s| {
                defer s.deinit();
                if (save_screenshot) s.saveToFile();
                if (copy_screenshot) s.copyToClipboard();
            }

            // 重置控制参数
            save_screenshot = false;
            copy_screenshot = false;
        }
    }

    try state.stopRendering();

    return if (toggle) {
        // todo: 如果图像没有变化，无需写入纹理
        // 写入纹理到状态缓存
        state.writeTexture(device, tex_src) catch |err| {
            std.log.err("Failed to write texture to state: {}", .{err});
        };
        return .toggle;
    } else {
        return .quit;
    };
}

const ActionDeps = struct {
    leader: *LeaderKey,
    is_sliding: bool,
    is_busy: bool,
};

fn updateActionFromEvent(action: *EventAction, event: c.SDL_Event, deps: ActionDeps) void {
    if (event.type == c.SDL_EVENT_QUIT) {
        action.* = .quit;
    } else if (isToggleEvent(event)) {
        action.* = .toggle;
    } else if (event.key.key == deps.leader.key) {
        action.* = .{ .leader = event.type };
    } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_SLASH) { // / 键重置所有参数
        action.* = .reset;
    } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_R and !deps.leader.pressed) { // R 键反转颜色
        action.* = .invert;
    } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_G) { // G 键灰阶化
        action.* = .grayscale;
    } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_S) { // S 键保存截图
        action.* = .save_screenshot;
    } else if (deps.leader.pressedAndKeyDown(event, c.SDLK_R) and !deps.is_busy) { // Leader+R 去除背景
        action.* = .start_task;
    } else if (deps.leader.pressedAndKeyDown(event, c.SDLK_T)) { // Leader+T 切换自定义着色器的启用状态
        action.* = .toggle_custom_shader;
    } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_C and (event.key.mod & c.SDL_KMOD_CTRL) != 0) { // Ctrl+C 复制截图
        action.* = .copy_screenshot;
    } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_MIDDLE) { // 横向调节开始
        action.* = .{ .slide_start = .{ .button = event.button.button } };
    } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == c.SDL_BUTTON_MIDDLE) { // 横向调节结束
        action.* = .{ .slide_stop = .{ .button = event.button.button } };
    } else if (event.type == c.SDL_EVENT_MOUSE_MOTION and deps.is_sliding) { // 滑动中
        handleSlidingEvent(event, action);
    } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_LEFT) { // 鼠标左键单击，获取位置
        action.* = .{ .marker = .{ .x = event.button.x, .y = event.button.y } };
    }
}

// 是否是切换事件
fn isToggleEvent(event: c.SDL_Event) bool {
    return event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_RIGHT; // 右键
}

fn handleSlidingEvent(event: c.SDL_Event, action: *EventAction) void {
    switch (action.*) {
        .sliding => |*payload| {
            // 如果这一帧里已经有 sliding 动作了，累加位移
            payload.xrel += event.motion.xrel;
        },
        .slide_stop => {}, // 中键松开时，可能残留滑动事件，避免覆盖 slide_stop
        else => {
            action.* = .{ .sliding = .{ .xrel = event.motion.xrel } };
        },
    }
}
