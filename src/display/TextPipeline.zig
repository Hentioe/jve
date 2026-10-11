const std = @import("std");
const sdl = @import("sdl");
const Vertex = @import("structs.zig").Vertex;
const TextUniforms = @import("structs.zig").TextUniforms;
const Size2D = @import("shared").Size2D;
const Point = @import("shared").Point;
const Window = @import("window.zig");
const Uploader = @import("Uploader.zig");
const shader_loader = @import("shader_loader.zig");
const Pipeline = @import("Pipeline.zig");
const ui = @import("../ui.zig");
const AssRendered = ui.AssRendered;
const Error = @import("errors.zig").Error;
const Self = @This();

pub const Options = struct {
    /// 文字 quad 左上角在帧内的像素坐标（原点为帧左上角），默认 (0, 0) 即左上角。
    position: Point(f32) = .{},
    /// 调试开关：为文字图片叠加红色背景，便于观察 quad 的位置与大小。
    debug: bool = false,

    /// 计算使文字在帧内居中的位置。居中不再是默认行为，需要时显式调用。
    pub fn centered(raster_size: Size2D(u32), frame_size: Size2D(i32), offset: Point(f32), debug: bool) Options {
        const f_rsize = raster_size.to(f32);
        const bw: f32 = f_rsize.w;
        const bh: f32 = f_rsize.h;
        const fw: f32 = @floatFromInt(frame_size.w);
        const fh: f32 = @floatFromInt(frame_size.h);
        return .{ .position = .{ .x = (fw - bw) * 0.5 + offset.x, .y = (fh - bh) * 0.5 + offset.y }, .debug = debug };
    }
};

gpu: *const sdl.Gpu,
pipeline: Pipeline,
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
texture: *sdl.c.SDL_GPUTexture,
sampler: *sdl.c.SDL_GPUSampler,
uniforms: TextUniforms,

/// 用栅格化结果建立文字渲染管线：上传覆盖率纹理、按 `options.position` 构造 quad。
pub fn init(
    allocator: std.mem.Allocator,
    window: *Window,
    gpu: *const sdl.Gpu,
    frame_size: Size2D(i32),
    raster: *const AssRendered,
    options: Options,
) Error!Self {
    const vert_buffer_desc: sdl.c.SDL_GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = sdl.c.SDL_GPU_VERTEXINPUTRATE_VERTEX };
    const vert_attrs: [2]sdl.c.SDL_GPUVertexAttribute = .{
        .{ .location = 0, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    const vertex_input_state: sdl.c.SDL_GPUVertexInputState = .{
        .num_vertex_buffers = 1,
        .vertex_buffer_descriptions = &vert_buffer_desc,
        .num_vertex_attributes = 2,
        .vertex_attributes = &vert_attrs,
    };

    // 文字管线（复用 base.vert，片元采样覆盖率）
    const vert_shader = try shader_loader.load(gpu, @embedFile("base.vert.spv"), "main", .vertex, 0, 0);
    const frag_shader = try shader_loader.load(gpu, @embedFile("text.frag.spv"), "main", .fragment, 1, 1);
    var pipeline = try Pipeline.init(gpu, window.sdl_window, .{ .vert = vert_shader, .frag = frag_shader }, vertex_input_state);
    errdefer pipeline.deinit();
    var uploader = Uploader.init(allocator, gpu);
    defer uploader.deinit();

    // 覆盖率（单通道）展开为 RGBA8888 再上传
    const tex_w: usize = @intCast(raster.width);
    const tex_h: usize = @intCast(raster.height);
    const pixels = try allocator.alloc(u8, tex_w * tex_h * 4);
    defer allocator.free(pixels);
    for (raster.pixels, 0..) |cov, i| {
        const off = i * 4;
        pixels[off + 0] = cov;
        pixels[off + 1] = cov;
        pixels[off + 2] = cov;
        pixels[off + 3] = cov;
    }
    const text_tex_info = sdl.c.SDL_GPUTextureCreateInfo{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = raster.width,
        .height = raster.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const texture = try uploader.uploadTexture(&text_tex_info, pixels.ptr, .{ .w = raster.width, .h = raster.height });

    // 按 `position`（帧左上角原点，像素）构造 quad，转换为 NDC
    const fw: f32 = @floatFromInt(frame_size.w);
    const fh: f32 = @floatFromInt(frame_size.h);
    const bw: f32 = @floatFromInt(raster.width);
    const bh: f32 = @floatFromInt(raster.height);
    const x0: f32 = options.position.x;
    const y0: f32 = options.position.y;
    const x1: f32 = x0 + bw;
    const y1: f32 = y0 + bh;
    const ndc_l = x0 / fw * 2.0 - 1.0;
    const ndc_r = x1 / fw * 2.0 - 1.0;
    const ndc_t = 1.0 - y0 / fh * 2.0; // 注意 Y 轴翻转
    const ndc_b = 1.0 - y1 / fh * 2.0;
    const verts: [6]Vertex = .{
        .{ .x = ndc_l, .y = ndc_t, .z = 0.0, .u = 0.0, .v = 0.0 },
        .{ .x = ndc_r, .y = ndc_t, .z = 0.0, .u = 1.0, .v = 0.0 },
        .{ .x = ndc_l, .y = ndc_b, .z = 0.0, .u = 0.0, .v = 1.0 },
        .{ .x = ndc_r, .y = ndc_t, .z = 0.0, .u = 1.0, .v = 0.0 },
        .{ .x = ndc_r, .y = ndc_b, .z = 0.0, .u = 1.0, .v = 1.0 },
        .{ .x = ndc_l, .y = ndc_b, .z = 0.0, .u = 0.0, .v = 1.0 },
    };
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = try uploader.uploadBuffer(&verts_buffer_info, @ptrCast(&verts), verts_size);

    try uploader.submit();

    // 文字纹理采样器
    const sampler_desc = sdl.c.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl.c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = sdl.c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = sdl.c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    };
    const sampler = try gpu.createGPUSampler(&sampler_desc);

    return Self{
        .gpu = gpu,
        .pipeline = pipeline,
        .verts_buffer = verts_buffer,
        .verts_binding = .{ .buffer = verts_buffer, .offset = 0 },
        .texture = texture,
        .sampler = sampler,
        .uniforms = TextUniforms.fromColor(raster.color, options.debug),
    };
}

pub fn deinit(self: *Self) void {
    self.pipeline.deinit();
    self.gpu.releaseGPUBuffer(self.verts_buffer);
    self.gpu.releaseGPUTexture(self.texture);
    self.gpu.releaseGPUSampler(self.sampler);
    self.* = undefined;
}

/// 在当前 render pass 内绑定文字管线与资源并绘制 quad。
pub fn draw(self: *Self, render_pass: *sdl.c.SDL_GPURenderPass, cmd_buf: *sdl.c.SDL_GPUCommandBuffer) void {
    self.pipeline.bind(render_pass);
    sdl.c.SDL_BindGPUVertexBuffers(render_pass, 0, &self.verts_binding, 1);
    const sampler_binding: sdl.c.SDL_GPUTextureSamplerBinding = .{ .texture = self.texture, .sampler = self.sampler };
    sdl.c.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_binding, 1);
    sdl.c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &self.uniforms, @sizeOf(TextUniforms));
    self.pipeline.draw();
}
