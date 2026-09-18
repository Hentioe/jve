const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const shader_util = @import("shader_util.zig");
const post_util = @import("post_util.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

device: *c.SDL_GPUDevice,
window: ?*c.SDL_Window,
engine: *c.TTF_TextEngine,
font: *c.TTF_Font,
sampler: *c.SDL_GPUSampler,

pub fn init(device: *c.SDL_GPUDevice, window: ?*c.SDL_Window, font_file: [:0]const u8) Error!Self {
    const engine = c.TTF_CreateGPUTextEngine(device) orelse {
        helper.printError();
        return Error.SdlTextEngineInitFailed;
    };
    const font = c.TTF_OpenFont(font_file, 36) orelse {
        helper.printError();
        return Error.SdlTextEngineInitFailed;
    };

    // 加粗，但效果不太好（模拟）
    // c.TTF_SetFontStyle(font, c.TTF_STYLE_BOLD);

    // 采样器：线性过滤 + clamp，避免边缘出现黑边
    const sampler = c.SDL_CreateGPUSampler(device, &.{
        .min_filter = c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .max_anisotropy = 1.0,
        .min_lod = 0.0,
        .max_lod = 1.0,
    }) orelse {
        helper.printError();
        return Error.SdlTextEngineInitFailed;
    };

    return Self{
        .device = device,
        .window = window,
        .engine = engine,
        .font = font,
        .sampler = sampler,
    };
}

const TextTexture = struct {
    texture: *c.SDL_GPUTexture,
    width: i32,
    height: i32,
};

pub fn createTextTexture(self: Self, text: [:0]const u8, color: c.SDL_Color) Error!TextTexture {
    // 渲染文字为 SDL_Surface
    const surface = c.TTF_RenderText_Blended(self.font, text, 0, color) orelse {
        helper.printError();
        std.log.err("Failed to TTF_RenderText_Blended\n", .{});
        return Error.SdlTTFInitFailed;
    };
    defer c.SDL_DestroySurface(surface);
    // 统一成 RGBA32（内存布局 = R,G,B,A 字节序，正好对应 R8G8B8A8_UNORM）
    // todo: 解决 release 编译后的程序，运行到此处报错：Parameter 'surface' is invalid
    // 原因疑似是因为本项目所用的 sdl3 源码版本和 SDL3_ttf 依赖的版本有差异导致
    // 考虑升级 castholm/SDL 或将 SDL3_ttf 的特定版本内置到项目中
    const rgba_surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_RGBA32) orelse {
        helper.printError();
        return Error.SdlTTFInitFailed;
    };
    defer c.SDL_DestroySurface(rgba_surface);

    const w = rgba_surface.*.w;
    const h = rgba_surface.*.h;
    const row_bytes = w * 4; // RGBA32 每个像素 4 字节
    const data_size = h * row_bytes; // RGBA32 每个像素 4 字节
    // 创建纹理
    const texture = c.SDL_CreateGPUTexture(self.device, &(c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = @intCast(w),
        .height = @intCast(h),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
    })) orelse {
        helper.printError();
        return Error.SdlGPUTextureCreateFailed;
    };

    // 数据先进 transfer buffer
    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(data_size),
    }) orelse {
        helper.printError();
        return Error.SdlGPUTextureCreateFailed;
    };
    const map = c.SDL_MapGPUTransferBuffer(self.device, transfer_buffer, false);
    _ = c.memcpy(map, rgba_surface.*.pixels, @intCast(data_size));
    // Copy Pass 上传到纹理
    const cmd = c.SDL_AcquireGPUCommandBuffer(self.device);
    const copy = c.SDL_BeginGPUCopyPass(cmd);
    c.SDL_UploadToGPUTexture(copy, &.{
        .transfer_buffer = transfer_buffer,
        .offset = 0,
        .pixels_per_row = @intCast(w),
        .rows_per_layer = @intCast(h),
    }, &.{
        .texture = texture,
        .mip_level = 0,
        .layer = 0,
        .x = 0,
        .y = 0,
        .z = 0,
        .w = @intCast(w),
        .h = @intCast(h),
        .d = 1,
    }, false);
    c.SDL_EndGPUCopyPass(copy);

    // 加载期一次性上传，等 fence 保证 transfer buffer 用完再释放
    const fence = c.SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    if (!c.SDL_WaitForGPUFences(self.device, true, &fence, 1)) {
        helper.printError();
        return Error.SdlGPUFenceWaitFailed;
    }
    c.SDL_UnmapGPUTransferBuffer(self.device, transfer_buffer);
    c.SDL_ReleaseGPUFence(self.device, fence);
    c.SDL_ReleaseGPUTransferBuffer(self.device, transfer_buffer);
    c.SDL_DestroySurface(rgba_surface);
    return TextTexture{
        .texture = texture,
        .width = w,
        .height = h,
    };
}

