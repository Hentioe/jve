const std = @import("std");
const c = @import("c.zig").c;
const initializer = @import("initializer.zig");
const shader_loader = @import("shader_loader.zig");
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const LoadedImage = @import("../loader.zig").Loaded;

// 定义顶点与 UV 坐标
const Vertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
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
    if (!c.SDL_ClaimWindowForGPUDevice(device, window.sdl_window)) {
        helper.printSdlError();
        return Error.SdlClaimWindowForGPUDeviceFailed;
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

    // --- 顶点 ---
    // 1. 创建顶点：铺满屏幕的 6 个顶点（两个三角形组成一个矩形）
    const vertices: [6]Vertex = .{
        // 三角形 1
        .{ .x = -1.0, .y = 1.0, .z = 0.0, .u = 0.0, .v = 0.0 }, // 左上
        .{ .x = 1.0, .y = 1.0, .z = 0.0, .u = 1.0, .v = 0.0 }, // 右上
        .{ .x = -1.0, .y = -1.0, .z = 0.0, .u = 0.0, .v = 1.0 }, // 左下

        // 三角形 2
        .{ .x = 1.0, .y = 1.0, .z = 0.0, .u = 1.0, .v = 0.0 }, // 右上
        .{ .x = 1.0, .y = -1.0, .z = 0.0, .u = 1.0, .v = 1.0 }, // 右下
        .{ .x = -1.0, .y = -1.0, .z = 0.0, .u = 0.0, .v = 1.0 }, // 左下
    };
    const vertices_size = @sizeOf(Vertex) * vertices.len;
    // 2. 将顶点上传到 GPU Buffer
    // 创建 GPU Buffer
    const buffer_info = c.SDL_GPUBufferCreateInfo{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = vertices_size };
    const vertex_buffer = c.SDL_CreateGPUBuffer(device, &buffer_info);
    // 通过 TransferBuffer 将顶点复制到 GPU Buffer
    const vert_transfer_info = c.SDL_GPUTransferBufferCreateInfo{ .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = vertices_size };
    const vert_transfer_buf = c.SDL_CreateGPUTransferBuffer(device, &vert_transfer_info);
    const vert_map_ptr = c.SDL_MapGPUTransferBuffer(device, vert_transfer_buf, false);
    _ = c.SDL_memcpy(vert_map_ptr, @ptrCast(&vertices), vertices_size);
    c.SDL_UnmapGPUTransferBuffer(device, vert_transfer_buf);
    // 3. 提交上传指令
    const vert_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const vert_copy_pass = c.SDL_BeginGPUCopyPass(vert_cmd_buf);
    const src = c.SDL_GPUTransferBufferLocation{ .transfer_buffer = vert_transfer_buf, .offset = 0 };
    const dst = c.SDL_GPUBufferRegion{ .buffer = vertex_buffer, .offset = 0, .size = vertices_size };
    c.SDL_UploadToGPUBuffer(vert_copy_pass, &src, &dst, false);
    c.SDL_EndGPUCopyPass(vert_copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(vert_cmd_buf);
    _ = c.SDL_ReleaseGPUTransferBuffer(device, vert_transfer_buf); // 释放传输缓存

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
    const vert_shader = try shader_loader.loadAndCompileHLSL(device, "src/shaders/vert.hlsl", "main", c.SDL_GPU_SHADERSTAGE_VERTEX, 0);
    const frag_shader = try shader_loader.loadAndCompileHLSL(device, "src/shaders/frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 1);
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
    const pipeline: *c.SDL_GPUGraphicsPipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse unreachable;

    // 渲染循环 (Render Pass 绘制)
    var running = true;
    var event: c.SDL_Event = undefined;
    while (running) {
        if (c.SDL_WaitEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                running = false;
            }
        }
        // 获取当前帧的 CommandBuffer 和 交换链 Swapchain 纹理 (即屏幕画面)
        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        const render_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
        if (c.SDL_WaitAndAcquireGPUSwapchainTexture(render_cmd_buf, window.sdl_window, @constCast(&swapchain_texture), null, null)) {
            if (swapchain_texture != null) {
                // 开启渲染 Pass
                const color_target: c.SDL_GPUColorTargetInfo = .{
                    .texture = swapchain_texture,
                    .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 }, // 清屏背景色（深灰）
                    .load_op = c.SDL_GPU_LOADOP_CLEAR,
                    .store_op = c.SDL_GPU_STOREOP_STORE,
                };
                const render_pass = c.SDL_BeginGPURenderPass(render_cmd_buf, &color_target, 1, null);
                // 绑定图形管线
                c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
                // 绑定顶点缓冲区
                const vertex_binding: c.SDL_GPUBufferBinding = .{ .buffer = vertex_buffer, .offset = 0 };
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
            }
        }
        // 提交绘制命令，渲染到屏幕
        _ = c.SDL_SubmitGPUCommandBuffer(render_cmd_buf);
    }
}
