const std = @import("std");
const c = @import("c.zig").c;
const initialization = @import("initialization.zig");
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
    try initialization.initialize(.SdlGpu);
    // 初始化窗口
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
    // 创建纹理
    const texture_desc = c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, // 对应常见的 RGBA8888 像素格式
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER, // 作为采样器供 Pipeline 渲染
        .width = @intCast(loaded.width),
        .height = @intCast(loaded.height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const gpu_texture = c.SDL_CreateGPUTexture(device, &texture_desc);
    // 将 CPU 像素数据上传至 GPU 纹理
    const image_size: u32 = @intCast(loaded.width * loaded.height * 4); // RGBA8888 字节大小
    // 创建传输缓冲区 (指定为 UPLOAD 模式，即 CPU -> GPU)
    const transfer_desc = c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = image_size,
    };
    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(device, &transfer_desc);
    // 映射内存并直接拷贝你的像素数据指针 (pixels_ptr)
    const map_ptr = c.SDL_MapGPUTransferBuffer(device, transfer_buffer, false);
    _ = c.SDL_memcpy(map_ptr, loaded.pixels_ptr, image_size); // 直接使用你的像素数据指针
    c.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);
    // 创建 Command Buffer 并开启复制 Pass，将传输缓冲区的数据写入纹理
    const txu_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const copy_pass = c.SDL_BeginGPUCopyPass(txu_cmd_buf);
    const source = c.SDL_GPUTextureTransferInfo{
        .transfer_buffer = transfer_buffer,
        .offset = 0,
    };
    const destination = c.SDL_GPUTextureRegion{
        .texture = gpu_texture,
        .w = @intCast(loaded.width),
        .h = @intCast(loaded.height),
        .d = 1,
    };
    // 提交上传命令
    c.SDL_UploadToGPUTexture(copy_pass, &source, &destination, false);
    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(txu_cmd_buf);
    // 传输完成后即可释放 TransferBuffer（纹理内容已上传至显存）
    _ = c.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer);

    // 创建顶点
    // 铺满屏幕的 6 个顶点（两个三角形组成一个矩形）
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
    // 将顶点上传到 GPU Vertex Buffer
    // 创建 GPU Buffer
    const buffer_desc = c.SDL_GPUBufferCreateInfo{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = vertices_size };
    const vertex_buffer = c.SDL_CreateGPUBuffer(device, &buffer_desc);
    // 通过 TransferBuffer 将内存顶点复制进去
    const vtx_transfer_desc = c.SDL_GPUTransferBufferCreateInfo{ .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = vertices_size };
    const vtx_transfer_buf = c.SDL_CreateGPUTransferBuffer(device, &vtx_transfer_desc);
    const vtx_map_ptr = c.SDL_MapGPUTransferBuffer(device, vtx_transfer_buf, false);
    _ = c.SDL_memcpy(vtx_map_ptr, @ptrCast(&vertices), vertices_size);
    c.SDL_UnmapGPUTransferBuffer(device, vtx_transfer_buf);
    // 提交上传指令
    const vtx_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const vtx_copy_pass = c.SDL_BeginGPUCopyPass(vtx_cmd_buf);
    const src = c.SDL_GPUTransferBufferLocation{ .transfer_buffer = vtx_transfer_buf, .offset = 0 };
    const dst = c.SDL_GPUBufferRegion{ .buffer = vertex_buffer, .offset = 0, .size = vertices_size };
    c.SDL_UploadToGPUBuffer(vtx_copy_pass, &src, &dst, false);
    c.SDL_EndGPUCopyPass(vtx_copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(vtx_cmd_buf);
    _ = c.SDL_ReleaseGPUTransferBuffer(device, vtx_transfer_buf); // 释放临时传输缓存

    // 创建纹理采样器 (Sampler)
    const sampler_desc = c.SDL_GPUSamplerCreateInfo{
        .min_filter = c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    };
    const sampler = c.SDL_CreateGPUSampler(device, &sampler_desc);

    // 配置图形管线 (Graphics Pipeline)
    // 顶点布局：告诉 GPU 顶点数据的结构
    const vert_attrs: [2]c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    const vert_buffer_desc: c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX };
    const vert_shader = try shader_loader.loadAndCompileHLSL(device, "src/shaders/vert.hlsl", "main", c.SDL_GPU_SHADERSTAGE_VERTEX, 0);
    const frag_shader = try shader_loader.loadAndCompileHLSL(device, "src/shaders/frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 1);
    const color_target_desc: c.SDL_GPUColorTargetDescription = .{ .format = c.SDL_GetGPUSwapchainTextureFormat(device, window.sdl_window) };
    const pipeline_desc: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert_shader, // 你编译好的 Vertex Shader (SPIR-V / DXIL / MSL)
        .fragment_shader = frag_shader, // 采样 Texture 的 Fragment Shader
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vert_buffer_desc,
            .num_vertex_attributes = 2,
            .vertex_attributes = &vert_attrs,
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{ .num_color_targets = 1, .color_target_descriptions = &color_target_desc },
    };
    const pipeline: *c.SDL_GPUGraphicsPipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_desc) orelse unreachable;

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
                    .texture = gpu_texture, // 对应上一步中包含像素数据的 SDL_GPUTexture
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