const Vertex = struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub fn createPipeline(self: Self) Error!*c.SDL_GPUGraphicsPipeline {
    const vertex_buffer_desc = c.SDL_GPUVertexBufferDescription{
        .slot = 0,
        .pitch = @sizeOf(Vertex),
        .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
        .instance_step_rate = 0,
    };
    const attrs: [3]c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "x") },
        .{ .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") },
        .{ .location = 2, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = @offsetOf(Vertex, "r") },
    };
    const color_target_desc = c.SDL_GPUColorTargetDescription{
        .format = c.SDL_GetGPUSwapchainTextureFormat(self.device, self.window),
        .blend_state = c.SDL_GPUColorTargetBlendState{
            .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
            .enable_blend = true,
        },
    };
    const vert_shader = try shader_util.loadAndCompileHLSL(self.device, "text_vert.hlsl", "main", c.SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    const frag_shader = try shader_util.loadAndCompileHLSL(self.device, "text_frag.hlsl", "main", c.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);

    return c.SDL_CreateGPUGraphicsPipeline(self.device, &.{
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &vertex_buffer_desc,
            .num_vertex_buffers = 1,
            .vertex_attributes = &attrs,
            .num_vertex_attributes = 3,
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{ .fill_mode = c.SDL_GPU_FILLMODE_FILL, .cull_mode = c.SDL_GPU_CULLMODE_NONE },
        .multisample_state = .{ .sample_count = c.SDL_GPU_SAMPLECOUNT_1 },
        .target_info = .{
            .color_target_descriptions = &color_target_desc,
            .num_color_targets = 1,
        },
    }) orelse {
        helper.printError();
        return Error.SdlCreateGPUGraphicsPipelineFailed;
    };
}

pub fn drawText(
    self: *const Self,
    cmd_buffer: ?*c.SDL_GPUCommandBuffer,
    render_pass: ?*c.SDL_GPURenderPass,
    text_texture: *const TextTexture,
    px: u32,
    py: u32,
    scale: f32,
    sw: u32,
    sh: u32,
    alpha: f32,
) Error!void {
    const w: f32 = @as(f32, @floatFromInt(text_texture.width)) * scale;
    const h: f32 = @as(f32, @floatFromInt(text_texture.height)) * scale;
    const f_px: f32 = @floatFromInt(px);
    const f_py: f32 = @floatFromInt(py);
    const f_sw: f32 = @floatFromInt(sw);
    const f_sh: f32 = @floatFromInt(sh);
    const x0 = (f_px / f_sw) * 2.0 - 1.0;
    const y0 = 1.0 - (f_py / f_sh) * 2.0;
    const x1 = ((f_px + w) / f_sw) * 2.0 - 1.0;
    const y1 = 1.0 - ((f_py + h) / f_sh) * 2.0;

    const verts: [4]Vertex = .{
        .{ .x = x0, .y = y0, .u = 0.0, .v = 0.0, .r = 1.0, .g = 1.0, .b = 1.0, .a = alpha },
        .{ .x = x1, .y = y0, .u = 1.0, .v = 0.0, .r = 1.0, .g = 1.0, .b = 1.0, .a = alpha },
        .{ .x = x1, .y = y1, .u = 1.0, .v = 1.0, .r = 1.0, .g = 1.0, .b = 1.0, .a = alpha },
        .{ .x = x0, .y = y1, .u = 0.0, .v = 1.0, .r = 1.0, .g = 1.0, .b = 1.0, .a = alpha },
    };
    const verts_size = @sizeOf(Vertex) * verts.len;
    const idx: [6]u16 = .{ 0, 1, 2, 0, 2, 3 };
    const idx_size = @sizeOf(u16) * idx.len;

    // 每帧临时缓冲（正式项目应做动态缓冲池/批量合并）
    const vert_buffer = c.SDL_CreateGPUBuffer(self.device, &.{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size });
    const idx_buffer = c.SDL_CreateGPUBuffer(self.device, &.{ .usage = c.SDL_GPU_BUFFERUSAGE_INDEX, .size = idx_size });
    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = verts_size + idx_size,
    });

    const map = c.SDL_MapGPUTransferBuffer(self.device, transfer_buffer, false);
    const map_u8_ptr: [*c]const u8 = @ptrCast(map);
    const map_dst: *anyopaque = @constCast(map_u8_ptr + verts_size);
    _ = c.SDL_memcpy(map, &verts, verts_size);
    _ = c.SDL_memcpy(map_dst, &idx, idx_size);
    c.SDL_UnmapGPUTransferBuffer(self.device, transfer_buffer);

    const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buffer);
    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .transfer_buffer = transfer_buffer, .offset = 0 },
        &.{ .buffer = vert_buffer, .offset = 0, .size = verts_size },
        false,
    );
    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .transfer_buffer = transfer_buffer, .offset = verts_size },
        &.{ .buffer = idx_buffer, .offset = 0, .size = idx_size },
        false,
    );
    c.SDL_EndGPUCopyPass(copy_pass);

    c.SDL_BindGPUVertexBuffers(render_pass, 0, &.{ .buffer = vert_buffer, .offset = 0 }, 1);
    c.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = idx_buffer, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);
    c.SDL_BindGPUFragmentSamplers(render_pass, 0, &.{ .texture = text_texture.texture, .sampler = self.sampler }, 1);

    c.SDL_DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0);

    c.SDL_ReleaseGPUBuffer(self.device, vert_buffer);
    c.SDL_ReleaseGPUBuffer(self.device, idx_buffer);
    c.SDL_ReleaseGPUTransferBuffer(self.device, transfer_buffer);
}

pub fn deinit(self: Self) void {
    c.TTF_CloseFont(self.font);
    c.TTF_DestroyGPUTextEngine(self.engine);
}
