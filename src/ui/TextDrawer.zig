const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Vertex = @import("../display/structs.zig").Vertex;
const TextUniforms = @import("../display/structs.zig").TextUniforms;
const Uploader = @import("../display/Uploader.zig");
const TextPipeline = @import("TextPipeline.zig");
const FrameSize = shared.Size2D(i32);
const Position = shared.Point(f32);
const AssRendered = @import("AssRendered.zig");
const LayoutOptions = @import("options.zig").LayoutOptions;
const Error = @import("errors.zig").Error;
const Self = @This();

/// 单个文字/图标组件的绘制依赖：顶点（布局）、纹理（栅格化结果）、uniforms（状态）。
///
/// 与共享的 `TextPipeline` 配合使用。内部只调用 `Uploader` 记录上传任务，不执行提交；
/// 提交由外部统一完成，因此上传所需的暂存数据（展开后的 RGBA 与顶点）由自身持有，
/// 随组件生命周期在 `release` 时释放。
pipeline: *TextPipeline,
texture: *sdl.c.SDL_GPUTexture,
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
uniforms: TextUniforms,
allocator: Allocator,
staging_pixels: []u8,
staging_verts: []Vertex,

pub fn init(
    allocator: Allocator,
    uploader: *Uploader,
    pipeline: *TextPipeline,
    frame_size: FrameSize,
    raster: *const AssRendered,
    layout: LayoutOptions,
) Error!Self {
    // 覆盖率（单通道）展开为 RGBA8888 再记录上传；数据需存活到外部提交之后，故由 Self 持有
    const tex_w: usize = @intCast(raster.width);
    const tex_h: usize = @intCast(raster.height);
    const staging_pixels = try allocator.alloc(u8, tex_w * tex_h * 4);
    errdefer allocator.free(staging_pixels);
    for (raster.pixels, 0..) |cov, i| {
        const off = i * 4;
        staging_pixels[off + 0] = cov;
        staging_pixels[off + 1] = cov;
        staging_pixels[off + 2] = cov;
        staging_pixels[off + 3] = cov;
    }
    const texture_create_info = sdl.c.SDL_GPUTextureCreateInfo{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = raster.width,
        .height = raster.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    const texture = try uploader.uploadTexture(&texture_create_info, staging_pixels.ptr, .{ .w = raster.width, .h = raster.height });

    // 按布局位置（帧左上角原点，像素）构造 quad，转换为 NDC；同样需存活到外部提交之后
    const staging_verts = try allocator.alloc(Vertex, 6);
    errdefer allocator.free(staging_verts);
    const verts = buildVerts(raster, frame_size, layout.position);
    @memcpy(staging_verts, &verts);
    const verts_size: u32 = @intCast(@sizeOf(Vertex) * staging_verts.len);
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const verts_buffer = try uploader.uploadBuffer(&verts_buffer_info, @ptrCast(staging_verts.ptr), verts_size);

    return Self{
        .pipeline = pipeline,
        .texture = texture,
        .verts_buffer = verts_buffer,
        .verts_binding = .{ .buffer = verts_buffer, .offset = 0 },
        .uniforms = TextUniforms.fromColor(raster.color, layout.debug),
        .allocator = allocator,
        .staging_pixels = staging_pixels,
        .staging_verts = staging_verts,
    };
}

fn buildVerts(raster: *const AssRendered, frame_size: FrameSize, position: Position) [6]Vertex {
    const fw: f32 = @floatFromInt(frame_size.w);
    const fh: f32 = @floatFromInt(frame_size.h);
    const bw: f32 = @floatFromInt(raster.width);
    const bh: f32 = @floatFromInt(raster.height);
    const x0: f32 = position.x;
    const y0: f32 = position.y;
    const x1: f32 = x0 + bw;
    const y1: f32 = y0 + bh;
    const ndc_l = x0 / fw * 2.0 - 1.0;
    const ndc_r = x1 / fw * 2.0 - 1.0;
    const ndc_t = 1.0 - y0 / fh * 2.0; // 注意 Y 轴翻转
    const ndc_b = 1.0 - y1 / fh * 2.0;
    return .{
        .{ .x = ndc_l, .y = ndc_t, .z = 0.0, .u = 0.0, .v = 0.0 },
        .{ .x = ndc_r, .y = ndc_t, .z = 0.0, .u = 1.0, .v = 0.0 },
        .{ .x = ndc_l, .y = ndc_b, .z = 0.0, .u = 0.0, .v = 1.0 },
        .{ .x = ndc_r, .y = ndc_t, .z = 0.0, .u = 1.0, .v = 0.0 },
        .{ .x = ndc_r, .y = ndc_b, .z = 0.0, .u = 1.0, .v = 1.0 },
        .{ .x = ndc_l, .y = ndc_b, .z = 0.0, .u = 0.0, .v = 1.0 },
    };
}

/// 释放上传暂存数据（外部提交完成后调用；重复调用安全）。
pub fn release(self: *Self) void {
    self.allocator.free(self.staging_pixels);
    self.allocator.free(self.staging_verts);
    self.staging_pixels = &.{};
    self.staging_verts = &.{};
}

pub fn deinit(self: *Self) void {
    self.release();
    self.pipeline.gpu.releaseGPUBuffer(self.verts_buffer);
    self.pipeline.gpu.releaseGPUTexture(self.texture);
    self.* = undefined;
}

/// 在当前 render pass 内绑定共享管线与自身资源并绘制 quad。
pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.pipeline.bind(pass);
    sdl.c.SDL_BindGPUVertexBuffers(pass, 0, &self.verts_binding, 1);
    const sampler_binding: sdl.c.SDL_GPUTextureSamplerBinding = .{ .texture = self.texture, .sampler = self.pipeline.sampler };
    sdl.c.SDL_BindGPUFragmentSamplers(pass, 0, &sampler_binding, 1);
    sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &self.uniforms, @sizeOf(TextUniforms));
    self.pipeline.draw();
}
