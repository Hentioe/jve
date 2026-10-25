const sdl = @import("sdl");
const shared = @import("shared");
const Vertex = shared.Vertex;
const BannerUniforms = @import("../display/structs.zig").BannerUniforms;
const base_verts = @import("../display/consts.zig").base_verts;
const Device = @import("../Device.zig");
const BannerPipeline = @import("../pipelines/BannerPipeline.zig");
const FrameSize = shared.Size2D(i32);
const Error = @import("errors.zig").Error;
const Self = @This();

/// 单个横幅背景的绘制依赖：全屏 quad 顶点（恒定不变）+ 状态 uniform。
///
/// 与 `TextDrawer` 对称。背景用「全屏 quad + uniform 带」表达：顶点固定为铺满屏幕
/// 的矩形，真正决定可见区域的是 `BannerUniforms.band`（uv 空间的纵向区间）与颜色，
/// 因此文字尺寸变化时只需更新 uniform，无需重建 GPU 资源。
pipeline: *BannerPipeline,
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
uniforms: BannerUniforms,

pub fn init(
    pipeline: *BannerPipeline,
    frame_size: FrameSize,
    top_px: f32,
    height_px: f32,
    color: [4]f32,
    debug: bool,
) Error!Self {
    const uploader = try Device.getUploader();
    const verts_size: u32 = @intCast(@sizeOf(Vertex) * base_verts.len);
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = verts_size,
        .props = 0,
    };
    // base_verts 是编译期常量，生命周期贯穿整个程序，无需额外暂存
    const verts_buffer = try uploader.uploadBufferBorrowed(&verts_buffer_info, @ptrCast(&base_verts), verts_size);

    return Self{
        .pipeline = pipeline,
        .verts_buffer = verts_buffer,
        .verts_binding = .{ .buffer = verts_buffer, .offset = 0 },
        .uniforms = bandUniforms(frame_size, top_px, height_px, color, debug),
    };
}

fn bandUniforms(frame_size: FrameSize, top_px: f32, height_px: f32, color: [4]f32, debug: bool) BannerUniforms {
    const fh: f32 = @floatFromInt(frame_size.h);
    const top = top_px / fh;
    const bottom = (top_px + height_px) / fh;
    return .{ .color = color, .band = .{ top, bottom }, .debug = debug };
}

/// 更新横幅矩形（像素，帧左上角原点）与颜色。只写 uniform，代价可忽略。
pub fn update(self: *Self, frame_size: FrameSize, top_px: f32, height_px: f32, color: [4]f32, debug: bool) void {
    self.uniforms = bandUniforms(frame_size, top_px, height_px, color, debug);
}

pub fn deinit(self: *Self) void {
    self.pipeline.gpu.releaseGPUBuffer(self.verts_buffer);
    self.* = undefined;
}

/// 在当前 render pass 内绑定共享管线与自身资源并绘制全屏 quad。
pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.pipeline.bind(pass);
    sdl.c.SDL_BindGPUVertexBuffers(pass, 0, &self.verts_binding, 1);
    sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &self.uniforms, @sizeOf(BannerUniforms));
    self.pipeline.draw();
}
